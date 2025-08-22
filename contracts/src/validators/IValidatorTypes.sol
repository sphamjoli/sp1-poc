// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title IValidatorTypes
/// @author Brianspha
/// @notice Type definitions and events for validator system
interface IValidatorTypes {
    /// @notice Required address parameter is the zero address
    error ZeroAddress();
    /// @notice Thrown when msg.sender is not the VM contract
    error NotValidatorManager();

    /// @notice Validator status enumeration
    /// @param Inactive   Not staked or slashed below minimum
    /// @param Active   Staked and eligible to submit attestations
    /// @param Unstaking   Initiated unstaking, no longer active
    /// @param Slashed   Penalized for malicious behavior
    enum ValidatorStatus {
        Inactive,
        Active,
        Unstaking,
        Slashed
    }

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
        uint32 chainId;
        bytes32 bridgeRoot;
    }

    /// @notice Complete validator information
    /// @param blsPublicKey BLS public key for signature aggregation
    /// @param status Current validator status
    /// @param attestationCount Total number of attestations submitted
    struct ValidatorInfo {
        uint256[4] blsPublicKey;
        ValidatorStatus status;
        uint256 attestationCount;
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
        uint32 chainId;
        uint256 blockNumber;
        bytes32 bridgeRoot;
        bytes32 stateRoot;
        uint256 timestamp;
        address validator;
        bytes signature;
    }

    /// @notice SP1 verification result for bridge roots
    /// @param chainId Source chain identifier
    /// @param blockNumber Block number verified
    /// @param bridgeRoot Bridge root that was verified
    /// @param verifiedAt Timestamp when SP1 verification completed
    /// @param proofHash Hash of the SP1 proof used for verification
    struct VerificationResult {
        uint32 chainId;
        uint256 blockNumber;
        bytes32 bridgeRoot;
        uint256 verifiedAt;
        bytes32 proofHash;
    }

    struct VMStorage {
        mapping(address validator => ValidatorInfo info) validators;
        uint256[50] __gap;
    }
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
        address indexed validator, uint32 indexed chainId, bytes32 bridgeRoot, uint256 blockNumber
    );

    /// @notice Emitted when bridge root is verified by SP1 system
    /// @param chainId Source chain identifier
    /// @param bridgeRoot Bridge root that was verified
    /// @param blockNumber Block number verified
    /// @param proofHash Hash of SP1 proof
    event RootVerified(uint32 indexed chainId, bytes32 indexed bridgeRoot, uint256 blockNumber, bytes32 proofHash);

    /// @notice Emitted when validator is slashed
    /// @param validator Address of slashed validator
    /// @param slashAmount Amount slashed
    /// @param evidence Evidence hash
    /// @param executor Address that executed slash
    event ValidatorSlashed(address indexed validator, uint256 slashAmount, bytes32 evidence, address executor);

    /// @notice Emitted when validator begins unstaking
    /// @param validator Address of validator
    /// @param stakeAmount Amount being unstaked
    /// @param completionTime When unstaking can be completed
    event UnstakingInitiated(address indexed validator, uint256 stakeAmount, uint256 completionTime);

    /// @notice Emitted when validator completes unstaking
    /// @param validator Address of validator
    /// @param stakeAmount Amount withdrawn
    event UnstakingCompleted(address indexed validator, uint256 stakeAmount);

    /// @notice Emitted when rewards are distributed
    /// @param totalReward Total amount distributed
    /// @param recipientCount Number of validators rewarded
    event RewardsDistributed(uint256 totalReward, uint256 recipientCount);

    /// @notice Emitted when system parameters are updated
    /// @param minimumStake New minimum stake requirement
    /// @param slashingRate New slashing rate
    /// @param unstakingDelay New unstaking delay
    event ParametersUpdated(uint256 minimumStake, uint256 slashingRate, uint256 unstakingDelay);
}
