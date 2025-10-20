// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {StakeManagerBaseTest, IStakeManagerTypes} from "./StakeManagerBase.t.sol";
import {IValidatorTypes} from "../../src/validator/IValidatorTypes.sol";
import {ArrayContainsLib} from "../../src/libs/ArrayContainsLib.sol";

abstract contract ValidatorManagerBaseTest is StakeManagerBaseTest {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;
    using ArrayContainsLib for address[];

    function setUp() public virtual override {
        super.setUp();
    }

    /// @notice Issues a certificate for a validator on a specific chain
    /// @param validator Validator address receiving the certificate
    /// @param forkId Chain fork identifier where certificate is valid
    /// @param expiresAt Expiration timestamp (0 for default 10 minutes)
    function _issueCertificate(
        address validator,
        uint256 forkId,
        uint256 expiresAt
    )
        internal
        returns (bytes memory certificateBytes, bytes32 digest)
    {
        (, uint256 ownerPrivateKey) = _prankOwnerOnChain(forkId);
        uint256 actualExpiresAt = expiresAt == 0 ? block.timestamp + 10 minutes : expiresAt;

        digest = keccak256(abi.encode(validator, block.timestamp, actualExpiresAt, block.chainid))
            .toEthSignedMessageHash();

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        IValidatorTypes.Certificate memory certificate = IValidatorTypes.Certificate({
            chainId: block.chainid,
            issuedAt: block.timestamp,
            expiresAt: actualExpiresAt,
            validator: validator,
            signature: signature
        });

        certificateBytes = abi.encode(certificate);
        vm.stopPrank();
    }

    /// @notice Generates a deterministic bridge root for testing
    /// @param seed Unique identifier for the bridge root
    /// @return Bridge root hash
    function _generateBridgeMockRoot(uint256 seed) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("bridge_root", seed));
    }

    /// @notice Creates a BridgeAttestation structure with embedded certificate
    /// @param validator Address of the attesting validator
    /// @param bridgeRoot Bridge state root being attested
    /// @param blockNumber Block number of the attestation
    /// @param certificate Certificate bytes from node manager
    /// @return Attestation structure with certificate and empty signature
    function _createAttestation(
        address validator,
        bytes32 bridgeRoot,
        uint256 blockNumber,
        bytes memory certificate,
        uint256 chainId
    )
        internal
        view
        returns (IValidatorTypes.BridgeAttestation memory)
    {
        return IValidatorTypes.BridgeAttestation({
            blockNumber: blockNumber,
            bridgeRoot: bridgeRoot,
            stateRoot: keccak256(abi.encodePacked("state_root", blockNumber)),
            timestamp: block.timestamp,
            validator: validator,
            certificate: certificate,
            chainId: chainId,
            signature: _signAttestation(validator, chainId)
        });
    }
    /// @notice Signs an attestation using validator's BLS proof of possession
    /// @dev We dont need this function but for reuse we create it
    /// @param validator Validator address
    /// @param chainId The currently active fork id
    /// @return signature BLS signature as uint256

    function _signAttestation(
        address validator,
        uint256 chainId
    )
        internal
        view
        returns (uint256[2] memory signature)
    {
        BlsTestData memory data = validatorBlsData[validator];
        ProofData memory proofData = validatorProofData[validator][chainId];

        require(bytes(data.walletAddress).length > 0, "No BLS data for validator");

        signature = [
            vm.parseUint(proofData.proofOfPossessionValidator[0]),
            vm.parseUint(proofData.proofOfPossessionValidator[1])
        ];
    }

    /// @notice Adds a validator to the ValidatorManager contract
    /// @param validator Validator address to add
    /// @param forkId Chain fork identifier
    function _addValidatorToManager(address validator, uint256 forkId) internal {
        BlsTestData memory data = validatorBlsData[validator];
        require(bytes(data.walletAddress).length > 0, "No BLS data for validator");

        vm.selectFork(forkId);

        IValidatorTypes.ValidatorInfo memory info = IValidatorTypes.ValidatorInfo({
            blsPublicKey: [
                vm.parseUint(data.publicKey[0]),
                vm.parseUint(data.publicKey[1]),
                vm.parseUint(data.publicKey[2]),
                vm.parseUint(data.publicKey[3])
            ],
            wallet: validator,
            status: IValidatorTypes.ValidatorStatus.Active,
            attestationCount: 0,
            invalidAttestations: 0
        });

        _prankOwnerOnChain(forkId);

        if (forkId == FORKA_ID) {
            validatorManagerA.addValidator(info);
        } else if (forkId == FORKB_ID) {
            validatorManagerB.addValidator(info);
        }

        vm.stopPrank();
    }

    /// @notice Submit attestations from multiple validators about a source chain to a destination chain
    /// @param validators Array of validator addresses
    /// @param forkId Fork ID of the source chain being attested to
    /// @param bridgeRoot The bridge root from the source chain
    /// @param blockNumber The block number on the source chain
    function _submitAttestationsToChain(
        address[5] memory validators,
        uint256 forkId,
        bytes32 bridgeRoot,
        uint256 blockNumber
    )
        internal
    {
        vm.selectFork(forkId);
        for (uint256 i = 0; i < validators.length; i++) {
            (bytes memory certificate,) =
                _issueCertificate(validators[i], forkId, block.timestamp + 10 minutes);

            IValidatorTypes.BridgeAttestation memory attestation = _createAttestation(
                validators[i], bridgeRoot, blockNumber, certificate, block.chainid
            );

            attestation.signature = _signAttestation(validators[i], block.chainid);

            vm.prank(validators[i]);

            if (forkId == FORKB_ID) {
                validatorManagerB.submitAttestation(attestation);
            } else if (forkId == FORKA_ID) {
                validatorManagerA.submitAttestation(attestation);
            } else {
                revert("Invalid fork");
            }
        }
    }

    /// @notice Finalizes attestations while mocking proof verification, excluding equivocators' attestations.
    /// @dev Filters `attestations` by removing any whose `validator` address appears in `equivocators`.
    /// Builds a compact memory array without using `push` (unsupported on memory arrays).
    /// Mocks SP1 verifier to return true and calls `finaliseAttestations`.
    /// @param attestations All candidate attestations.
    /// @param equivocators Validators to be slashed; their attestations are excluded.
    /// @param validBridgeRoot Bridge root to embed in the public values.
    /// @param forkId Fork on which to impersonate the owner before finalisation.
    function _finalizeWithMocks(
        IValidatorTypes.BridgeAttestation[] memory attestations,
        IStakeManagerTypes.SlashParams[] memory equivocators,
        bytes32 validBridgeRoot,
        uint256 forkId
    )
        internal
    {
        address[] memory baddies = new address[](equivocators.length);
        for (uint256 i = 0; i < equivocators.length; ++i) {
            baddies[i] = equivocators[i].validator;
        }

        IValidatorTypes.BridgeAttestation[] memory scratch =
            new IValidatorTypes.BridgeAttestation[](attestations.length);

        uint256 kept = 0;
        for (uint256 i = 0; i < attestations.length; ++i) {
            if (!baddies.contains(attestations[i].validator)) {
                scratch[kept] = attestations[i];
                unchecked {
                    ++kept;
                }
            }
        }

        IValidatorTypes.BridgeAttestation[] memory filtered =
            new IValidatorTypes.BridgeAttestation[](kept);
        for (uint256 i = 0; i < kept; ++i) {
            filtered[i] = scratch[i];
        }

        _prankOwnerOnChain(forkId);

        IValidatorTypes.VerificationPublicValues memory publicValues = IValidatorTypes
            .VerificationPublicValues({
            chainId: block.chainid,
            attestations: filtered,
            equivocators: equivocators,
            validBridgeRoot: validBridgeRoot
        });

        IValidatorTypes.VerificationParams memory params = IValidatorTypes.VerificationParams({
            publicValues: abi.encode(publicValues),
            proofBytes: ""
        });

        vm.mockCall(
            address(validatorManagerA.SP1_VERIFIER()),
            abi.encodeWithSelector(bytes4(keccak256("verifyProof(bytes32,bytes,bytes)"))),
            abi.encode(true)
        );

        validatorManagerA.finaliseAttestations(params);
    }

    /// @notice Build slash parameters for a contiguous slice of `validators`.
    /// @dev Copies validators in the range `[startIndex, validators.length)`
    ///      into a new array of `SlashParams`. If `startIndex == validators.length`,
    ///      returns an empty array.
    /// @param validators The full list of validator addresses (in memory).
    /// @param startIndex The starting index (inclusive) of the slice to convert.
    /// @param slashAmount The slash amount to assign to every selected validator.
    /// @return equivocators An array of `SlashParams` for the selected validators.
    function _createEquivicators(
        address[] memory validators,
        uint256 startIndex,
        uint256 slashAmount
    )
        internal
        pure
        returns (IStakeManagerTypes.SlashParams[] memory equivocators)
    {
        require(startIndex <= validators.length, "startIndex out of bounds");

        uint256 length = validators.length - startIndex;
        equivocators = new IStakeManagerTypes.SlashParams[](length);

        for (uint256 index = 0; index < length; ++index) {
            equivocators[index] = IStakeManagerTypes.SlashParams({
                validator: validators[startIndex + index],
                slashAmount: slashAmount
            });
        }
    }
}
