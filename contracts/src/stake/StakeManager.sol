// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {
    ERC721EnumerableUpgradeable,
    ERC721Upgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {PausableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from
    "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {BLS} from "solbls/BLS.sol";
import {StakeManagerStorage} from "./StakeManagerStorage.sol";
import {ArrayContainsLib} from "../libs/ArrayContainsLib.sol";
import {IStakeManager} from "./IStakeManager.sol";
import {IValidatorManager, IValidatorTypes} from "../validator/IValidatorManager.sol";

/// @title Stake Manager
/// @author Brianspha
/// @notice Manages validator stakes, rewards, and slashing for bridge validation system
contract StakeManager is
    IStakeManager,
    Initializable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    ERC721EnumerableUpgradeable,
    StakeManagerStorage,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using BLS for *;
    using ArrayContainsLib for address[];
    using SafeERC20 for IERC20;

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

    uint256 public immutable PERFORMANCE_SCALE;

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
    constructor() {
        CHAIN_ID = block.chainid;
        REWARD_RATE = 500;
        SCALING_FACTOR = 1e18;
        PERFORMANCE_SCALE = 10_000;
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
        COUNTER = 1;
        NAME = "StakeManager";
        VERSION = "1";
        POP_STAKE_DOMAIN = "StakeManager:BN254:PoP:v1:";
        // ~90 days at 10 min epochs assuming we dont change this we could
        // instead add a function to update this but for now its ayt
        EARLY_BONUS_EPOCHS = 12_960;
        // 80% performance minimum
        MIN_PERFORMANCE_THRESHOLD = 8_000;
        // 1 token bonus could be more but this is a POC
        EARLY_BONUS_AMOUNT = 1e18;

        __Ownable_init(msg.sender);
        __ERC721_init("SP1 Bridge Poc", "SBP");
        __Pausable_init();
        __UUPSUpgradeable_init();

        upgradeStakeConfig(config);
        updateValidatorManager(manager);
    }

    /// @inheritdoc IStakeManager
    function updateValidatorManager(address manager) public onlyOwner {
        emit UpdatedValidatorManager(VALIDATOR_MANAGER, manager);
        VALIDATOR_MANAGER = manager;
    }

    /// @inheritdoc IStakeManager
    function stake(
        StakeParams memory params,
        BlsOwnerShip memory proof
    )
        external
        override
        whenNotPaused
        nonReentrant
    {
        uint256[2] memory msgToVerify = proofOfPossessionMessage(proof.pubkey);
        SMStorage storage $ = _loadStorage();
        ValidatorBalance storage validator = $.balances[msg.sender];

        bytes32 currentStakeVersion = getStakeVersion(ACTIVE_STAKING_CONFIG);
        require(BLS.isValidPublicKey(proof.pubkey), InvalidPublicKey());
        require(BLS.isValidSignature(proof.signature), InvalidSignature());
        (bool pairingSuccess, bool callSuccess) =
            BLS.verifySingle(proof.signature, proof.pubkey, msgToVerify);
        require(pairingSuccess && callSuccess, NotOwnerBLS());
        require(params.stakeVersion == currentStakeVersion, InvalidStakeVersion());

        if (validator.stakeAmount == 0) {
            require(
                params.stakeAmount >= ACTIVE_STAKING_CONFIG.minStakeAmount, MinStakeAmountRequired()
            );
        } else {
            require(validator.stakeVersion == currentStakeVersion, MigrateToNewVersion());
        }

        IERC20 token = IERC20(ACTIVE_STAKING_CONFIG.stakingToken);
        token.safeTransferFrom(msg.sender, address(this), params.stakeAmount);

        // Increase principal by the newly staked amount
        $.principal[ACTIVE_STAKING_CONFIG.stakingToken] += params.stakeAmount;

        if (validator.tokenId == 0) {
            validator.pubkey = proof.pubkey;
            _mintValidatorNFT(msg.sender, proof.pubkey);
        }
        IValidatorTypes.ValidatorInfo memory info =
            IValidatorManager(VALIDATOR_MANAGER).getValidator(msg.sender);
        if (info.status == IValidatorTypes.ValidatorStatus.Inactive) {
            IValidatorManager(VALIDATOR_MANAGER).updateValidatorStatus(
                msg.sender, IValidatorTypes.ValidatorStatus.Active
            );
        }

        validator.stakeAmount += params.stakeAmount;
        validator.stakeVersion = params.stakeVersion;
        validator.stakeTimestamp = block.timestamp;

        emit ValidatorStaked(
            msg.sender, validator.stakeVersion, validator.stakeAmount, block.timestamp
        );
    }

    /// @inheritdoc IStakeManager
    function transferToken(
        address token,
        uint256 amount
    )
        external
        override
        onlyOwner
        nonReentrant
    {
        require(token != address(0), ZeroAddress());
        require(amount > 0, NotAllowed());

        IERC20 erc = IERC20(token);
        uint256 balBefore = erc.balanceOf(address(this));
        erc.safeTransferFrom(msg.sender, address(this), amount);
        uint256 balAfter = erc.balanceOf(address(this));

        uint256 received = balAfter - balBefore;
        require(received > 0, NotReservesRecieved());

        // credit rewards budget for this token
        SMStorage storage $ = _loadStorage();
        $.rewardReserves[token] += received;

        emit RewardTopUp(token, received, msg.sender);
    }

    /// @inheritdoc IStakeManager
    function sweepExcess(address token, uint256 amount) external onlyOwner nonReentrant {
        SMStorage storage $ = _loadStorage();

        uint256 required = $.rewardReserves[token];
        require(required > amount, NoAccessReserves());

        IERC20(token).safeTransfer(msg.sender, amount);
    }

    /// @inheritdoc ERC721Upgradeable
    /// @dev Transfers are disabled for validator NFTs
    function transferFrom(
        address,
        address,
        uint256
    )
        public
        pure
        override(IERC721, ERC721Upgradeable)
    {
        revert NotAllowed();
    }

    /// @inheritdoc ERC721Upgradeable
    /// @dev Approvals are disabled for validator NFTs
    function approve(address, uint256) public pure override(IERC721, ERC721Upgradeable) {
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
            CHAIN_ID, blsPubkey[0], blsPubkey[1], blsPubkey[2], blsPubkey[3], msg.sender
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
    function beginUnstaking(UnstakingParams memory params) external override {
        SMStorage storage $ = _loadStorage();
        ValidatorBalance storage validator = $.balances[msg.sender];
        StakeManagerConfig memory config = $.stakingManagerVersions[validator.stakeVersion];
        IValidatorTypes.ValidatorInfo memory info =
            IValidatorManager(VALIDATOR_MANAGER).getValidator(msg.sender);

        require(config.minStakeAmount > 0, InvalidStakingConfig());

        if (info.status == IValidatorTypes.ValidatorStatus.Inactive) {
            // This is the case where validators want to exit after being
            // Jailed for being slashed below the threshold and do not want
            // To topup we also reset their rewards to 0 since everything
            // Is being withdrawn
            validator.unstakeAmount = validator.stakeAmount + validator.balance;
            validator.stakeAmount = 0;
            validator.balance = 0;
        } else {
            require(validator.unstakeAmount == 0, NotAllowed());
            require(validator.stakeAmount > 0, ValidatorNotFound());
            require(validator.stakeExitTimestamp == 0, NotAllowed());
            require(params.stakeAmount > 0, MinStakeAmountRequired());
            require(params.stakeAmount <= validator.stakeAmount, AmountExceedsStake());
            require(params.stakeAmount > config.minWithdrawAmount, MinStakeAmountRequired());
            uint256 remaining = validator.stakeAmount - params.stakeAmount;
            bool fullExit = remaining == 0;

            if (!fullExit) {
                require(remaining >= config.minStakeAmount, BelowMinimumStake());
            }

            validator.unstakeAmount = params.stakeAmount;
            validator.stakeExitTimestamp = block.timestamp + config.minUnstakeDelay;
        }

        IValidatorManager(VALIDATOR_MANAGER).updateValidatorStatus(
            msg.sender, IValidatorTypes.ValidatorStatus.Unstaking
        );

        emit ValidatorCoolDown(
            msg.sender,
            validator.stakeVersion,
            validator.stakeTimestamp,
            validator.stakeExitTimestamp
        );
    }

    event Here(uint256 indexed amount, uint256 indexed principal);

    /// @inheritdoc IStakeManager
    function completeUnstaking() external override nonReentrant {
        SMStorage storage $ = _loadStorage();
        ValidatorBalance storage validator = $.balances[msg.sender];
        StakeManagerConfig memory config = $.stakingManagerVersions[validator.stakeVersion];
        require(validator.stakeExitTimestamp > 0, NotAllowed());
        require(block.timestamp >= validator.stakeExitTimestamp, NotAllowed());
        require(validator.unstakeAmount > 0, NotAllowed());
        require(config.minStakeAmount > 0, InvalidStakeVersion());
        uint256 totalAmount = validator.unstakeAmount;
        uint256 rewardAmount = validator.balance;
        bool partialExit = _processUnstaking(validator);
        bytes32 stakeVersion = validator.stakeVersion;
        emit Here(totalAmount, $.principal[config.stakingToken]);
        $.principal[config.stakingToken] -= totalAmount;

        if (!partialExit) {
            IValidatorManager(VALIDATOR_MANAGER).removeValidator(msg.sender);
            delete $.balances[msg.sender];
        } else {
            validator.unstakeAmount = 0;
            validator.stakeExitTimestamp = 0;
        }

        IERC20 token = IERC20(config.stakingToken);
        token.safeTransfer(msg.sender, totalAmount);

        emit ValidatorExit(msg.sender, stakeVersion, rewardAmount, partialExit);
    }

    /// @inheritdoc IStakeManager
    function upgradeStakeConfig(StakeManagerConfig memory config) public override onlyOwner {
        emit StakeManagerConfigUpdated(ACTIVE_STAKING_CONFIG, config);
        ACTIVE_STAKING_CONFIG = config;
        SMStorage storage $ = _loadStorage();
        $.stakingManagerVersions[getStakeVersion(ACTIVE_STAKING_CONFIG)] = config;
    }

    /// @inheritdoc IStakeManager
    function slashValidator(SlashParams calldata params) external override onlyValidatorManager {
        require(params.slashAmount > 0, ZeroSlashAmount());

        SMStorage storage $ = _loadStorage();
        ValidatorBalance storage validator = $.balances[params.validator];
        StakeManagerConfig memory config = $.stakingManagerVersions[validator.stakeVersion];
        require(config.minStakeAmount > 0, InvalidStakeVersion());
        require(validator.stakeAmount > 0, ValidatorNotFound());

        uint256 balance = validator.stakeAmount + validator.balance;
        require(balance >= params.slashAmount, InsufficientStakeToSlash());

        uint256 originalStake = validator.stakeAmount;

        // Compute how much of the slash comes from stake vs. accrued rewards.
        (uint256 fromStake, uint256 fromRewards) = _processSlashing(validator, params.slashAmount);

        // Reallocate: principal reduces by stake portion; reserves increase by total slashed.
        $.principal[config.stakingToken] -= fromStake;
        $.rewardReserves[config.stakingToken] += (fromStake + fromRewards);

        // Strict threshold: if remaining stake is >0 but below min, jail (set Inactive) until top-up.
        // Theres probz a better design but we keeping it simple here
        if (
            validator.stakeAmount > 0
                && validator.stakeAmount < ACTIVE_STAKING_CONFIG.minStakeAmount
        ) {
            IValidatorManager(VALIDATOR_MANAGER).updateValidatorStatus(
                params.validator, IValidatorTypes.ValidatorStatus.Inactive
            );
            validator.stakeExitTimestamp = block.timestamp;
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

        require(
            params.epochDuration == IValidatorManager(VALIDATOR_MANAGER).epochDuration(),
            EpochDurationMisMatch()
        );

        uint256 distributedTotal =
            _distributeToValidators(params.recipients, rewardPool, params.epoch);

        emit RewardsDistributed(distributedTotal, params.recipients.length, params.epoch);
    }

    /// @inheritdoc IStakeManager
    function claimRewards() external override nonReentrant {
        SMStorage storage $ = _loadStorage();
        ValidatorBalance storage validator = $.balances[msg.sender];
        address stakingToken = $.stakingManagerVersions[validator.stakeVersion].stakingToken;
        require(validator.balance > 0, NoRewardsToClaim());
        uint256 amount = validator.balance;
        require($.rewardReserves[stakingToken] >= amount, NoRewards());
        validator.balance = 0;

        IERC20 token = IERC20(stakingToken);
        token.safeTransfer(msg.sender, amount);
        $.rewardReserves[stakingToken] =
            amount >= $.rewardReserves[stakingToken] ? 0 : $.rewardReserves[stakingToken] - amount;
        emit ValidatorRewardsClaimed(msg.sender, amount, block.timestamp);
    }

    /// @inheritdoc IStakeManager
    function getLatestRewards(address validator) external view override returns (uint256) {
        SMStorage storage $ = _loadStorage();
        return $.balances[validator].balance;
    }

    /// @inheritdoc IStakeManager
    function validatorBalance(address validator)
        external
        view
        returns (ValidatorBalance memory info)
    {
        SMStorage storage $ = _loadStorage();
        info = $.balances[validator];
    }

    /// @inheritdoc ERC721Upgradeable
    function safeTransferFrom(
        address,
        address,
        uint256,
        bytes memory
    )
        public
        pure
        override(IERC721, ERC721Upgradeable)
    {
        revert NotAllowed();
    }

    /// @inheritdoc ERC721Upgradeable
    function setApprovalForAll(address, bool) public pure override(IERC721, ERC721Upgradeable) {
        revert NotAllowed();
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
        SMStorage storage $ = _loadStorage();
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
            // Theres a scenario where the validator has been jailed
            // But have no interest on topping up since they were slahed
            // Below the min stake amount as such they want to withdraw everything
            // Including the rewards they have accumalated we could use their rewards
            // To top up but thats up to them we care for allowing them to withdraw everything
            // So the below statement of substracting from stakeAmount the remaining amount needs
            // To ensure that we cater for if the stakeAmount has been reset to 0 in the beginUnstake
            // Step since the validators rewards have also been also reset to 0
            validator.stakeAmount =
                validator.stakeAmount > 0 ? validator.stakeAmount - remainingAmount : 0;
            partialExit = validator.stakeAmount > 0;
        }

        if (!partialExit) {
            _burn(validator.tokenId);
        }

        return partialExit;
    }

    /// @notice Process slashing by deducting from stake and/or rewards, and return the split sources
    /// @param validator Storage reference to validator balance
    /// @param slashAmount Amount to slash
    /// @return fromStake Amount deducted from principal stake
    /// @return fromRewards Amount deducted from accrued-but-unclaimed rewards
    function _processSlashing(
        ValidatorBalance storage validator,
        uint256 slashAmount
    )
        internal
        returns (uint256 fromStake, uint256 fromRewards)
    {
        if (validator.stakeAmount >= slashAmount) {
            // Entire slash comes from stake.
            validator.stakeAmount -= slashAmount;
            fromStake = slashAmount;
            fromRewards = 0;
        } else if (validator.balance >= slashAmount) {
            // Entire slash comes from rewards.
            validator.balance -= slashAmount;
            fromStake = 0;
            fromRewards = slashAmount;
        } else {
            // Consume all rewards first, then the remainder from stake.
            uint256 remainingSlash = slashAmount - validator.balance;
            fromRewards = validator.balance;
            validator.balance = 0;
            validator.stakeAmount -= remainingSlash;
            fromStake = remainingSlash;
        }
    }

    /// @notice Calculate total reward pool for current epoch
    /// @return rewardPool Total rewards available for distribution
    function _calculateEpochRewardPool() internal view returns (uint256 rewardPool) {
        SMStorage storage $ = _loadStorage();
        IValidatorManager manager = IValidatorManager(VALIDATOR_MANAGER);
        address[] memory activeValidators = manager.getActiveValidators();

        uint256 totalStaked = 0;
        for (uint256 i = 0; i < activeValidators.length; i++) {
            totalStaked += $.balances[activeValidators[i]].stakeAmount;
        }

        require(totalStaked > 0, NoStakedAmount());

        uint256 epochsPerYear = manager.getEpochsPerYear();
        uint256 denominator = PERFORMANCE_SCALE * epochsPerYear;
        uint256 epochReward = Math.mulDiv(totalStaked, REWARD_RATE, denominator);

        uint256 scalingBase = totalStaked / 1_000_000;
        uint256 scalingFactor = Math.sqrt(scalingBase);

        if (scalingFactor > 1) {
            epochReward = epochReward / scalingFactor;
        }

        uint256 minReward = totalStaked / 1_000_000;
        uint256 maxReward = totalStaked / 10_000;

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
        SMStorage storage $ = _loadStorage();

        for (uint256 i = 0; i < validators.length; i++) {
            uint256 correctAttestations = validators[i].attestationCount
                > validators[i].invalidAttestations
                ? validators[i].attestationCount - validators[i].invalidAttestations
                : 0;

            uint256 stakeAmount = $.balances[validators[i].wallet].stakeAmount;
            totalPoints += _calculateValidatorPoints(stakeAmount, correctAttestations);
        }
        return totalPoints;
    }

    /// @notice Distribute rewards to all eligible validators
    /// @param validators Array of validator info
    /// @param rewardPool Total rewards to distribute
    /// @param currentEpoch Current epoch number
    /// @return distributedTotal Total amount actually distributed
    function _distributeToValidators(
        IValidatorTypes.ValidatorInfo[] memory validators,
        uint256 rewardPool,
        uint256 currentEpoch
    )
        internal
        returns (uint256 distributedTotal)
    {
        SMStorage storage $ = _loadStorage();

        uint256 totalPoints = 0;
        bool[] memory eligible = new bool[](validators.length);

        for (uint256 i = 0; i < validators.length; i++) {
            IValidatorTypes.ValidatorInfo memory vi = validators[i];

            // Defensive status gate: skip non-Active or under-min-stake validators.
            IValidatorTypes.ValidatorInfo memory live =
                IValidatorManager(VALIDATOR_MANAGER).getValidator(vi.wallet);
            if (
                $.balances[vi.wallet].stakeAmount < ACTIVE_STAKING_CONFIG.minStakeAmount
                    || live.status != IValidatorTypes.ValidatorStatus.Active
            ) {
                eligible[i] = false;
                continue;
            }

            uint256 correctAttestations = vi.attestationCount > vi.invalidAttestations
                ? vi.attestationCount - vi.invalidAttestations
                : 0;

            uint256 performanceScore = (vi.attestationCount == 0)
                ? 0
                : Math.mulDiv(correctAttestations, PERFORMANCE_SCALE, vi.attestationCount);

            ValidatorBalance storage balance = $.balances[vi.wallet];
            if (balance.lastRewardEpoch >= currentEpoch) {
                eligible[i] = false;
                continue;
            }
            if (performanceScore < MIN_PERFORMANCE_THRESHOLD) {
                eligible[i] = false;
                continue;
            }

            uint256 points = _calculateValidatorPoints(balance.stakeAmount, correctAttestations);

            if (points == 0) {
                eligible[i] = false;
                continue;
            }

            eligible[i] = true;
            totalPoints += points;
        }

        require(totalPoints > 0, NoEligibleValidators());

        for (uint256 i = 0; i < validators.length; i++) {
            if (!eligible[i]) continue;

            IValidatorTypes.ValidatorInfo memory validatorInfo = validators[i];
            ValidatorBalance storage balance = $.balances[validatorInfo.wallet];

            uint256 correctAttestations = validatorInfo.attestationCount
                > validatorInfo.invalidAttestations
                ? validatorInfo.attestationCount - validatorInfo.invalidAttestations
                : 0;

            uint256 validatorPoints =
                _calculateValidatorPoints(balance.stakeAmount, correctAttestations);

            uint256 finalReward = Math.mulDiv(rewardPool, validatorPoints, totalPoints);

            uint256 earlyBonus = _calculateEarlyBonus(balance.stakeTimestamp);
            finalReward = finalReward + earlyBonus;

            balance.balance = balance.balance + finalReward;
            balance.lastRewardEpoch = currentEpoch;
            distributedTotal = distributedTotal + finalReward;

            emit ValidatorRewarded(validatorInfo.wallet, finalReward, correctAttestations);
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
    /// @return bonus Early validator bonus amount
    function _calculateEarlyBonus(uint256 stakeTimestamp) internal view returns (uint256 bonus) {
        uint256 epochsStaked =
            IValidatorManager(VALIDATOR_MANAGER).epochsElapsedSince(stakeTimestamp);

        if (epochsStaked >= EARLY_BONUS_EPOCHS) return 0;

        uint256 remaining = EARLY_BONUS_EPOCHS - epochsStaked;
        bonus = Math.mulDiv(EARLY_BONUS_AMOUNT, remaining, EARLY_BONUS_EPOCHS);
    }

    /// @notice Authorize contract upgrades
    /// @dev Only owner can authorize upgrades per UUPS pattern
    /// @param newImplementation Address of new implementation contract
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
