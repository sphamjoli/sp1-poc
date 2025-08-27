// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {
    ERC721Enumerable,
    ERC721
} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {BLS} from "solbls/BLS.sol";
import {StakeManagerStorage} from "./StakeManagerStorage.sol";
import {ArrayContainsLib} from "../libs/ArrayContainsLib.sol";
import {IStakeManager} from "./IStakeManager.sol";
import {IValidatorManager, IValidatorTypes} from "../validators/IValidatorManager.sol";

/// @title Stake Manager
/// @author Brianspha
/// @notice Manages validator stakes, rewards, and slashing for bridge validation system
contract StakeManager is
    IStakeManager,
    Initializable,
    Ownable,
    UUPSUpgradeable,
    ERC721Enumerable,
    StakeManagerStorage,
    Pausable
{
    using BLS for *;
    using ArrayContainsLib for address[];

    /// @notice Restricts access to validator manager only
    modifier onlyValidatorManager() {
        require(msg.sender == VALIDATOR_MANAGER, NotValidatorManager());
        _;
    }

    /// @notice Chain ID where this contract is deployed
    uint256 public immutable CHAIN_ID;

    /// @notice Counter for NFT token IDs
    uint256 public COUNTER;

    /// @notice Active staking configuration
    StakeManagerConfig public ACTIVE_STAKING_CONFIG;

    /// @notice Address of the validator manager contract
    address public VALIDATOR_MANAGER;

    /// @notice Contract name identifier
    string public NAME;

    /// @notice Contract version identifier
    string public VERSION;

    /// @notice Annual reward rate in basis points (500 = 5%)
    uint256 public immutable REWARD_RATE;

    /// @notice Scaling factor for precise calculations
    uint64 public immutable SCALING_FACTOR;

    /// @notice Domain separator for BLS proof of possession
    bytes public POP_STAKE_DOMAIN;

    /// @notice Number of epochs eligible for early validator bonus
    uint256 public EARLY_BONUS_EPOCHS;

    /// @notice Minimum performance threshold for reward eligibility (80%)
    uint256 public MIN_PERFORMANCE_THRESHOLD;

    /// @notice Early validator bonus amount in wei
    uint256 public EARLY_BONUS_AMOUNT;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() ERC721("SP1 Bridge Poc", "SBP") Ownable(msg.sender) {
        CHAIN_ID = block.chainid;
        // 5% annually (APY)
        REWARD_RATE = 500;
        COUNTER++;
        SCALING_FACTOR = 1e18;
        _disableInitializers();
    }

    /// @inheritdoc IStakeManager
    function initialize(
        StakeManagerConfig memory config,
        address manager
    )
        external
        override
        initializer
    {
        emit StakeManagerConfigUpdated(ACTIVE_STAKING_CONFIG, config);
        ACTIVE_STAKING_CONFIG = config;
        VALIDATOR_MANAGER = manager;

        SMStorage storage $ = __loadStorage();
        $.stakingManagerVersions[getStakeVersion(config)] = config;

        NAME = "StakeManager";
        VERSION = "1";
        POP_STAKE_DOMAIN = "StakeManager:BN254:PoP:v1:";
        // ~90 days at 10 min epochs assuming we dont change this we could
        // instead add a function to update this but for now its ayt
        EARLY_BONUS_EPOCHS = 12960;
        // 80% performance minimum
        MIN_PERFORMANCE_THRESHOLD = 80;
        // 1 token bonus could be more but this is a POC
        EARLY_BONUS_AMOUNT = 1e18;

        __UUPSUpgradeable_init();
    }

    /// @inheritdoc IStakeManager
    function stake(
        StakeParams memory params,
        BlsOwnerShip memory proof
    )
        external
        override
        whenNotPaused
    {
        uint256[2] memory msgToVerify = proofOfPossessionMessage(proof.pubkey);
        (bool pairingSuccess, bool callSuccess) =
            BLS.verifySingle(proof.signature, proof.pubkey, msgToVerify);

        require(pairingSuccess && callSuccess, NotOwnerBLS());
        require(
            params.stakeVersion == getStakeVersion(ACTIVE_STAKING_CONFIG), InvalidStakeVersion()
        );
        require(
            params.stakeAmount >= ACTIVE_STAKING_CONFIG.minStakeAmount, MinStakeAmountRequired()
        );

        IERC20 token = IERC20(ACTIVE_STAKING_CONFIG.stakingToken);
        require(token.allowance(msg.sender, address(this)) >= params.stakeAmount, NotApproved());
        require(token.transferFrom(msg.sender, address(this), params.stakeAmount), TransferFailed());

        SMStorage storage $ = __loadStorage();
        ValidatorBalance storage validator = $.balances[msg.sender];
        StakeManagerConfig memory config = $.stakingManagerVersions[params.stakeVersion];
        require(config.minStakeAmount > 0, InvalidStakingConfig());

        if (validator.tokenId == 0) {
            _mintValidatorNFT(msg.sender, proof.pubkey);
        }

        validator.stakeAmount += params.stakeAmount;
        validator.stakeVersion = params.stakeVersion;
        validator.stakeTimestamp = block.timestamp;
        validator.pubkey = params.pubkey;

        emit ValidatorStaked(
            msg.sender, validator.stakeVersion, validator.stakeAmount, block.timestamp
        );
    }

    /// @inheritdoc ERC721
    /// @dev Transfers are disabled for validator NFTs
    function transferFrom(address, address, uint256) public pure override(IERC721, ERC721) {
        revert NotAllowed();
    }

    /// @inheritdoc ERC721
    /// @dev Approvals are disabled for validator NFTs
    function approve(address, uint256) public pure override(IERC721, ERC721) {
        revert NotAllowed();
    }

    /// @inheritdoc IStakeManager
    function proofOfPossessionMessage(uint256[4] memory blsPubkey)
        public
        view
        override
        returns (uint256[2] memory)
    {
        bytes memory messageBytes = abi.encodePacked(
            POP_STAKE_DOMAIN, blsPubkey[0], blsPubkey[1], blsPubkey[2], blsPubkey[3], msg.sender
        );
        return BLS.hashToPoint(POP_STAKE_DOMAIN, messageBytes);
    }

    /// @inheritdoc IStakeManager
    function getStakeVersion(StakeManagerConfig memory config)
        public
        pure
        override
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                config.minStakeAmount,
                config.minWithdrawAmount,
                config.minUnstakeDelay,
                config.correctProofReward,
                config.incorrectProofPenalty,
                config.maxMissedProofs,
                config.slashingRate,
                config.stakingToken
            )
        );
    }

    /// @inheritdoc IStakeManager
    function beginUnstaking(UnstakingParams memory params) external override onlyValidatorManager {
        SMStorage storage $ = __loadStorage();
        ValidatorBalance storage validator = $.balances[params.validator];
        StakeManagerConfig memory config = $.stakingManagerVersions[params.stakeVersion];

        require(config.minStakeAmount > 0, InvalidStakingConfig());
        require(validator.stakeAmount > 0, ValidatorNotFound());
        require(validator.stakeExitTimestamp == 0, NotAllowed());
        require(validator.stakeAmount >= config.minStakeAmount, MinStakeAmountRequired());

        validator.stakeExitTimestamp = block.timestamp;
        validator.unstakeAmount = params.stakeAmount;

        emit ValidatorCoolDown(
            params.validator, validator.stakeVersion, validator.stakeTimestamp, block.timestamp
        );
    }

    /// @inheritdoc IStakeManager
    function completeUnstaking(address who) external override onlyValidatorManager {
        SMStorage storage $ = __loadStorage();
        ValidatorBalance storage validator = $.balances[who];

        require(validator.stakeAmount > 0, ValidatorNotFound());
        require(validator.stakeExitTimestamp > 0, NotAllowed());
        require(
            block.timestamp >= validator.stakeExitTimestamp + ACTIVE_STAKING_CONFIG.minUnstakeDelay,
            NotAllowed()
        );
        require(validator.unstakeAmount > 0, NotAllowed());

        uint256 totalAmount = validator.unstakeAmount;
        uint256 rewardAmount = validator.balance;
        bool partialExit = _processUnstaking(validator);

        // Handle full vs partial exit
        if (!partialExit) {
            delete $.balances[who];
        } else {
            require(
                validator.stakeAmount >= ACTIVE_STAKING_CONFIG.minStakeAmount, BelowMinimumStake()
            );
            validator.unstakeAmount = 0;
            validator.stakeExitTimestamp = 0;
        }

        IERC20 token = IERC20(ACTIVE_STAKING_CONFIG.stakingToken);
        require(token.transfer(who, totalAmount), TransferFailed());

        emit ValidatorExit(who, validator.stakeVersion, rewardAmount, partialExit);
    }

    /// @inheritdoc IStakeManager
    function upgradeStakeConfig(StakeManagerConfig calldata config) external override onlyOwner {
        emit StakeManagerConfigUpdated(ACTIVE_STAKING_CONFIG, config);
        ACTIVE_STAKING_CONFIG = config;
    }

    /// @inheritdoc IStakeManager
    function slashValidator(SlashParams calldata params) external override onlyValidatorManager {
        require(params.slashAmount > 0, ZeroSlashAmount());

        SMStorage storage $ = __loadStorage();
        ValidatorBalance storage validator = $.balances[params.validator];

        require(validator.stakeAmount > 0, ValidatorNotFound());
        uint256 balance = validator.stakeAmount + validator.balance;
        require(balance >= params.slashAmount, InsufficientStakeToSlash());

        uint256 originalStake = validator.stakeAmount;
        _processSlashing(validator, params.slashAmount);

        if (validator.stakeAmount > 0) {
            require(
                validator.stakeAmount >= ACTIVE_STAKING_CONFIG.minStakeAmount, BelowMinimumStake()
            );
        }

        emit ValidatorSlashed(
            params.validator,
            params.slashAmount,
            originalStake,
            validator.stakeAmount,
            block.timestamp
        );
    }

    /// @inheritdoc IStakeManager
    function distributeRewards(RewardsParams calldata params)
        external
        override
        onlyValidatorManager
    {
        require(params.recipients.length > 0, NoValidators());

        uint256 rewardPool = _calculateEpochRewardPool();
        require(rewardPool > 0, InsufficientTreasury());

        uint256 totalPoints = _calculateTotalPoints(params.recipients);
        require(totalPoints > 0, NoEligibleValidators());

        uint256 distributedTotal = _distributeToValidators(
            params.recipients, rewardPool, totalPoints, params.epoch, params.epochDuration
        );

        emit RewardsDistributed(distributedTotal, params.recipients.length, params.epoch);
    }

    /// @inheritdoc IStakeManager
    function claimRewards() external override {
        SMStorage storage $ = __loadStorage();
        ValidatorBalance storage validator = $.balances[msg.sender];

        require(validator.balance > 0, NoRewardsToClaim());
        uint256 amount = validator.balance;
        validator.balance = 0;

        IERC20 token = IERC20(ACTIVE_STAKING_CONFIG.stakingToken);
        require(token.transfer(msg.sender, amount), TransferFailed());

        emit ValidatorRewardsClaimed(msg.sender, amount, block.timestamp);
    }

    /// @inheritdoc IStakeManager
    function getLatestRewards(address validator) external view override returns (uint256) {
        SMStorage storage $ = __loadStorage();
        return $.balances[validator].balance;
    }

    /// @inheritdoc IStakeManager
    function pause() external override onlyOwner {
        _pause();
    }

    /// @inheritdoc IStakeManager
    function unPause() external override onlyOwner {
        _unpause();
    }

    /// @notice Mint NFT and register new validator
    /// @param validator Address of the validator
    /// @param pubkey BLS public key of the validator
    function _mintValidatorNFT(address validator, uint256[4] memory pubkey) internal {
        uint256 tokenId = COUNTER++;
        SMStorage storage $ = __loadStorage();
        $.balances[validator].tokenId = tokenId;
        _mint(validator, tokenId);

        IValidatorTypes.ValidatorInfo memory info = IValidatorTypes.ValidatorInfo({
            blsPublicKey: pubkey,
            wallet: validator,
            status: IValidatorTypes.ValidatorStatus.Active,
            attestationCount: 0,
            invalidAttestations: 0
        });
        IValidatorManager(VALIDATOR_MANAGER).addValidator(info);
    }

    /// @notice Process unstaking by deducting from stake and/or rewards
    /// @param validator Storage reference to validator balance
    /// @return partialExit Whether this is a partial or full exit
    function _processUnstaking(ValidatorBalance storage validator)
        internal
        returns (bool partialExit)
    {
        if (validator.stakeAmount >= validator.unstakeAmount) {
            validator.stakeAmount -= validator.unstakeAmount;
            partialExit = validator.stakeAmount > 0;
        } else if (validator.balance >= validator.unstakeAmount) {
            validator.balance -= validator.unstakeAmount;
            partialExit = true;
        } else {
            uint256 remainingAmount = validator.unstakeAmount - validator.balance;
            validator.balance = 0;
            validator.stakeAmount -= remainingAmount;
            partialExit = validator.stakeAmount > 0;
        }

        if (!partialExit) {
            _burn(validator.tokenId);
        }

        return partialExit;
    }

    /// @notice Process slashing by deducting from stake and/or rewards
    /// @param validator Storage reference to validator balance
    /// @param slashAmount Amount to slash
    function _processSlashing(ValidatorBalance storage validator, uint256 slashAmount) internal {
        if (validator.stakeAmount >= slashAmount) {
            validator.stakeAmount -= slashAmount;
        } else if (validator.balance >= slashAmount) {
            validator.balance -= slashAmount;
        } else {
            uint256 remainingSlash = slashAmount - validator.balance;
            validator.balance = 0;
            validator.stakeAmount -= remainingSlash;
        }
    }

    /// @notice Calculate total reward pool for current epoch
    /// @return rewardPool Total rewards available for distribution
    function _calculateEpochRewardPool() internal view returns (uint256 rewardPool) {
        SMStorage storage $ = __loadStorage();
        IValidatorManager manager = IValidatorManager(VALIDATOR_MANAGER);
        address[] memory activeValidators = manager.getActiveValidators();

        uint256 totalStaked = 0;
        for (uint256 i = 0; i < activeValidators.length; i++) {
            totalStaked += $.balances[activeValidators[i]].stakeAmount;
        }

        require(totalStaked > 0, NoStakedAmount());

        uint256 epochsPerYear = manager.getEpochsPerYear();
        uint256 epochReward = (totalStaked * REWARD_RATE) / (10000 * epochsPerYear);

        // Apply scaling to prevent excessive inflation
        uint256 scalingFactor = _sqrt(totalStaked / SCALING_FACTOR);
        if (scalingFactor > 1) {
            epochReward = epochReward / scalingFactor;
        }

        uint256 minReward = totalStaked / 1000000;
        uint256 maxReward = totalStaked / 10000;

        if (epochReward < minReward) return minReward;
        if (epochReward > maxReward) return maxReward;
        return epochReward;
    }

    /// @notice Calculate total points for all validators
    /// @param validators Array of validator info structs
    /// @return totalPoints Sum of all validator points
    function _calculateTotalPoints(IValidatorTypes.ValidatorInfo[] memory validators)
        internal
        view
        returns (uint256 totalPoints)
    {
        SMStorage storage $ = __loadStorage();

        for (uint256 i = 0; i < validators.length; i++) {
            uint256 correctAttestations =
                validators[i].attestationCount - validators[i].invalidAttestations;
            uint256 stakeAmount = $.balances[validators[i].wallet].stakeAmount;
            totalPoints += _calculateValidatorPoints(stakeAmount, correctAttestations);
        }
        return totalPoints;
    }

    /// @notice Distribute rewards to all eligible validators
    /// @param validators Array of validator info
    /// @param rewardPool Total rewards to distribute
    /// @param totalPoints Total points for proportional calculation
    /// @param currentEpoch Current epoch number
    /// @param epochDuration Duration of each epoch in seconds
    /// @return distributedTotal Total amount actually distributed
    function _distributeToValidators(
        IValidatorTypes.ValidatorInfo[] memory validators,
        uint256 rewardPool,
        uint256 totalPoints,
        uint256 currentEpoch,
        uint256 epochDuration
    )
        internal
        returns (uint256 distributedTotal)
    {
        SMStorage storage $ = __loadStorage();

        for (uint256 i = 0; i < validators.length; i++) {
            IValidatorTypes.ValidatorInfo memory validatorInfo = validators[i];

            uint256 correctAttestations =
                validatorInfo.attestationCount - validatorInfo.invalidAttestations;
            uint256 performanceScore = validatorInfo.attestationCount > 0
                ? (correctAttestations * 100) / validatorInfo.attestationCount
                : 0;

            require(performanceScore >= MIN_PERFORMANCE_THRESHOLD, LowPerformance());

            ValidatorBalance storage validatorBalance = $.balances[validatorInfo.wallet];

            // Calculate base reward
            uint256 validatorPoints =
                _calculateValidatorPoints(validatorBalance.stakeAmount, correctAttestations);
            uint256 finalReward = (rewardPool * validatorPoints) / totalPoints;

            // Add early bonus if applicable
            uint256 earlyBonus =
                _calculateEarlyBonus(validatorBalance.stakeTimestamp, currentEpoch, epochDuration);
            finalReward += earlyBonus;

            // Update validator balance
            validatorBalance.balance += finalReward;
            validatorBalance.lastRewardEpoch = currentEpoch;
            distributedTotal += finalReward;

            emit ValidatorRewarded(
                validatorInfo.wallet, finalReward, performanceScore, correctAttestations
            );
        }

        return distributedTotal;
    }

    /// @notice Calculate points for a validator based on stake and performance
    /// @param stakeAmount Validator's stake amount
    /// @param correctAttestations Number of correct attestations
    /// @return points Total points for this validator
    function _calculateValidatorPoints(
        uint256 stakeAmount,
        uint256 correctAttestations
    )
        internal
        view
        returns (uint256 points)
    {
        uint256 stakePoints = stakeAmount / SCALING_FACTOR;
        uint256 performancePoints = correctAttestations * 10;
        return stakePoints + performancePoints;
    }

    /// @notice Calculate early validator bonus
    /// @param stakeTimestamp When validator first staked
    /// @param currentEpoch Current epoch number
    /// @param epochDuration Duration of each epoch
    /// @return bonus Early validator bonus amount
    function _calculateEarlyBonus(
        uint256 stakeTimestamp,
        uint256 currentEpoch,
        uint256 epochDuration
    )
        internal
        view
        returns (uint256 bonus)
    {
        uint256 stakeStartEpoch = stakeTimestamp / epochDuration;
        uint256 epochsStaked = currentEpoch - stakeStartEpoch;

        if (epochsStaked >= EARLY_BONUS_EPOCHS) return 0;

        uint256 remainingBonusEpochs = EARLY_BONUS_EPOCHS - epochsStaked;
        return (EARLY_BONUS_AMOUNT * remainingBonusEpochs) / EARLY_BONUS_EPOCHS;
    }

    /// @notice Calculate square root using Newton's method
    /// @param x Input value
    /// @return y Square root of x
    function _sqrt(uint256 x) internal pure returns (uint256 y) {
        uint256 z = (x + 1) / 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }

    /// @notice Authorize contract upgrades
    /// @dev Only owner can authorize upgrades per UUPS pattern
    /// @param newImplementation Address of new implementation contract
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
