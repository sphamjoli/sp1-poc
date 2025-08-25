// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IStakeManagerTypes} from "../stake/IStakeManagerTypes.sol";

/// @title IValidatorTypes
/// @author Brianspha
/// @notice Type definitions and events for validator system
/// @dev Defines core data structures and events for bridge validation system
interface IValidatorTypes {
    // ========== ERRORS ==========

    /// @notice Required address parameter is the zero address
    error ZeroAddress();

    /// @notice Validator is not registered in the system
    error ValidatorNotRegistered();

    /// @notice Thrown when msg.sender is not the VM contract
    error NotValidatorManager();

    /// @notice Thrown when public values from SP1 include a chain id not targeting current chain
    error InvalidChainId();

    /// @notice Generic revert for unauthorized or invalid operations
    error NotAllowed();

    /// @notice No participants available for the requested operation
    error NoParticipants();

    /// @notice Validator has already attested to this root
    error AlreadyAttested();

    /// @notice Thrown when msg.sender is not the StakeManager contract
    error NotStakeManager();

    // ========== ENUMS ==========

    /// @notice Validator status enumeration
    /// @param Inactive Not staked or slashed below minimum
    /// @param Active Staked and eligible to submit attestations
    /// @param Unstaking Initiated unstaking, no longer active
    /// @param Slashed Penalized for malicious behavior
    enum ValidatorStatus {
        Inactive,
        Active,
        Unstaking,
        Slashed
    }

    // ========== STRUCTS ==========

    /// @notice Parameters for reward distribution
    /// @param totalReward Total reward amount to distribute
    /// @param recipients Array of validator addresses to reward
    /// @param amounts Array of reward amounts for each validator
    struct RewardsParams {
        uint256 totalReward;
        address[] recipients;
        uint256[] amounts;
    }

    /// @notice Parameters for root verification queries
    /// @param chainId Source chain identifier
    /// @param bridgeRoot Bridge contract root to verify
    struct RootParams {
        uint256 chainId;
        bytes32 bridgeRoot;
    }


    /// @notice Complete validator information
    /// @param blsPublicKey BLS public key for signature aggregation
    /// @param status Current validator status
    /// @param attestationCount Total number of attestations submitted
    /// @param invalidAttestations Used to track all invalid attestations made
    /// @param lastRewardEpoch The recorded epoch the validator got rewards
    /// @param wallet Wallet address used for rewards
    struct ValidatorInfo {
        uint256[4] blsPublicKey;
        ValidatorStatus status;
        uint256 attestationCount;
        uint256 invalidAttestations;
        address wallet;
    }

    /// @notice Bridge state attestation submitted by validator
    /// @param chainId Source chain identifier (e.g., 1 for Ethereum)
    /// @param blockNumber Block number where bridge state was captured
    /// @param bridgeRoot Root hash of bridge contract's state tree
    /// @param stateRoot State root of the blockchain at blockNumber
    /// @param timestamp Block timestamp when attestation was created
    /// @param validator Address of attesting validator
    /// @param signature BLS signature over attestation data
    struct BridgeAttestation {
        uint256 chainId;
        uint256 blockNumber;
        bytes32 bridgeRoot;
        bytes32 stateRoot;
        uint256 timestamp;
        address validator;
        uint256[2] signature;
    }

    /// @notice Aggregated bridge state attestation from multiple validators
    /// @param chainId Source chain identifier (e.g., 1 for Ethereum)
    /// @param blockNumber Block number where bridge state was captured
    /// @param bridgeRoot Root hash of bridge contract's state tree
    /// @param stateRoot State root of the blockchain at blockNumber
    /// @param timestamp Block timestamp when attestation was created
    /// @param participants Array of validator addresses who signed this attestation
    /// @param aggregatedSignature BLS aggregated signature over attestation data
    /// @param aggregatedPublicKey BLS aggregated public keys from all participants
    struct AggregatedBridgeAttestation {
        uint256 chainId;
        uint256 blockNumber;
        bytes32 bridgeRoot;
        bytes32 stateRoot;
        uint256 timestamp;
        address[] participants;
        uint256[2] aggregatedSignature;
        uint256[4] aggregatedPublicKey;
    }

    /// @notice SP1 verification public values for bridge roots
    /// @param chainId Source chain identifier
    /// @param attestations Array of bridge attestations to verify
    /// @param equivocators Array of slash parameters for misbehaving validators
    /// @param validBridgeRoot The verified correct bridge root
    struct VerificationPublicValues {
        uint256 chainId;
        BridgeAttestation[] attestations;
        IStakeManagerTypes.SlashParams[] equivocators;
        bytes32 validBridgeRoot;
    }

    /// @notice Parameters for finalizing bridge attestations
    /// @param publicValues Encoded public values from SP1 proof
    /// @param proofBytes Raw proof bytes from SP1 verification system
    struct VerificationParams {
        bytes publicValues;
        bytes proofBytes;
    }

    /// @notice Pre-confirmation tracking for attestations
    /// @param count Number of validators who pre-confirmed
    /// @param confirmed Whether the attestation has reached confirmation threshold
    struct PreConfirmation {
        uint256 count;
        bool confirmed;
    }

    /// @notice Internal storage structure for validator manager
    /// @param validators Mapping of validator addresses to their information
    /// @param attestations Mapping of validator to root hash to attestation status
    /// @param preConfirmations Mapping of root hashes to pre-confirmation data
    /// @param activeValidators Set of currently active validator addresses
    /// @param __gap Storage gap for future upgrades
    struct VMStorage {
        mapping(address validator => ValidatorInfo info) validators;
        mapping(address => mapping(bytes32 => bool)) attestations;
        mapping(bytes32 => PreConfirmation) preConfirmations;
        EnumerableSet.AddressSet activeValidators;
        uint256[46] __gap;
    }

    // ========== EVENTS ==========

    /// @notice Emitted when a validator stakes tokens
    /// @param validator Address of new validator
    /// @param stakeAmount Amount staked
    /// @param blsPublicKey BLS public key registered
    event ValidatorStaked(address indexed validator, uint256 stakeAmount, bytes blsPublicKey);

    /// @notice Emitted when validator submits bridge attestation
    /// @param validator Address of validator
    /// @param chainId Chain that was attested
    /// @param bridgeRoot Bridge root that was attested
    /// @param blockNumber Block number of attestation
    event AttestationSubmitted(
        address indexed validator, uint256 indexed chainId, bytes32 bridgeRoot, uint256 blockNumber
    );

    /// @notice Emitted when bridge root is verified by SP1 system
    /// @param chainId Source chain identifier
    /// @param bridgeRoot Bridge root that was verified
    /// @param blockNumber Block number verified
    event RootVerified(
        uint256 indexed chainId, bytes32 indexed bridgeRoot, uint256 blockNumber
    );

    /// @notice Emitted when a new validator is added to the active set
    /// @param wallet Validator's wallet address used for rewards
    /// @param blsKey BLS public key for validator
    event AddedValidator(address indexed wallet, uint256[4] indexed blsKey);

    /// @notice Emitted when a validator is removed from the active set
    /// @param wallet Validator's wallet address used for rewards
    /// @param blsKey BLS public key for validator
    event RemovedValidator(address indexed wallet, uint256[4] indexed blsKey);

    /// @notice Emitted when the SP1 program verification key is updated
    /// @param currentKey Previous program verification key
    /// @param newKey New program verification key
    event ProgramKeyUpdated(bytes32 indexed currentKey, bytes32 indexed newKey);

    /// @notice emitted when bridge roots have been verified
    /// @param currentEpoch The current epoch number
    /// @param newEpoch The new epoch number
    event NewEpoch(uint256 indexed currentEpoch, uint256 indexed newEpoch);

    /// @notice Emitted when system parameters are updated
    /// @param minimumStake New minimum stake requirement
    /// @param slashingRate New slashing rate percentage
    /// @param unstakingDelay New unstaking delay in seconds
    event ParametersUpdated(uint256 minimumStake, uint256 slashingRate, uint256 unstakingDelay);
}
