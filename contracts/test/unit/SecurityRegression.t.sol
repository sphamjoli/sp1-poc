// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Bridge} from "../../src/bridge/Bridge.sol";
import {StakeManager} from "../../src/stake/StakeManager.sol";
import {ValidatorManager} from "../../src/validator/ValidatorManager.sol";
import {IStakeManagerTypes} from "../../src/stake/IStakeManagerTypes.sol";
import {IValidatorTypes} from "../../src/validator/IValidatorTypes.sol";
import {IBridgeTypes} from "../../src/bridge/BridgeTypes.sol";
import {LocalExitTreeLib} from "../../src/libs/LocalExitTreeLib.sol";

contract SecurityToken is ERC20 {
    bool public chargeFee;

    constructor() ERC20("Security test token", "SEC") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function setFee(bool enabled) external {
        chargeFee = enabled;
    }

    function _update(address from, address to, uint256 value) internal override {
        if (chargeFee && from != address(0) && to != address(0)) {
            uint256 fee = value / 100;
            super._update(from, address(0), fee);
            value -= fee;
        }
        super._update(from, to, value);
    }
}

contract StakeAccountingHarness is StakeManager {
    function accounting(address token) external view returns (uint256, uint256, uint256) {
        SmStorage storage $ = _loadStorage();
        return ($.principal[token], $.rewardReserves[token], $.accruedRewards[token]);
    }
}

contract SecurityRegressionTest is Test {
    SecurityToken internal token;
    StakeAccountingHarness internal stake;
    ValidatorManager internal manager;
    Bridge internal bridge;
    address internal alice;
    IStakeManagerTypes.StakeManagerConfig internal config;

    function setUp() public {
        vm.warp(1_000_000);
        alice = makeAddr("security-alice");
        token = new SecurityToken();
        config = IStakeManagerTypes.StakeManagerConfig({
            minStakeAmount: 100 ether,
            minWithdrawAmount: 1 ether,
            minUnstakeDelay: 2 days,
            correctProofReward: 1 ether,
            incorrectProofPenalty: 1 ether,
            maxMissedProofs: 5,
            slashingRate: 1000,
            stakingToken: address(token)
        });
        stake = StakeAccountingHarness(
            address(
                new ERC1967Proxy(
                    address(new StakeAccountingHarness()),
                    abi.encodeCall(StakeManager.initialize, (config, address(this)))
                )
            )
        );
        manager = ValidatorManager(
            address(
                new ERC1967Proxy(
                    address(new ValidatorManager()),
                    abi.encodeCall(
                        ValidatorManager.initialize,
                        (address(this), address(1), bytes32(uint256(1)))
                    )
                )
            )
        );
        bridge = Bridge(
            payable(
                address(
                    new ERC1967Proxy(
                        address(new Bridge()), abi.encodeCall(Bridge.initialize, (address(this)))
                    )
                )
            )
        );
        stake.updateValidatorManager(address(manager));
        manager.updateStakingManager(address(stake));
        token.mint(alice, 1000 ether);
        token.mint(address(this), 1000 ether);
        token.approve(address(stake), type(uint256).max);
    }

    function stakeAsAlice(uint256 amount) public {
        // Secret scalar one signs a G1 message as itself, with the standard G2 generator.
        uint256[4] memory publicKey = [
            uint256(10857046999023057135944570762232829481370756359578518086990519993285655852781),
            uint256(11559732032986387107991004021392285783925812861821192530917403151452391805634),
            uint256(8495653923123431417604973247489272438418190587263600148770280649306958101930),
            uint256(4082367875863433681332203403145435568316851327593401208105741076214120093531)
        ];
        vm.startPrank(alice);
        uint256[2] memory signature = stake.proofOfPossessionMessage(publicKey);
        token.approve(address(stake), amount);
        stake.stake(
            IStakeManagerTypes.StakeParams({
                stakeAmount: amount,
                stakeVersion: stake.getStakeVersion(config)
            }),
            IStakeManagerTypes.BlsOwnerShip({signature: signature, pubkey: publicKey})
        );
        vm.stopPrank();
    }

    function allocateRewards(uint256 epoch) public {
        IValidatorTypes.ValidatorInfo[] memory recipients = new IValidatorTypes.ValidatorInfo[](1);
        recipients[0] = manager.getValidator(alice);
        recipients[0].attestationCount = 100;
        uint256 duration = manager.epochDuration();
        vm.prank(address(manager));
        stake.distributeRewards(
            IStakeManagerTypes.RewardsParams({
                recipients: recipients,
                epoch: epoch,
                epochDuration: duration
            })
        );
    }

    function test_sweepCannotSpendPrincipalOrRewardFunding() public {
        this.stakeAsAlice(200 ether);
        stake.transferToken(address(token), 10 ether);
        vm.expectRevert(IStakeManagerTypes.NoAccessReserves.selector);
        stake.sweepExcess(address(token), 1 ether);
        assertTrue(token.transfer(address(stake), 2 ether));
        stake.sweepExcess(address(token), 2 ether);
        vm.expectRevert(IStakeManagerTypes.NoAccessReserves.selector);
        stake.sweepExcess(address(token), 1);
        assertEq(token.balanceOf(address(stake)), 210 ether);
    }

    function test_rewardAllocationFailsAtomicallyWithoutFunding() public {
        this.stakeAsAlice(200 ether);
        vm.expectRevert(IStakeManagerTypes.InsufficientTreasury.selector);
        this.allocateRewards(1);
        assertEq(stake.getLatestRewards(alice), 0);
        assertEq(stake.validatorBalance(alice).lastRewardEpoch, 0);
    }

    function test_fundedRewardsAreReservedAndPaidOnce() public {
        this.stakeAsAlice(200 ether);
        stake.transferToken(address(token), 2 ether);
        this.allocateRewards(1);
        uint256 rewards = stake.getLatestRewards(alice);
        (uint256 principal, uint256 reserves, uint256 accrued) = stake.accounting(address(token));
        assertEq(principal, 200 ether);
        assertEq(reserves, 2 ether);
        assertEq(accrued, rewards);
        vm.expectRevert(IStakeManagerTypes.InsufficientTreasury.selector);
        this.allocateRewards(2);
        vm.prank(alice);
        stake.claimRewards();
        (principal, reserves, accrued) = stake.accounting(address(token));
        assertEq(accrued, 0);
        assertEq(reserves, 2 ether - rewards);
        assertEq(token.balanceOf(address(stake)), principal + reserves);
    }

    function test_partialExitRestoresActiveStatus() public {
        this.stakeAsAlice(200 ether);
        vm.prank(alice);
        stake.beginUnstaking(IStakeManagerTypes.UnstakingParams({stakeAmount: 100 ether}));
        skip(2 days);
        vm.prank(alice);
        stake.completeUnstaking();
        assertEq(stake.validatorBalance(alice).stakeAmount, 100 ether);
        assertEq(
            uint256(manager.getValidator(alice).status),
            uint256(IValidatorTypes.ValidatorStatus.Active)
        );
        assertEq(stake.ownerOf(1), alice);
    }

    function testFuzz_exitPaysPrincipalAndRewards(
        bool slashBeforeExit,
        uint96 rewardFunding
    )
        public
    {
        uint256 funding = bound(uint256(rewardFunding), 2 ether, 100 ether);
        _stakeForExit(funding, slashBeforeExit);
    }

    function _stakeForExit(uint256 funding, bool slashBeforeExit) internal {
        this.stakeAsAlice(200 ether);
        stake.transferToken(address(token), funding);
        this.allocateRewards(1);
        uint256 rewards = stake.getLatestRewards(alice);
        uint256 remainingPrincipal = 200 ether;
        if (slashBeforeExit) {
            vm.prank(address(manager));
            stake.slashValidator(
                IStakeManagerTypes.SlashParams({validator: alice, slashAmount: 150 ether})
            );
            remainingPrincipal = 50 ether;
        }
        vm.prank(alice);
        stake.beginUnstaking(IStakeManagerTypes.UnstakingParams({stakeAmount: remainingPrincipal}));
        if (!slashBeforeExit) skip(2 days);
        uint256 beforeBalance = token.balanceOf(alice);
        vm.prank(alice);
        stake.completeUnstaking();
        assertEq(token.balanceOf(alice) - beforeBalance, remainingPrincipal + rewards);
        (uint256 principal, uint256 reserves, uint256 accrued) = stake.accounting(address(token));
        assertEq(principal, 0);
        assertEq(accrued, 0);
        assertEq(token.balanceOf(address(stake)), reserves);
        assertEq(stake.balanceOf(alice), 0);
    }

    function testFuzz_jailedTopUpRequiresMinimum(uint96 rawTopUp) public {
        this.stakeAsAlice(200 ether);
        vm.prank(address(manager));
        stake.slashValidator(
            IStakeManagerTypes.SlashParams({validator: alice, slashAmount: 150 ether})
        );
        uint256 topUp = bound(uint256(rawTopUp), 1, 100 ether);
        if (topUp < 50 ether) {
            vm.expectRevert(IStakeManagerTypes.MinStakeAmountRequired.selector);
            this.stakeAsAlice(topUp);
            assertEq(
                uint256(manager.getValidator(alice).status),
                uint256(IValidatorTypes.ValidatorStatus.Inactive)
            );
        } else {
            this.stakeAsAlice(topUp);
            assertEq(
                uint256(manager.getValidator(alice).status),
                uint256(IValidatorTypes.ValidatorStatus.Active)
            );
        }
    }

    function testFuzz_slashConservesTokenBacking(uint96 rawSlash) public {
        this.stakeAsAlice(200 ether);
        stake.transferToken(address(token), 10 ether);
        this.allocateRewards(1);
        uint256 originalRewards = stake.getLatestRewards(alice);
        uint256 slashAmount = bound(uint256(rawSlash), 1, 200 ether + originalRewards);
        vm.prank(address(manager));
        stake.slashValidator(
            IStakeManagerTypes.SlashParams({validator: alice, slashAmount: slashAmount})
        );
        IStakeManagerTypes.ValidatorBalance memory balance = stake.validatorBalance(alice);
        (uint256 principal, uint256 reserves, uint256 accrued) = stake.accounting(address(token));
        assertEq(balance.stakeAmount + balance.balance, 200 ether + originalRewards - slashAmount);
        assertEq(principal, balance.stakeAmount);
        assertEq(accrued, balance.balance);
        assertEq(reserves, 10 ether + 200 ether - principal);
        assertEq(token.balanceOf(address(stake)), principal + reserves);
    }

    function test_fullySlashedValidatorCanBurnItsReceipt() public {
        this.stakeAsAlice(200 ether);
        vm.prank(address(manager));
        stake.slashValidator(
            IStakeManagerTypes.SlashParams({validator: alice, slashAmount: 200 ether})
        );
        vm.prank(alice);
        stake.beginUnstaking(IStakeManagerTypes.UnstakingParams({stakeAmount: 0}));
        vm.prank(alice);
        stake.completeUnstaking();
        assertEq(stake.balanceOf(alice), 0);
        assertEq(stake.validatorBalance(alice).tokenId, 0);
    }

    function test_feeTokenCannotInflateStake() public {
        token.setFee(true);
        vm.expectRevert(IStakeManagerTypes.TransferFailed.selector);
        this.stakeAsAlice(200 ether);
        assertEq(token.balanceOf(address(stake)), 0);
    }

    function test_bridgeRejectsFeeTokenAndAttachedEther() public {
        token.setFee(true);
        vm.startPrank(alice);
        token.approve(address(bridge), 200 ether);
        IBridgeTypes.DepositParams memory params = IBridgeTypes.DepositParams({
            amount: 200 ether,
            token: address(token),
            to: alice,
            destinationChain: block.chainid + 1
        });
        vm.expectRevert(IBridgeTypes.InvalidTransaction.selector);
        bridge.deposit(params);
        token.setFee(false);
        vm.deal(alice, 1 ether);
        vm.expectRevert(IBridgeTypes.InvalidTransaction.selector);
        bridge.deposit{value: 1 ether}(params);
        vm.stopPrank();
        assertEq(bridge.DEPOSIT_COUNTER(), 0);
        assertEq(token.balanceOf(address(bridge)), 0);
        assertEq(address(bridge).balance, 0);
    }

    function testFuzz_claimLeafCommitsEveryField(IBridgeTypes.ClaimLeaf memory leaf) public pure {
        assertEq(LocalExitTreeLib.computeExitLeaf(leaf), keccak256(abi.encode(leaf)));
    }
}
