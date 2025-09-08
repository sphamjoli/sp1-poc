// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ISP1Verifier} from "@sp1-contracts/ISP1Verifier.sol";
import {IValidatorManager, IValidatorTypes} from "./IValidatorManager.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {PausableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ValidatorManagerStorage} from "./ValidatorManagerStorage.sol";
import {BLS} from "solbls/BLS.sol";
import {IStakeManager, IStakeManagerTypes} from "../stake/IStakeManager.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

/// @title Validator Manager
/// @notice Manages validator lifecycle and bridge state attestations
/// @dev Handles validator registration, attestation submission, and reward distribution
contract ValidatorManager is
    IValidatorManager,
    Initializable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    PausableUpgradeable,
    ValidatorManagerStorage
{
    using BLS for *;
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @notice Restricts access to stake manager only
    modifier onlyStakeManager() {
        require(msg.sender == STAKING_MANAGER, NotStakeManager(msg.sender));
        _;
    }

    /// @notice Chain ID where this contract is deployed
    uint256 public immutable CHAIN_ID;

    /// @notice Contract name identifier
    string public NAME;

    /// @notice Contract version identifier
    string public VERSION;

    /// @notice Address of the stake manager contract
    address public STAKING_MANAGER;

    /// @notice SP1 verifier contract address
    address public SP1_VERIFIER;

    /// @notice Domain separator for BLS proof of possession in attestations
    bytes public POP_ATTEST_DOMAIN;

    /// @notice SP1 program verification key for bridge proofs
    bytes32 public PROGRAM_KEY;

    /// @notice Current epoch number
    uint256 public EPOCH;

    /// @notice Duration of each epoch in seconds
    uint256 public EPOCH_DURATION;

    uint256 public EPOCH_ZERO_TS;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        CHAIN_ID = block.chainid;
        _disableInitializers();
    }

    /// @inheritdoc IValidatorManager
    function initialize(address verifier, bytes32 programKey) external override initializer {
        SP1_VERIFIER = verifier;
        NAME = "ValidatorManager";
        VERSION = "1";
        POP_ATTEST_DOMAIN = "ValidatorManager:BN254:PoP:v1:";
        EPOCH_ZERO_TS = block.timestamp;
        EPOCH = 1;
        EPOCH_DURATION = 10 minutes;

        __Ownable_init(msg.sender);
        __Pausable_init();
        __UUPSUpgradeable_init();
        updateProgramKey(programKey);
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
        VMStorage storage $ = _loadStorage();

        require(msg.sender == attestation.validator, NotAllowed());
        require($.validators[msg.sender].status == ValidatorStatus.Active, ValidatorNotRegistered());

        bytes32 attestationKey = keccak256(
            abi.encode(attestation.chainId, attestation.bridgeRoot, attestation.blockNumber)
        );
        require(!$.attestations[msg.sender][attestationKey], AlreadyAttested());

        uint256[4] memory blsPublicKey = $.validators[msg.sender].blsPublicKey;
        uint256[2] memory msgToVerify = proofOfPossessionMessage(blsPublicKey, attestation);

        (bool pairingSuccess, bool callSuccess) =
            BLS.verifySingle(attestation.signature, blsPublicKey, msgToVerify);
        require(pairingSuccess && callSuccess, IStakeManagerTypes.InvalidBLSSignature());

        $.attestations[msg.sender][attestationKey] = true;
        _updatePreConfirmation($, attestationKey, 1);

        emit AttestationSubmitted(
            msg.sender, CHAIN_ID, attestation.bridgeRoot, attestation.blockNumber
        );
    }

    /// @inheritdoc IValidatorManager
    function submitAggregatedAttestation(AggregatedBridgeAttestation calldata attestation)
        external
        override
        whenNotPaused
    {
        VMStorage storage $ = _loadStorage();

        require(attestation.participants.length > 0, NoParticipants());

        bytes32 attestationKey = keccak256(
            abi.encode(attestation.chainId, attestation.bridgeRoot, attestation.blockNumber)
        );

        for (uint256 i = 0; i < attestation.participants.length; i++) {
            address participant = attestation.participants[i];
            require(!$.attestations[participant][attestationKey], AlreadyAttested());
            require(
                $.validators[participant].status == ValidatorStatus.Active, ValidatorNotRegistered()
            );
        }

        uint256[2] memory msgToVerify = proofOfPossessionMessage(attestation);
        (bool pairingSuccess, bool callSuccess) = BLS.verifySingle(
            attestation.aggregatedSignature, attestation.aggregatedPublicKey, msgToVerify
        );
        require(pairingSuccess && callSuccess, IStakeManagerTypes.InvalidBLSSignature());

        for (uint256 i = 0; i < attestation.participants.length; i++) {
            $.attestations[attestation.participants[i]][attestationKey] = true;
        }

        _updatePreConfirmation($, attestationKey, attestation.participants.length);

        emit AttestationSubmitted(
            msg.sender, CHAIN_ID, attestation.bridgeRoot, attestation.blockNumber
        );
    }

    /// @inheritdoc IValidatorManager
    function isRootVerified(RootParams calldata params)
        external
        view
        override
        returns (bool verified)
    {
        VMStorage storage $ = _loadStorage();
        bytes32 attestationKey = keccak256(abi.encode(params.chainId, params.bridgeRoot));
        return $.preConfirmations[attestationKey].confirmed;
    }

    /// @inheritdoc IValidatorManager
    function updateValidatorStatus(
        address validator,
        ValidatorStatus status
    )
        external
        override
        onlyStakeManager
    {
        VMStorage storage $ = _loadStorage();
        ValidatorInfo storage info = $.validators[validator];
        info.status = status;
    }

    /// @inheritdoc IValidatorManager
    function getValidator(address validator)
        external
        view
        override
        returns (ValidatorInfo memory info)
    {
        VMStorage storage $ = _loadStorage();
        return $.validators[validator];
    }

    /// @inheritdoc IValidatorManager
    function getActiveValidators() external view override returns (address[] memory validators) {
        VMStorage storage $ = _loadStorage();
        return $.activeValidators.values();
    }

    /// @inheritdoc IValidatorManager
    function finaliseAttestations(VerificationParams calldata params) external override onlyOwner {
        VMStorage storage $ = _loadStorage();

        ISP1Verifier(SP1_VERIFIER).verifyProof(PROGRAM_KEY, params.publicValues, params.proofBytes);

        VerificationPublicValues memory publicValues =
            abi.decode(params.publicValues, (VerificationPublicValues));
        require(publicValues.chainId == CHAIN_ID, InvalidChainId());

        IStakeManager manager = IStakeManager(STAKING_MANAGER);

        for (uint256 i = 0; i < publicValues.equivocators.length; i++) {
            IStakeManagerTypes.SlashParams memory slashParams = publicValues.equivocators[i];
            ValidatorInfo storage info = $.validators[slashParams.validator];

            manager.slashValidator(slashParams);
            info.invalidAttestations++;
        }

        for (uint256 i = 0; i < publicValues.attestations.length; i++) {
            BridgeAttestation memory attestation = publicValues.attestations[i];
            ValidatorInfo storage info = $.validators[attestation.validator];

            info.attestationCount++;
            emit RootVerified(attestation.chainId, attestation.bridgeRoot, attestation.blockNumber);
        }

        _updateEpoch();
    }

    /// @inheritdoc IValidatorManager
    function proofOfPossessionMessage(
        uint256[4] memory blsPubkey,
        BridgeAttestation calldata attestation
    )
        public
        view
        override
        returns (uint256[2] memory)
    {
        bytes memory messageBytes = abi.encodePacked(
            blsPubkey[0],
            blsPubkey[1],
            blsPubkey[2],
            blsPubkey[3],
            msg.sender,
            attestation.chainId,
            attestation.blockNumber,
            attestation.bridgeRoot,
            attestation.stateRoot,
            attestation.timestamp
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
            attestation.aggregatedPublicKey[0],
            attestation.aggregatedPublicKey[1],
            attestation.aggregatedPublicKey[2],
            attestation.aggregatedPublicKey[3],
            msg.sender,
            attestation.chainId,
            attestation.blockNumber,
            attestation.bridgeRoot,
            attestation.stateRoot,
            attestation.timestamp
        );
        return BLS.hashToPoint(POP_ATTEST_DOMAIN, messageBytes);
    }

    /// @inheritdoc IValidatorManager
    function addValidator(ValidatorInfo memory info) external override onlyStakeManager {
        VMStorage storage $ = _loadStorage();
        require($.validators[info.wallet].status == ValidatorStatus.Inactive, NotAllowed());
        $.validators[info.wallet] = info;
        $.activeValidators.add(info.wallet);

        emit AddedValidator(info.wallet, info.blsPublicKey);
    }

    /// @inheritdoc IValidatorManager
    function removeValidator(address validator) external override onlyStakeManager {
        VMStorage storage $ = _loadStorage();
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
        return 31557600 / EPOCH_DURATION;
    }

    /// @inheritdoc IValidatorManager
    function distributeRewards() external override onlyOwner whenNotPaused {
        VMStorage storage $ = _loadStorage();
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

    /// @notice Update pre-confirmation status for an attestation
    /// @param $ Storage reference
    /// @param attestationKey Unique key for the attestation
    /// @param additionalCount Number of new confirmations to add
    function _updatePreConfirmation(
        VMStorage storage $,
        bytes32 attestationKey,
        uint256 additionalCount
    )
        internal
    {
        PreConfirmation storage pc = $.preConfirmations[attestationKey];
        pc.count += additionalCount;

        // Here we need a 67% threshold with rounding up similar to calling math.ceil()
        uint256 threshold = ($.activeValidators.length() * 67 + 99) / 100;
        if (!pc.confirmed && pc.count >= threshold) {
            pc.confirmed = true;
        }
    }

    /// @notice Increment epoch and emit event
    function _updateEpoch() internal {
        emit NewEpoch(EPOCH, ++EPOCH);
    }

    /// @inheritdoc IValidatorManager
    function epochsElapsedSince(uint256 timestamp) public view override returns (uint256 epochs) {
        if (block.timestamp <= timestamp || EPOCH_DURATION == 0) return 0;
        epochs = Math.saturatingSub(block.timestamp, timestamp) / EPOCH_DURATION;
    }

    /// @notice Authorize contract upgrades
    /// @dev Only owner can authorize upgrades per UUPS pattern
    /// @param newImplementation Address of new implementation contract
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
