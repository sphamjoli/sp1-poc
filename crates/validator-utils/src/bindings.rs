use alloy::sol;

pub const STATUS_INACTIVE: u8 = 0;
pub const STATUS_ACTIVE: u8 = 1;
pub const STATUS_UNSTAKING: u8 = 2;
pub const STATUS_SLASHED: u8 = 3;

sol! {
    #[sol(rpc)]
    interface IERC20 {
        function approve(address spender, uint256 amount) external returns (bool);
        function balanceOf(address account) external view returns (uint256);
        function decimals() external view returns (uint8);
        function symbol() external view returns (string memory);
        function transfer(address to, uint256 amount) external returns (bool);
    }

    #[sol(rpc)]
    interface IBridge {
        struct DepositParams {
            uint256 amount;
            address token;
            address to;
            uint256 destinationChain;
        }

        struct SparseMerkleProof {
            bytes32 root;
            bytes32[] siblings;
            bool existence;
            bytes32 key;
            bytes32 value;
            bool auxExistence;
            bytes32 auxKey;
            bytes32 auxValue;
        }

        struct ClaimParams {
            uint256 depositIndex;
            uint32 sourceChain;
            address token;
            address to;
            uint256 amount;
            bytes32 sourceRoot;
            uint256 blockNumber;
            bytes32 stateRoot;
            SparseMerkleProof proof;
        }

        function owner() external view returns (address);
        function VALIDATOR_MANAGER() external view returns (address);
        function deposit(DepositParams calldata depositParams) external payable;
        function claim(ClaimParams calldata claimParams) external;
        function getBalance(address token) external view returns (uint256);
        function getDepositProof(uint256 depositIndex) external view returns (SparseMerkleProof memory);
        function updateValidatorManager(address validatorManager) external;
    }

    #[derive(Debug, Default)]
    struct StakeManagerConfig {
        uint256 minStakeAmount;
        uint256 minWithdrawAmount;
        uint256 minUnstakeDelay;
        uint256 correctProofReward;
        uint256 incorrectProofPenalty;
        uint32 maxMissedProofs;
        uint256 slashingRate;
        address stakingToken;
    }

    #[derive(Debug, Default)]
    struct ValidatorBalance {
        uint256 balance;
        uint256 stakeAmount;
        bytes32 stakeVersion;
        uint256 stakeTimestamp;
        uint256 stakeExitTimestamp;
        uint256 unstakeAmount;
        uint256 tokenId;
        uint256 lastRewardEpoch;
        uint256[4] pubkey;
    }

    #[derive(Debug, Default)]
    struct StakeParams {
        uint256 stakeAmount;
        bytes32 stakeVersion;
    }

    #[derive(Debug, Default)]
    struct UnstakingParams {
        uint256 stakeAmount;
    }

    #[derive(Debug, Default)]
    struct BlsOwnerShip {
        uint256[2] signature;
        uint256[4] pubkey;
    }

    #[derive(Debug, Default)]
    struct ValidatorInfo {
        uint256[4] blsPublicKey;
        uint8 status;
        uint256 attestationCount;
        uint256 invalidAttestations;
        address wallet;
    }

    #[derive(Debug, Default)]
    struct Certificate {
        address validator;
        uint256 issuedAt;
        uint256 expiresAt;
        uint256 chainId;
        bytes signature;
    }

    #[derive(Debug, Default)]
    struct BridgeAttestation {
        uint256 blockNumber;
        bytes32 bridgeRoot;
        bytes32 stateRoot;
        uint256 sourceChainId;
        uint256 timestamp;
        address validator;
        bytes certificate;
        uint256[2] signature;
    }

    #[derive(Debug, Default)]
    struct RootParams {
        uint256 blockNumber;
        bytes32 bridgeRoot;
        bytes32 stateRoot;
        uint256 sourceChainId;
    }

    #[derive(Debug, Default)]
    struct SlashParams {
        address validator;
        uint256 slashAmount;
    }

    #[derive(Debug, Default)]
    struct VerificationPublicValues {
        uint256 attestedChainId;
        BridgeAttestation[] attestations;
        SlashParams[] equivocators;
        bytes32 validBridgeRoot;
    }

    #[derive(Debug, Default)]
    struct VerificationParams {
        bytes publicValues;
        bytes proofBytes;
    }

    #[sol(rpc)]
    interface IStakeManager {
        function owner() external view returns (address);
        function VALIDATOR_MANAGER() external view returns (address);
        function ACTIVE_STAKING_CONFIG() external view returns (StakeManagerConfig memory);
        function getStakeVersion(StakeManagerConfig memory config) external pure returns (bytes32);
        function getLatestRewards(address validator) external view returns (uint256);
        function validatorBalance(address validator) external view returns (ValidatorBalance memory);
        function beginUnstaking(UnstakingParams memory params) external;
        function completeUnstaking() external;
        function slashValidator(SlashParams calldata params) external;
        function claimRewards() external;
        function transferToken(address token, uint256 amount) external;
        function updateValidatorManager(address manager) external;
        function stake(StakeParams memory params, BlsOwnerShip memory proof) external;
    }

    #[sol(rpc)]
    interface IValidatorManager {
        function owner() external view returns (address);
        function STAKING_MANAGER() external view returns (address);
        function SP1_VERIFIER() external view returns (address);
        function PROGRAM_KEY() external view returns (bytes32);
        function EPOCH() external view returns (uint256);
        function epochDuration() external view returns (uint256);
        function getEpochsPerYear() external view returns (uint256);
        function getValidator(address validator) external view returns (ValidatorInfo memory);
        function getActiveValidators() external view returns (address[] memory);
        function distributeRewards() external;
        function updateStakingManager(address stakingManager) external;
        function addValidator(ValidatorInfo memory info) external;
        function updateValidatorStatus(address validator, uint8 status) external;
        function isRootVerified(RootParams calldata params) external view returns (bool);
        function submitAttestation(BridgeAttestation calldata attestation) external;
        function finaliseAttestations(VerificationParams calldata params) external;
    }
}
