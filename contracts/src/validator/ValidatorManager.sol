// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ISP1Verifier} from "@sp1-contracts/ISP1Verifier.sol";
import {IValidatorManager} from "./IValidatorManager.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {PausableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ValidatorManagerStorage} from "./ValidatorManagerStorage.sol";
import {BLS} from "solbls/BLS.sol";
import {IStakeManager, IStakeManagerTypes} from "../stake/IStakeManager.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {ArrayContainsLib} from "../libs/ArrayContainsLib.sol";

/// @title Validator Manager
/// @notice Manages validator lifecycle and bridge state attestations
/// @dev Handles validator registration, BLS attestations, pre-confirmations, and reward distribution
contract ValidatorManager is
    IValidatorManager,
    Initializable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    PausableUpgradeable,
    ValidatorManagerStorage
{
    using BLS for *;
    using ArrayContainsLib for *;
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @notice Restricts access to stake manager only
    modifier onlyAdminManager() {
        require(msg.sender == STAKING_MANAGER || msg.sender == owner(), NotAdminManager(msg.sender));
        _;
    }

    /// @notice Restricts root finalisation to base chain
    modifier onlyBaseChain() {
        require(address(STAKING_MANAGER) != address(0), NotBaseChain(block.chainid));
        _;
    }
    /// @notice Chain ID where this contract is deployed

    uint256 public CHAIN_ID;

    /// @notice Contract name identifier
    string public NAME;

    /// @notice Contract version identifier
    string public VERSION;

    /// @notice Address of the stake manager contract
    address public STAKING_MANAGER;

    /// @notice SP1 verifier contract address
    address public SP1_VERIFIER;

    /// @notice Domain separator used by BLS hash-to-curve for attestations
    bytes public POP_ATTEST_DOMAIN;

    /// @notice SP1 program verification key for bridge proof verification
    bytes32 public PROGRAM_KEY;

    /// @notice Current epoch index used for reward periods
    uint256 public EPOCH;

    /// @notice Duration of each epoch in seconds
    uint256 public EPOCH_DURATION;

    /// @notice Timestamp of epoch zero; basis for epoch calculations
    uint256 public EPOCH_ZERO_TS;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @inheritdoc IValidatorManager
    function initialize(
        address owner,
        address verifier,
        bytes32 programKey
    )
        external
        override
        initializer
    {
        CHAIN_ID = block.chainid;
        SP1_VERIFIER = verifier;
        NAME = "ValidatorManager";
        VERSION = "1";
        POP_ATTEST_DOMAIN = "ValidatorManager:BN254:Attestation:v1:";
        EPOCH_ZERO_TS = block.timestamp;
        EPOCH = 1;
        EPOCH_DURATION = 10 minutes;

        __Ownable_init(owner);
        __Pausable_init();
        __UUPSUpgradeable_init();
        _setProgramKey(programKey);
    }

    /// @inheritdoc IValidatorManager
    function updateStakingManager(address stakingManager) public onlyOwner {
        require(stakingManager != address(0), ZeroAddress());
        emit UpdatedStakingManager(STAKING_MANAGER, stakingManager);
        STAKING_MANAGER = stakingManager;
    }

    /// @inheritdoc IValidatorManager
    function submitAttestation(BridgeAttestation calldata attestation)
        external
        override
        whenNotPaused
    {
        VmStorage storage $ = _loadStorage();

        require(msg.sender == attestation.validator, NotAllowed());
        require($.validators[msg.sender].status == ValidatorStatus.Active, ValidatorNotRegistered());
        address certifiedValidator = _verifyCertificate(attestation.certificate);
        require(certifiedValidator == attestation.validator, NotAllowed());

        bytes32 attestationKey = _rootParamsKey(
            attestation.blockNumber,
            attestation.bridgeRoot,
            attestation.stateRoot,
            attestation.sourceChainId
        );

        require(!$.attestations[msg.sender][attestationKey], AlreadyAttested());

        uint256[4] memory blsPublicKey = $.validators[msg.sender].blsPublicKey;
        uint256[2] memory msgToVerify = _attestationMessage(attestation);

        (bool pairingSuccess, bool callSuccess) =
            BLS.verifySingle(attestation.signature, blsPublicKey, msgToVerify);

        require(pairingSuccess && callSuccess, IStakeManagerTypes.InvalidBLSSignature());

        $.attestations[msg.sender][attestationKey] = true;
        _updatePreConfirmation($, attestationKey, 1);

        emit AttestationSubmitted(
            msg.sender,
            attestation.sourceChainId,
            attestation.bridgeRoot,
            attestation.blockNumber,
            attestation.stateRoot,
            attestation.timestamp
        );
    }

    /// @inheritdoc IValidatorManager
    function submitAggregatedAttestation(AggregatedBridgeAttestation calldata)
        external
        view
        override
        whenNotPaused
    {
        revert IStakeManagerTypes.NotAllowed();
    }

    /// @inheritdoc IValidatorManager
    function isRootVerified(RootParams calldata params)
        external
        view
        override
        returns (bool verified)
    {
        VmStorage storage $ = _loadStorage();
        bytes32 attestationKey = _rootParamsKey(
            params.blockNumber, params.bridgeRoot, params.stateRoot, params.sourceChainId
        );

        return $.preConfirmations[attestationKey].confirmed;
    }

    /// @inheritdoc IValidatorManager
    function updateValidatorStatus(
        address validator,
        ValidatorStatus status
    )
        external
        override
        onlyAdminManager
    {
        VmStorage storage $ = _loadStorage();
        ValidatorInfo storage info = $.validators[validator];
        info.status = status;

        if (status == ValidatorStatus.Active) {
            $.activeValidators.add(validator);
        } else if (status == ValidatorStatus.Unstaking || status == ValidatorStatus.Inactive) {
            $.activeValidators.remove(validator);
        }
    }

    /// @inheritdoc IValidatorManager
    function getValidator(address validator)
        external
        view
        override
        returns (ValidatorInfo memory info)
    {
        VmStorage storage $ = _loadStorage();
        return $.validators[validator];
    }

    /// @inheritdoc IValidatorManager
    function getActiveValidators() external view override returns (address[] memory validators) {
        VmStorage storage $ = _loadStorage();
        return $.activeValidators.values();
    }

    /// @inheritdoc IValidatorManager
    function finaliseAttestations(VerificationParams calldata params)
        external
        override
        onlyOwner
        onlyBaseChain
    {
        VmStorage storage $ = _loadStorage();

        ISP1Verifier(SP1_VERIFIER).verifyProof(PROGRAM_KEY, params.publicValues, params.proofBytes);

        VerificationPublicValues memory publicValues =
            abi.decode(params.publicValues, (VerificationPublicValues));
        bytes32 finalizationHash = keccak256(params.publicValues);
        if ($.processedFinalizations[finalizationHash]) {
            revert FinalizationAlreadyProcessed(finalizationHash);
        }

        bytes32 finalizedRootKey = _finalizedRootKey(publicValues);
        if (finalizedRootKey != bytes32(0)) {
            if ($.finalizedRoots[finalizedRootKey]) {
                revert FinalizationAlreadyProcessed(finalizedRootKey);
            }
            $.finalizedRoots[finalizedRootKey] = true;
        }
        $.processedFinalizations[finalizationHash] = true;

        IStakeManager manager = IStakeManager(STAKING_MANAGER);

        for (uint256 i = 0; i < publicValues.equivocators.length; i++) {
            IStakeManagerTypes.SlashParams memory slashParams = publicValues.equivocators[i];
            ValidatorInfo storage info = $.validators[slashParams.validator];
            if (info.status != ValidatorStatus.Active) {
                continue;
            }

            manager.slashValidator(slashParams);
            info.invalidAttestations++;
        }

        for (uint256 i = 0; i < publicValues.attestations.length; i++) {
            BridgeAttestation memory attestation = publicValues.attestations[i];
            ValidatorInfo storage info = $.validators[attestation.validator];
            require(attestation.sourceChainId == publicValues.attestedChainId, InvalidChainId());
            if (!publicValues.equivocators.contains(attestation.validator)) {
                info.attestationCount++;
            }
            emit RootVerified(
                publicValues.attestedChainId, attestation.bridgeRoot, attestation.blockNumber
            );
        }

        _updateEpoch();
    }

    /// @inheritdoc IValidatorManager
    function proofOfPossessionMessage(uint256[4] memory blsPubkey)
        public
        view
        override
        returns (uint256[2] memory)
    {
        bytes memory messageBytes = abi.encodePacked(
            CHAIN_ID, blsPubkey[0], blsPubkey[1], blsPubkey[2], blsPubkey[3], msg.sender
        );

        return BLS.hashToPoint(POP_ATTEST_DOMAIN, messageBytes);
    }

    /// @inheritdoc IValidatorManager
    function proofOfPossessionMessage(AggregatedBridgeAttestation calldata attestation)
        public
        view
        override
        returns (uint256[2] memory)
    {
        bytes memory messageBytes = abi.encodePacked(
            attestation.sourceChainId,
            attestation.blockNumber,
            attestation.bridgeRoot,
            attestation.stateRoot,
            attestation.timestamp,
            keccak256(abi.encode(attestation.participants)),
            attestation.aggregatedPublicKey[0],
            attestation.aggregatedPublicKey[1],
            attestation.aggregatedPublicKey[2],
            attestation.aggregatedPublicKey[3]
        );
        return BLS.hashToPoint(POP_ATTEST_DOMAIN, messageBytes);
    }

    /// @inheritdoc IValidatorManager
    function addValidator(ValidatorInfo memory info) external override onlyAdminManager {
        VmStorage storage $ = _loadStorage();
        require($.validators[info.wallet].status == ValidatorStatus.Inactive, NotAllowed());
        $.validators[info.wallet] = info;
        $.activeValidators.add(info.wallet);

        emit AddedValidator(info.wallet, info.blsPublicKey);
    }

    /// @inheritdoc IValidatorManager
    function removeValidator(address validator) external override onlyAdminManager {
        VmStorage storage $ = _loadStorage();
        require(
            $.validators[validator].status == ValidatorStatus.Unstaking, UnableToRemoveValidator()
        );
        $.activeValidators.remove(validator);
        ValidatorInfo memory info = $.validators[validator];
        delete $.validators[validator];

        emit RemovedValidator(validator, info.blsPublicKey);
    }

    /// @inheritdoc IValidatorManager
    function updateProgramKey(bytes32 programKey) public override onlyOwner {
        _setProgramKey(programKey);
    }

    function _setProgramKey(bytes32 programKey) internal {
        emit ProgramKeyUpdated(PROGRAM_KEY, programKey);
        require(programKey != bytes32(0), InvalidProgramKey(programKey));
        PROGRAM_KEY = programKey;
    }

    /// @inheritdoc IValidatorManager
    function epochDuration() external view override returns (uint256 duration) {
        return EPOCH_DURATION;
    }

    /// @inheritdoc IValidatorManager
    function getEpochsPerYear() external view override returns (uint256 epochs) {
        // 365.25 days
        return 31557600 / EPOCH_DURATION;
    }

    /// @inheritdoc IValidatorManager
    function epochsElapsedSince(uint256 timestamp) public view override returns (uint256 epochs) {
        if (block.timestamp <= timestamp || EPOCH_DURATION == 0) return 0;
        epochs = Math.saturatingSub(block.timestamp, timestamp) / EPOCH_DURATION;
    }

    /// @inheritdoc IValidatorManager
    function distributeRewards() external override onlyOwner whenNotPaused {
        VmStorage storage $ = _loadStorage();
        address[] memory activeValidators = $.activeValidators.values();

        require(activeValidators.length > 0, NoParticipants());

        ValidatorInfo[] memory validatorInfos = new ValidatorInfo[](activeValidators.length);
        for (uint256 i = 0; i < activeValidators.length; i++) {
            validatorInfos[i] = $.validators[activeValidators[i]];
        }

        IStakeManagerTypes.RewardsParams memory params = IStakeManagerTypes.RewardsParams({
            epoch: EPOCH,
            epochDuration: EPOCH_DURATION,
            recipients: validatorInfos
        });

        IStakeManager(STAKING_MANAGER).distributeRewards(params);
    }

    event Preconfirmed(PreConfirmation);
    /// @notice Update pre-confirmation status for an attestation key
    /// @dev Uses a 67% rounded-up threshold over the active validator set
    /// @param $ Storage reference
    /// @param attestationKey Unique key (sourceChainId, bridgeRoot, stateRoot, blockNumber)
    /// @param additionalCount Newly added confirmations

    function _updatePreConfirmation(
        VmStorage storage $,
        bytes32 attestationKey,
        uint256 additionalCount
    )
        internal
    {
        PreConfirmation storage pc = $.preConfirmations[attestationKey];
        pc.count += additionalCount;

        uint256 threshold = ($.activeValidators.length() * 67 + 99) / 100;
        if (!pc.confirmed && pc.count >= threshold) {
            pc.confirmed = true;
        }

        emit Preconfirmed(pc);
    }

    function _attestationMessage(BridgeAttestation calldata attestation)
        internal
        view
        returns (uint256[2] memory)
    {
        bytes memory messageBytes = abi.encodePacked(
            attestation.sourceChainId,
            attestation.blockNumber,
            attestation.bridgeRoot,
            attestation.stateRoot,
            attestation.timestamp,
            attestation.validator
        );

        return BLS.hashToPoint(POP_ATTEST_DOMAIN, messageBytes);
    }

    function _rootParamsKey(
        uint256 blockNumber,
        bytes32 bridgeRoot,
        bytes32 stateRoot,
        uint256 sourceChainId
    )
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(blockNumber, bridgeRoot, stateRoot, sourceChainId));
    }

    function _finalizedRootKey(VerificationPublicValues memory publicValues)
        internal
        pure
        returns (bytes32 finalizedRootKey)
    {
        if (publicValues.attestations.length == 0) {
            return bytes32(0);
        }

        BridgeAttestation memory template = publicValues.attestations[0];
        if (
            template.sourceChainId != publicValues.attestedChainId
                || template.bridgeRoot != publicValues.validBridgeRoot
        ) {
            revert InconsistentAttestationBatch();
        }

        finalizedRootKey = _rootParamsKey(
            template.blockNumber,
            publicValues.validBridgeRoot,
            template.stateRoot,
            publicValues.attestedChainId
        );

        for (uint256 i = 1; i < publicValues.attestations.length; i++) {
            BridgeAttestation memory attestation = publicValues.attestations[i];
            if (
                attestation.sourceChainId != publicValues.attestedChainId
                    || attestation.bridgeRoot != publicValues.validBridgeRoot
                    || attestation.blockNumber != template.blockNumber
                    || attestation.stateRoot != template.stateRoot
            ) {
                revert InconsistentAttestationBatch();
            }
        }
    }

    /// @notice Increment the epoch counter and emit event
    function _updateEpoch() internal {
        emit NewEpoch(EPOCH, ++EPOCH);
    }

    /// @notice Verifies certificate proves validator authorization on base chain
    /// @dev Checks ECDSA signature, temporal validity, and chain binding
    /// @param certificateData ABI-encoded Certificate struct
    /// @return validatedValidator Address of validator if certificate is valid
    function _verifyCertificate(bytes memory certificateData)
        internal
        view
        returns (address validatedValidator)
    {
        Certificate memory certificate = abi.decode(certificateData, (Certificate));

        bytes32 structHash;

        assembly {
            let pointer := mload(0x40)
            mstore(pointer, mload(certificate))
            mstore(add(pointer, 0x20), mload(add(certificate, 0x20)))
            mstore(add(pointer, 0x40), mload(add(certificate, 0x40)))
            mstore(add(pointer, 0x60), mload(add(certificate, 0x60)))
            structHash := keccak256(pointer, 0x80)
            mstore(0x40, add(pointer, 0x80))
        }

        bytes32 digest = MessageHashUtils.toEthSignedMessageHash(structHash);
        address signer = ECDSA.recover(digest, certificate.signature);

        if (signer != owner()) {
            revert InvalidCertificateSigner(signer, owner());
        }

        if (block.timestamp < certificate.issuedAt) {
            revert CertificateNotYetValid(block.timestamp, certificate.issuedAt);
        }
        if (block.timestamp >= certificate.expiresAt) {
            revert CertificateExpired(block.timestamp, certificate.expiresAt);
        }

        if (certificate.chainId != block.chainid) {
            revert CertificateWrongChain(certificate.chainId, block.chainid);
        }

        return certificate.validator;
    }

    /// @notice Authorize contract upgrades (UUPS)
    /// @dev Only owner can authorize upgrades
    /// @param newImplementation New implementation address
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
