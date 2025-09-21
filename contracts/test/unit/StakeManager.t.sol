// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../base/StakeManagerBase.t.sol";

contract StakeManagerTest is StakeManagerBaseTest {
    function test_blsTestDataIsValid() public view {
        assertTrue(blsTestData.length >= 2, "Need at least 2 BLS test cases");

        BlsTestData memory aliceData = validatorBlsData[alice];
        assertTrue(bytes(aliceData.walletAddress).length > 0, "Alice BLS data not found");

        uint256[4] memory pubkey = [
            vm.parseUint(aliceData.publicKey[0]),
            vm.parseUint(aliceData.publicKey[1]),
            vm.parseUint(aliceData.publicKey[2]),
            vm.parseUint(aliceData.publicKey[3])
        ];

        uint256[2] memory signature = [
            vm.parseUint(aliceData.proofOfPossession[0]),
            vm.parseUint(aliceData.proofOfPossession[1])
        ];

        uint256[2] memory messageHash =
            [vm.parseUint(aliceData.messageHash[0]), vm.parseUint(aliceData.messageHash[1])];

        (bool pairingSuccess, bool callSuccess) = BLS.verifySingle(signature, pubkey, messageHash);
        assertTrue(pairingSuccess && callSuccess, "BLS signature verification failed for Alice");
    }

    function test_initializeSetsCorrectValues() public {
        vm.selectFork(FORKA_ID);
        _prankOwnerOnChain(FORKA_ID);

        assertEq(stakeManagerA.NAME(), "StakeManager");
        assertEq(stakeManagerA.VERSION(), "1");
        assertEq(stakeManagerA.VALIDATOR_MANAGER(), address(validatorManagerA));
        assertEq(stakeManagerA.EARLY_BONUS_EPOCHS(), 12960);
        // 8000=80%
        assertEq(stakeManagerA.MIN_PERFORMANCE_THRESHOLD(), 8000);
        assertEq(stakeManagerA.EARLY_BONUS_AMOUNT(), 1e18);
    }

    function test_stakeSuccessWithValidBlsProof() public {
        _stakeAsUser(alice, 200 ether, FORKA_ID);
    }

    function test_stakeMintsNft() public {
        _stakeAsUser(alice, 200 ether, FORKA_ID);
        assertEq(stakeManagerA.balanceOf(alice), 1);
        assertEq(stakeManagerA.ownerOf(1), alice);
    }

    function test_stakeRevertsWhenPaused() public {
        _prankOwnerOnChain(FORKA_ID);
        stakeManagerA.pause();
        vm.stopPrank();

        BlsTestData memory data = validatorBlsData[alice];
        vm.startPrank(alice);
        vm.selectFork(FORKA_ID);
        TOKEN_CHAINA.approve(address(stakeManagerA), 200 ether);

        uint256[4] memory pubkey = [
            vm.parseUint(data.publicKey[0]),
            vm.parseUint(data.publicKey[1]),
            vm.parseUint(data.publicKey[2]),
            vm.parseUint(data.publicKey[3])
        ];
        uint256[2] memory signature =
            [vm.parseUint(data.proofOfPossession[0]), vm.parseUint(data.proofOfPossession[1])];

        StakeParams memory params =
            StakeParams({stakeAmount: 200 ether, stakeVersion: testConfigVersionA});
        BlsOwnerShip memory proof = BlsOwnerShip({signature: signature, pubkey: pubkey});

        vm.expectRevert();
        stakeManagerA.stake(params, proof);
        vm.stopPrank();
    }

    function test_stakeRevertsInvalidStakeVersion() public {
        BlsTestData memory data = validatorBlsData[alice];
        vm.startPrank(alice);
        vm.selectFork(FORKA_ID);
        TOKEN_CHAINA.approve(address(stakeManagerA), 200 ether);

        uint256[4] memory pubkey = [
            vm.parseUint(data.publicKey[0]),
            vm.parseUint(data.publicKey[1]),
            vm.parseUint(data.publicKey[2]),
            vm.parseUint(data.publicKey[3])
        ];
        uint256[2] memory signature =
            [vm.parseUint(data.proofOfPossession[0]), vm.parseUint(data.proofOfPossession[1])];

        StakeParams memory params =
            StakeParams({stakeAmount: 200 ether, stakeVersion: keccak256("invalid")});
        BlsOwnerShip memory proof = BlsOwnerShip({signature: signature, pubkey: pubkey});

        vm.expectRevert(InvalidStakeVersion.selector);
        stakeManagerA.stake(params, proof);
        vm.stopPrank();
    }

    function test_stakeRevertsInsufficientAmount() public {
        BlsTestData memory data = validatorBlsData[alice];
        vm.selectFork(FORKA_ID);
        vm.startPrank(alice);
        TOKEN_CHAINA.approve(address(stakeManagerA), 50 ether);

        uint256[4] memory pubkey = [
            vm.parseUint(data.publicKey[0]),
            vm.parseUint(data.publicKey[1]),
            vm.parseUint(data.publicKey[2]),
            vm.parseUint(data.publicKey[3])
        ];
        uint256[2] memory signature =
            [vm.parseUint(data.proofOfPossession[0]), vm.parseUint(data.proofOfPossession[1])];

        StakeParams memory params =
            StakeParams({stakeAmount: 50 ether, stakeVersion: testConfigVersionA});
        BlsOwnerShip memory proof = BlsOwnerShip({signature: signature, pubkey: pubkey});

        vm.expectRevert(MinStakeAmountRequired.selector);
        stakeManagerA.stake(params, proof);
        vm.stopPrank();
    }

    function test_stakeRevertsInsufficientAllowance() public {
        BlsTestData memory data = validatorBlsData[alice];
        vm.selectFork(FORKA_ID);
        vm.startPrank(alice);
        TOKEN_CHAINA.approve(address(stakeManagerA), 100 ether);

        uint256[4] memory pubkey = [
            vm.parseUint(data.publicKey[0]),
            vm.parseUint(data.publicKey[1]),
            vm.parseUint(data.publicKey[2]),
            vm.parseUint(data.publicKey[3])
        ];
        uint256[2] memory signature =
            [vm.parseUint(data.proofOfPossession[0]), vm.parseUint(data.proofOfPossession[1])];

        StakeParams memory params =
            StakeParams({stakeAmount: 200 ether, stakeVersion: testConfigVersionA});
        BlsOwnerShip memory proof = BlsOwnerShip({signature: signature, pubkey: pubkey});

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector,
                address(stakeManagerA),
                100 ether,
                200 ether
            )
        );
        stakeManagerA.stake(params, proof);
        vm.stopPrank();
    }

    function test_stakeIncreasesExistingStake() public {
        _stakeAsUser(alice, 200 ether, FORKA_ID);
        ValidatorBalance memory beforeB = stakeManagerA.validatorBalance(alice);

        BlsTestData memory data = validatorBlsData[alice];
        vm.startPrank(alice);
        TOKEN_CHAINA.approve(address(stakeManagerA), 100 ether);
        uint256[4] memory pubkey = [
            vm.parseUint(data.publicKey[0]),
            vm.parseUint(data.publicKey[1]),
            vm.parseUint(data.publicKey[2]),
            vm.parseUint(data.publicKey[3])
        ];
        uint256[2] memory signature =
            [vm.parseUint(data.proofOfPossession[0]), vm.parseUint(data.proofOfPossession[1])];

        StakeParams memory params =
            StakeParams({stakeAmount: 100 ether, stakeVersion: testConfigVersionA});
        BlsOwnerShip memory proof = BlsOwnerShip({signature: signature, pubkey: pubkey});
        stakeManagerA.stake(params, proof);

        ValidatorBalance memory afterB = stakeManagerA.validatorBalance(alice);
        assertEq(stakeManagerA.balanceOf(alice), 1);
        assertEq(afterB.stakeAmount, beforeB.stakeAmount + params.stakeAmount);
        vm.stopPrank();
    }

    function test_beginUnstakingSetsExitTimestamp() public {
        _stakeAsUser(alice, 200 ether, FORKA_ID);
        skip(1 days);
        UnstakingParams memory params = UnstakingParams({stakeAmount: 100 ether});
        vm.prank(alice);
        stakeManagerA.beginUnstaking(params);
        ValidatorBalance memory bal = stakeManagerA.validatorBalance(alice);
        assertEq(bal.stakeExitTimestamp, block.timestamp + testConfigA.minUnstakeDelay);
    }

    function test_beginUnstakingRevertsAlreadyUnstaking() public {
        _stakeAsUser(alice, 200 ether, FORKA_ID);
        _beginUnstakingAsValidator(alice, 100 ether, FORKA_ID);

        skip(1 days);
        UnstakingParams memory params = UnstakingParams({stakeAmount: 100 ether});

        vm.prank(alice);
        vm.expectRevert(NotAllowed.selector);
        stakeManagerA.beginUnstaking(params);
    }

    function test_completeUnstakingTransfersTokens() public {
        _stakeAsUser(alice, 200 ether, FORKA_ID);
        _beginUnstakingAsValidator(alice, 100 ether, FORKA_ID);

        skip(10 days);
        uint256 beforeBal = TOKEN_CHAINA.balanceOf(alice);

        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit ValidatorExit(alice, testConfigVersionA, 0, true);
        stakeManagerA.completeUnstaking();

        uint256 afterBal = TOKEN_CHAINA.balanceOf(alice);
        assertEq(afterBal - beforeBal, 100 ether);
    }

    function test_completeUnstakingBurnsNft() public {
        _stakeAsUser(alice, 200 ether, FORKA_ID);
        _beginUnstakingAsValidator(alice, 200 ether, FORKA_ID);

        skip(10 days);
        uint256 beforeBal = TOKEN_CHAINA.balanceOf(alice);

        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit ValidatorExit(alice, testConfigVersionA, 0, false);
        stakeManagerA.completeUnstaking();

        uint256 afterBal = TOKEN_CHAINA.balanceOf(alice);
        assertEq(afterBal - beforeBal, 200 ether);
        assertEq(stakeManagerA.balanceOf(alice), 0);
    }

    function test_completeUnstakingRevertsBeforeDelay() public {
        _stakeAsUser(alice, 200 ether, FORKA_ID);
        _beginUnstakingAsValidator(alice, 200 ether, FORKA_ID);
        skip(1 days);

        vm.prank(alice);
        vm.expectRevert(NotAllowed.selector);
        stakeManagerA.completeUnstaking();
    }

    function test_slashReducesStake() public {
        _stakeAsUser(alice, 200 ether, FORKA_ID);
        SlashParams memory params = SlashParams({validator: alice, slashAmount: 50 ether});
        vm.prank(address(validatorManagerA));
        emit ValidatorSlashed(alice, 50 ether, 200 ether, 150 ether, block.timestamp);
        stakeManagerA.slashValidator(params);
    }

    function test_slashRevertsZeroAmount() public {
        _stakeAsUser(alice, 200 ether, FORKA_ID);
        SlashParams memory params = SlashParams({validator: alice, slashAmount: 0});
        vm.prank(address(validatorManagerA));
        vm.expectRevert(ZeroSlashAmount.selector);
        stakeManagerA.slashValidator(params);
    }

    function test_slashRevertsInsufficientStake() public {
        _stakeAsUser(alice, 200 ether, FORKA_ID);
        SlashParams memory params = SlashParams({validator: alice, slashAmount: 300 ether});
        vm.prank(address(validatorManagerA));
        vm.expectRevert(InsufficientStakeToSlash.selector);
        stakeManagerA.slashValidator(params);
    }

    function test_slashJailedIfLeavesBelowMinStake() public {
        _stakeAsUser(alice, 200 ether, FORKA_ID);
        uint256 slashAmt = testConfigA.minStakeAmount - 1;
        vm.prank(address(validatorManagerA));
        stakeManagerA.slashValidator(
            SlashParams({validator: alice, slashAmount: 200 ether - slashAmt})
        );

        IValidatorTypes.ValidatorInfo memory info = validatorManagerA.getValidator(alice);
        // We cant use asserts here so we do it the good ol way :XD
        require(info.status == IValidatorTypes.ValidatorStatus.Inactive, "Not Jailed");
    }

    function test_distributeRewardsAllocates() public {
        _stakeAsUser(alice, 200 ether, FORKA_ID);
        _stakeAsUser(bob, 200 ether, FORKA_ID);

        BlsTestData memory a = validatorBlsData[alice];
        BlsTestData memory b = validatorBlsData[bob];
        IValidatorTypes.ValidatorInfo[] memory validators = new IValidatorTypes.ValidatorInfo[](2);

        validators[0] = IValidatorTypes.ValidatorInfo({
            blsPublicKey: [
                vm.parseUint(a.publicKey[0]),
                vm.parseUint(a.publicKey[1]),
                vm.parseUint(a.publicKey[2]),
                vm.parseUint(a.publicKey[3])
            ],
            wallet: alice,
            status: IValidatorTypes.ValidatorStatus.Active,
            attestationCount: 100,
            invalidAttestations: 10
        });
        validators[1] = IValidatorTypes.ValidatorInfo({
            blsPublicKey: [
                vm.parseUint(b.publicKey[0]),
                vm.parseUint(b.publicKey[1]),
                vm.parseUint(b.publicKey[2]),
                vm.parseUint(b.publicKey[3])
            ],
            wallet: bob,
            status: IValidatorTypes.ValidatorStatus.Active,
            attestationCount: 150,
            invalidAttestations: 5
        });

        RewardsParams memory params =
            RewardsParams({recipients: validators, epoch: 1, epochDuration: 600});
        vm.prank(address(validatorManagerA));
        stakeManagerA.distributeRewards(params);

        assertTrue(stakeManagerA.getLatestRewards(alice) > 0);
        assertTrue(stakeManagerA.getLatestRewards(bob) > 0);
    }

    function test_distributeRewardsRevertsNoEligibleValidators() public {
        _stakeAsUser(alice, 200 ether, FORKA_ID);
        _stakeAsUser(bob, 200 ether, FORKA_ID);

        BlsTestData memory a = validatorBlsData[alice];
        BlsTestData memory b = validatorBlsData[bob];
        IValidatorTypes.ValidatorInfo[] memory validators = new IValidatorTypes.ValidatorInfo[](2);
        validators[0] = IValidatorTypes.ValidatorInfo({
            blsPublicKey: [
                vm.parseUint(a.publicKey[0]),
                vm.parseUint(a.publicKey[1]),
                vm.parseUint(a.publicKey[2]),
                vm.parseUint(a.publicKey[3])
            ],
            wallet: alice,
            status: IValidatorTypes.ValidatorStatus.Active,
            attestationCount: 10,
            invalidAttestations: 10
        });
        validators[1] = IValidatorTypes.ValidatorInfo({
            blsPublicKey: [
                vm.parseUint(b.publicKey[0]),
                vm.parseUint(b.publicKey[1]),
                vm.parseUint(b.publicKey[2]),
                vm.parseUint(b.publicKey[3])
            ],
            wallet: bob,
            status: IValidatorTypes.ValidatorStatus.Active,
            attestationCount: 5,
            invalidAttestations: 5
        });

        RewardsParams memory params =
            RewardsParams({recipients: validators, epoch: 1, epochDuration: 600});
        vm.prank(address(validatorManagerA));
        vm.expectRevert(NoEligibleValidators.selector);
        stakeManagerA.distributeRewards(params);
    }

    function test_distributeRewardsRevertsOnEpochDurationMismatch() public {
        _stakeAsUser(alice, 200 ether, FORKA_ID);

        BlsTestData memory a = validatorBlsData[alice];
        IValidatorTypes.ValidatorInfo;
        IValidatorTypes.ValidatorInfo;
        IValidatorTypes.ValidatorInfo[] memory validators = new IValidatorTypes.ValidatorInfo[](1);
        validators[0] = IValidatorTypes.ValidatorInfo({
            blsPublicKey: [
                vm.parseUint(a.publicKey[0]),
                vm.parseUint(a.publicKey[1]),
                vm.parseUint(a.publicKey[2]),
                vm.parseUint(a.publicKey[3])
            ],
            wallet: alice,
            status: IValidatorTypes.ValidatorStatus.Active,
            attestationCount: 10,
            invalidAttestations: 0
        });

        RewardsParams memory params =
            RewardsParams({recipients: validators, epoch: 1, epochDuration: 601});
        vm.prank(address(validatorManagerA));
        vm.expectRevert(EpochDurationMisMatch.selector);
        stakeManagerA.distributeRewards(params);
    }

    function test_distributeRewardsSecondCallSameEpochReverts() public {
        _stakeAsUser(alice, 200 ether, FORKA_ID);

        BlsTestData memory a = validatorBlsData[alice];
        IValidatorTypes.ValidatorInfo[] memory validators = new IValidatorTypes.ValidatorInfo[](1);

        validators[0] = IValidatorTypes.ValidatorInfo({
            blsPublicKey: [
                vm.parseUint(a.publicKey[0]),
                vm.parseUint(a.publicKey[1]),
                vm.parseUint(a.publicKey[2]),
                vm.parseUint(a.publicKey[3])
            ],
            wallet: alice,
            status: IValidatorTypes.ValidatorStatus.Active,
            attestationCount: 10,
            invalidAttestations: 0
        });

        RewardsParams memory p =
            RewardsParams({recipients: validators, epoch: 1, epochDuration: 600});
        vm.prank(address(validatorManagerA));
        stakeManagerA.distributeRewards(p);

        vm.prank(address(validatorManagerA));
        vm.expectRevert(NoEligibleValidators.selector);
        stakeManagerA.distributeRewards(p);
    }

    function test_claimRewardsTransfers() public {
        _stakeAsUser(alice, 200 ether, FORKA_ID);
        _distributeRewardsToValidator(alice, FORKA_ID, 1);

        uint256 beforeBal = TOKEN_CHAINA.balanceOf(alice);
        uint256 rewardAmount = stakeManagerA.getLatestRewards(alice);
        _topupRewards(FORKA_ID, 100 ether, address(TOKEN_CHAINA));
        vm.stopPrank();
        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit ValidatorRewardsClaimed(alice, rewardAmount, block.timestamp);
        stakeManagerA.claimRewards();

        uint256 afterBal = TOKEN_CHAINA.balanceOf(alice);
        assertEq(afterBal - beforeBal, rewardAmount);
        assertEq(stakeManagerA.getLatestRewards(alice), 0);
    }

    function test_claimRewardsRevertsWhenEmpty() public {
        _stakeAsUser(alice, 200 ether, FORKA_ID);
        vm.prank(alice);
        vm.expectRevert(NoRewardsToClaim.selector);
        stakeManagerA.claimRewards();
    }

    function test_upgradeStakeConfigUpdates() public {
        StakeManagerConfig memory newConfig = StakeManagerConfig({
            minStakeAmount: 150 ether,
            minWithdrawAmount: 15 ether,
            minUnstakeDelay: 10 days,
            correctProofReward: 1.5 ether,
            incorrectProofPenalty: 3 ether,
            maxMissedProofs: 3,
            slashingRate: 1500,
            stakingToken: address(TOKEN_CHAINA)
        });

        vm.expectEmit(true, true, true, true);
        emit StakeManagerConfigUpdated(testConfigA, newConfig);

        _prankOwnerOnChain(FORKA_ID);
        stakeManagerA.upgradeStakeConfig(newConfig);
    }

    function test_upgradeStakeConfigAndStakeRevert() public {
        _stakeAsUser(alice, 200 ether, FORKA_ID);

        StakeManagerConfig memory newConfig = StakeManagerConfig({
            minStakeAmount: 150 ether,
            minWithdrawAmount: 15 ether,
            minUnstakeDelay: 10 days,
            correctProofReward: 1.5 ether,
            incorrectProofPenalty: 3 ether,
            maxMissedProofs: 3,
            slashingRate: 1500,
            stakingToken: address(TOKEN_CHAINA)
        });

        vm.expectEmit(true, true, true, true);
        emit StakeManagerConfigUpdated(testConfigA, newConfig);

        _prankOwnerOnChain(FORKA_ID);
        stakeManagerA.upgradeStakeConfig(newConfig);
        testConfigVersionA = stakeManagerA.getStakeVersion(newConfig);
        BlsTestData memory data = validatorBlsData[alice];
        vm.startPrank(alice);
        TOKEN_CHAINA.approve(address(stakeManagerA), 200 ether);

        uint256[4] memory pubkey = [
            vm.parseUint(data.publicKey[0]),
            vm.parseUint(data.publicKey[1]),
            vm.parseUint(data.publicKey[2]),
            vm.parseUint(data.publicKey[3])
        ];

        uint256[2] memory signature =
            [vm.parseUint(data.proofOfPossession[0]), vm.parseUint(data.proofOfPossession[1])];
        StakeParams memory params =
            StakeParams({stakeAmount: 200 ether, stakeVersion: testConfigVersionA});
        BlsOwnerShip memory proof = BlsOwnerShip({signature: signature, pubkey: pubkey});
        vm.expectRevert(MigrateToNewVersion.selector);
        stakeManagerA.stake(params, proof);
    }

    function test_pauseStopsStaking() public {
        _prankOwnerOnChain(FORKA_ID);
        stakeManagerA.pause();

        BlsTestData memory data = validatorBlsData[alice];

        vm.startPrank(spha);
        TOKEN_CHAINA.approve(address(stakeManagerA), 200 ether);

        uint256[4] memory pubkey = [
            vm.parseUint(data.publicKey[0]),
            vm.parseUint(data.publicKey[1]),
            vm.parseUint(data.publicKey[2]),
            vm.parseUint(data.publicKey[3])
        ];
        uint256[2] memory signature =
            [vm.parseUint(data.proofOfPossession[0]), vm.parseUint(data.proofOfPossession[1])];

        StakeParams memory params =
            StakeParams({stakeAmount: 200 ether, stakeVersion: testConfigVersionA});
        BlsOwnerShip memory proof = BlsOwnerShip({signature: signature, pubkey: pubkey});

        vm.expectRevert();
        stakeManagerA.stake(params, proof);
        vm.stopPrank();
    }

    function test_stakeVersionHashDiffersForDifferentConfigs() public {
        StakeManagerConfig memory config2 = testConfigA;
        config2.minStakeAmount = 150 ether;
        vm.selectFork(FORKA_ID);
        bytes32 v1 = stakeManagerA.getStakeVersion(testConfigA);
        bytes32 v2 = stakeManagerA.getStakeVersion(config2);
        assertTrue(v1 != v2);
    }

    function test_proofOfPossessionMessageStable() public {
        BlsTestData memory data = validatorBlsData[alice];
        vm.selectFork(FORKA_ID);
        uint256[4] memory pubkey = [
            vm.parseUint(data.publicKey[0]),
            vm.parseUint(data.publicKey[1]),
            vm.parseUint(data.publicKey[2]),
            vm.parseUint(data.publicKey[3])
        ];

        uint256[2] memory hash1 = stakeManagerA.proofOfPossessionMessage(pubkey);
        uint256[2] memory hash2 = stakeManagerA.proofOfPossessionMessage(pubkey);
        assertEq(hash1[0], hash2[0]);
        assertEq(hash1[1], hash2[1]);
    }

    function test_beginUnstakingRevertsBelowMinWithdraw() public {
        _stakeAsUser(alice, 200 ether, FORKA_ID);
        skip(1 days);

        uint256 below = testConfigA.minWithdrawAmount - 1;
        UnstakingParams memory p = UnstakingParams({stakeAmount: below});

        vm.prank(alice);
        vm.expectRevert(MinStakeAmountRequired.selector);
        stakeManagerA.beginUnstaking(p);
    }

    function test_beginUnstakingRevertsLeavingBelowMinStake() public {
        _stakeAsUser(alice, 200 ether, FORKA_ID);
        skip(1 days);

        uint256 leave = testConfigA.minStakeAmount - 1;
        uint256 unstakeAmt = 200 ether - leave;

        UnstakingParams memory p = UnstakingParams({stakeAmount: unstakeAmt});

        vm.prank(alice);
        vm.expectRevert(BelowMinimumStake.selector);
        stakeManagerA.beginUnstaking(p);
    }

    function test_nftTransfersAndApprovalsRevert() public {
        _stakeAsUser(alice, 200 ether, FORKA_ID);

        vm.expectRevert(NotAllowed.selector);
        stakeManagerA.approve(address(this), 1);

        vm.expectRevert(NotAllowed.selector);
        stakeManagerA.transferFrom(alice, address(this), 1);

        vm.expectRevert(NotAllowed.selector);
        stakeManagerA.safeTransferFrom(alice, address(this), 1, "");

        vm.expectRevert(NotAllowed.selector);
        stakeManagerA.setApprovalForAll(address(this), true);
    }

    function test_stakeRevertsInvalidPublicKey() public {
        vm.selectFork(FORKA_ID);
        vm.startPrank(alice);
        TOKEN_CHAINA.approve(address(stakeManagerA), 200 ether);

        uint256[4] memory badPk = [uint256(0), uint256(0), uint256(0), uint256(0)];
        uint256[2] memory sig = [uint256(1), uint256(1)];

        StakeParams memory params =
            StakeParams({stakeAmount: 200 ether, stakeVersion: testConfigVersionA});
        BlsOwnerShip memory proof = BlsOwnerShip({signature: sig, pubkey: badPk});

        vm.expectRevert(InvalidPublicKey.selector);
        stakeManagerA.stake(params, proof);
        vm.stopPrank();
    }

    function test_distributeRewardsRevertsZeroEligibleValidators() public {
        _stakeAsUser(alice, 200 ether, FORKA_ID);

        BlsTestData memory a = validatorBlsData[alice];
        IValidatorTypes.ValidatorInfo[] memory validators = new IValidatorTypes.ValidatorInfo[](1);
        validators[0] = IValidatorTypes.ValidatorInfo({
            blsPublicKey: [
                vm.parseUint(a.publicKey[0]),
                vm.parseUint(a.publicKey[1]),
                vm.parseUint(a.publicKey[2]),
                vm.parseUint(a.publicKey[3])
            ],
            wallet: alice,
            status: IValidatorTypes.ValidatorStatus.Active,
            attestationCount: 10,
            invalidAttestations: 10
        });

        RewardsParams memory params =
            RewardsParams({recipients: validators, epoch: 1, epochDuration: 600});

        vm.prank(address(validatorManagerA));
        vm.expectRevert(NoEligibleValidators.selector);
        stakeManagerA.distributeRewards(params);
    }

    function test_distributeRewardsRevertsDoubleClaimSameEpoch() public {
        _stakeAsUser(alice, 200 ether, FORKA_ID);
        _distributeRewardsToValidator(alice, FORKA_ID, 1);

        BlsTestData memory a = validatorBlsData[alice];
        IValidatorTypes.ValidatorInfo[] memory validators = new IValidatorTypes.ValidatorInfo[](1);
        validators[0] = IValidatorTypes.ValidatorInfo({
            blsPublicKey: [
                vm.parseUint(a.publicKey[0]),
                vm.parseUint(a.publicKey[1]),
                vm.parseUint(a.publicKey[2]),
                vm.parseUint(a.publicKey[3])
            ],
            wallet: alice,
            status: IValidatorTypes.ValidatorStatus.Active,
            attestationCount: 100,
            invalidAttestations: 10
        });

        RewardsParams memory params =
            RewardsParams({recipients: validators, epoch: 1, epochDuration: 600});

        vm.prank(address(validatorManagerA));
        vm.expectRevert(NoEligibleValidators.selector);
        stakeManagerA.distributeRewards(params);
    }

    function test_slashValidatorRevertsExceedingTotalBalance() public {
        _stakeAsUser(alice, 200 ether, FORKA_ID);
        _distributeRewardsToValidator(alice, FORKA_ID, 1);

        ValidatorBalance memory before = stakeManagerA.validatorBalance(alice);
        uint256 totalBalance = before.stakeAmount + before.balance;

        SlashParams memory params =
            SlashParams({validator: alice, slashAmount: totalBalance + 1 ether});

        vm.prank(address(validatorManagerA));
        vm.expectRevert(InsufficientStakeToSlash.selector);
        stakeManagerA.slashValidator(params);
    }

    function test_stakeRevertsBlsSignatureReuse() public {
        BlsTestData memory aliceData = validatorBlsData[alice];
        _stakeAsUser(alice, 200 ether, FORKA_ID);

        vm.startPrank(bob);
        TOKEN_CHAINA.approve(address(stakeManagerA), 200 ether);

        uint256[4] memory pubkey = [
            vm.parseUint(aliceData.publicKey[0]),
            vm.parseUint(aliceData.publicKey[1]),
            vm.parseUint(aliceData.publicKey[2]),
            vm.parseUint(aliceData.publicKey[3])
        ];
        uint256[2] memory signature = [
            vm.parseUint(aliceData.proofOfPossession[0]),
            vm.parseUint(aliceData.proofOfPossession[1])
        ];

        StakeParams memory params =
            StakeParams({stakeAmount: 200 ether, stakeVersion: testConfigVersionA});
        BlsOwnerShip memory proof = BlsOwnerShip({signature: signature, pubkey: pubkey});

        vm.expectRevert(NotOwnerBLS.selector);
        stakeManagerA.stake(params, proof);
        vm.stopPrank();
    }

    function test_sweepExcessRevertsAccessingReserves() public {
        _stakeAsUser(alice, 200 ether, FORKA_ID);

        _prankOwnerOnChain(FORKA_ID);
        TOKEN_CHAINA.transfer(address(stakeManagerA), 100 ether);
        stakeManagerA.transferToken(address(TOKEN_CHAINA), 110 ether);

        uint256 contractBalance = TOKEN_CHAINA.balanceOf(address(stakeManagerA));
        console.log("contractBalance");
        console.logUint(contractBalance);
        vm.expectRevert(NoAccessReserves.selector);
        stakeManagerA.sweepExcess(address(TOKEN_CHAINA), DEFAULT_REWARD_BALANCE + contractBalance);
        vm.stopPrank();
    }

    function test_slashValidatorJailsBelowMinimumStake() public {
        _stakeAsUser(alice, 200 ether, FORKA_ID);

        uint256 slashAmount = 200 ether - testConfigA.minStakeAmount + 1;
        SlashParams memory params = SlashParams({validator: alice, slashAmount: slashAmount});

        vm.prank(address(validatorManagerA));
        stakeManagerA.slashValidator(params);

        IValidatorTypes.ValidatorInfo memory info = validatorManagerA.getValidator(alice);
        assertEq(uint256(info.status), uint256(IValidatorTypes.ValidatorStatus.Inactive));

        ValidatorBalance memory balance = stakeManagerA.validatorBalance(alice);
        assertTrue(balance.stakeAmount < testConfigA.minStakeAmount);
    }

    function test_claimRewardsRevertsAfterValidatorDeletion() public {
        _stakeAsUser(alice, 200 ether, FORKA_ID);
        _distributeRewardsToValidator(alice, FORKA_ID, 1);

        _beginUnstakingAsValidator(alice, 200 ether, FORKA_ID);
        skip(10 days);
        vm.prank(alice);
        stakeManagerA.completeUnstaking();

        vm.prank(alice);
        vm.expectRevert(NoRewardsToClaim.selector);
        stakeManagerA.claimRewards();
    }

    function test_slashValidatorHandlesSequentialSlashes() public {
        _stakeAsUser(alice, 200 ether, FORKA_ID);
        _distributeRewardsToValidator(alice, FORKA_ID, 1);

        ValidatorBalance memory before = stakeManagerA.validatorBalance(alice);
        uint256 totalBalance = before.stakeAmount + before.balance;

        SlashParams memory params1 = SlashParams({validator: alice, slashAmount: totalBalance / 2});
        vm.prank(address(validatorManagerA));
        stakeManagerA.slashValidator(params1);

        SlashParams memory params2 = SlashParams({validator: alice, slashAmount: totalBalance});
        vm.prank(address(validatorManagerA));
        vm.expectRevert(InsufficientStakeToSlash.selector);
        stakeManagerA.slashValidator(params2);
    }

    function test_jailedValidatorCanTopUpAndReactivate() public {
        _stakeAsUser(alice, 200 ether, FORKA_ID);

        uint256 slashAmount = 200 ether - testConfigA.minStakeAmount + 1;
        SlashParams memory slashParams = SlashParams({validator: alice, slashAmount: slashAmount});

        vm.prank(address(validatorManagerA));
        stakeManagerA.slashValidator(slashParams);

        IValidatorTypes.ValidatorInfo memory info = validatorManagerA.getValidator(alice);
        assertEq(uint256(info.status), uint256(IValidatorTypes.ValidatorStatus.Inactive));

        BlsTestData memory data = validatorBlsData[alice];
        vm.startPrank(alice);
        TOKEN_CHAINA.approve(address(stakeManagerA), 200 ether);

        uint256[4] memory pubkey = [
            vm.parseUint(data.publicKey[0]),
            vm.parseUint(data.publicKey[1]),
            vm.parseUint(data.publicKey[2]),
            vm.parseUint(data.publicKey[3])
        ];
        uint256[2] memory signature =
            [vm.parseUint(data.proofOfPossession[0]), vm.parseUint(data.proofOfPossession[1])];

        StakeParams memory params =
            StakeParams({stakeAmount: 200 ether, stakeVersion: testConfigVersionA});
        BlsOwnerShip memory proof = BlsOwnerShip({signature: signature, pubkey: pubkey});

        stakeManagerA.stake(params, proof);
        vm.stopPrank();

        IValidatorTypes.ValidatorInfo memory afterInfo = validatorManagerA.getValidator(alice);
        assertEq(uint256(afterInfo.status), uint256(IValidatorTypes.ValidatorStatus.Active));

        ValidatorBalance memory balance = stakeManagerA.validatorBalance(alice);
        assertTrue(balance.stakeAmount >= testConfigA.minStakeAmount);
    }

    function test_jailedValidatorDoesNotReceiveRewards() public {
        _stakeAsUser(alice, 200 ether, FORKA_ID);
        _stakeAsUser(bob, 200 ether, FORKA_ID);

        uint256 slashAmount = 200 ether - testConfigA.minStakeAmount + 1;
        SlashParams memory slashParams = SlashParams({validator: alice, slashAmount: slashAmount});

        vm.prank(address(validatorManagerA));
        stakeManagerA.slashValidator(slashParams);

        BlsTestData memory a = validatorBlsData[alice];
        BlsTestData memory b = validatorBlsData[bob];
        IValidatorTypes.ValidatorInfo[] memory validators = new IValidatorTypes.ValidatorInfo[](2);

        validators[0] = IValidatorTypes.ValidatorInfo({
            blsPublicKey: [
                vm.parseUint(a.publicKey[0]),
                vm.parseUint(a.publicKey[1]),
                vm.parseUint(a.publicKey[2]),
                vm.parseUint(a.publicKey[3])
            ],
            wallet: alice,
            status: IValidatorTypes.ValidatorStatus.Inactive,
            attestationCount: 100,
            invalidAttestations: 10
        });
        validators[1] = IValidatorTypes.ValidatorInfo({
            blsPublicKey: [
                vm.parseUint(b.publicKey[0]),
                vm.parseUint(b.publicKey[1]),
                vm.parseUint(b.publicKey[2]),
                vm.parseUint(b.publicKey[3])
            ],
            wallet: bob,
            status: IValidatorTypes.ValidatorStatus.Active,
            attestationCount: 100,
            invalidAttestations: 10
        });

        RewardsParams memory params =
            RewardsParams({recipients: validators, epoch: 1, epochDuration: 600});

        vm.prank(address(validatorManagerA));
        stakeManagerA.distributeRewards(params);

        assertEq(stakeManagerA.getLatestRewards(alice), 0);
        assertTrue(stakeManagerA.getLatestRewards(bob) > 0);
    }

    function test_jailedValidatorCanExitImmediatelyWithoutDelay() public {
        _stakeAsUser(alice, 200 ether, FORKA_ID);

        uint256 slashAmount = 200 ether - testConfigA.minStakeAmount + 1;
        SlashParams memory slashParams = SlashParams({validator: alice, slashAmount: slashAmount});

        vm.prank(address(validatorManagerA));
        stakeManagerA.slashValidator(slashParams);

        ValidatorBalance memory beforeBalance = stakeManagerA.validatorBalance(alice);

        vm.prank(alice);
        stakeManagerA.beginUnstaking(UnstakingParams({stakeAmount: beforeBalance.stakeAmount}));

        ValidatorBalance memory afterBegin = stakeManagerA.validatorBalance(alice);
        assertEq(afterBegin.stakeAmount, 0);
        assertEq(afterBegin.unstakeAmount, beforeBalance.stakeAmount);

        uint256 beforeTokenBal = TOKEN_CHAINA.balanceOf(alice);
        skip(10 days);
        vm.prank(alice);
        stakeManagerA.completeUnstaking();

        uint256 afterTokenBal = TOKEN_CHAINA.balanceOf(alice);
        assertEq(afterTokenBal - beforeTokenBal, beforeBalance.stakeAmount);
    }

    function test_slashValidatorToExactlyMinimumStakeDoesNotJail() public {
        _stakeAsUser(alice, 200 ether, FORKA_ID);

        uint256 slashAmount = 200 ether - testConfigA.minStakeAmount;
        SlashParams memory params = SlashParams({validator: alice, slashAmount: slashAmount});

        vm.prank(address(validatorManagerA));
        stakeManagerA.slashValidator(params);

        ValidatorBalance memory balance = stakeManagerA.validatorBalance(alice);
        assertEq(balance.stakeAmount, testConfigA.minStakeAmount);

        IValidatorTypes.ValidatorInfo memory info = validatorManagerA.getValidator(alice);
        assertEq(uint256(info.status), uint256(IValidatorTypes.ValidatorStatus.Active));
    }

    function test_distributeRewardsSkipsValidatorsWithInsufficientStake() public {
        _stakeAsUser(alice, 200 ether, FORKA_ID);
        _stakeAsUser(bob, 200 ether, FORKA_ID);

        uint256 slashAmount = 200 ether - testConfigA.minStakeAmount + 1;
        SlashParams memory slashParams = SlashParams({validator: alice, slashAmount: slashAmount});

        vm.prank(address(validatorManagerA));
        stakeManagerA.slashValidator(slashParams);

        BlsTestData memory a = validatorBlsData[alice];
        BlsTestData memory b = validatorBlsData[bob];
        IValidatorTypes.ValidatorInfo[] memory validators = new IValidatorTypes.ValidatorInfo[](2);

        validators[0] = IValidatorTypes.ValidatorInfo({
            blsPublicKey: [
                vm.parseUint(a.publicKey[0]),
                vm.parseUint(a.publicKey[1]),
                vm.parseUint(a.publicKey[2]),
                vm.parseUint(a.publicKey[3])
            ],
            wallet: alice,
            status: IValidatorTypes.ValidatorStatus.Active,
            attestationCount: 100,
            invalidAttestations: 10
        });
        validators[1] = IValidatorTypes.ValidatorInfo({
            blsPublicKey: [
                vm.parseUint(b.publicKey[0]),
                vm.parseUint(b.publicKey[1]),
                vm.parseUint(b.publicKey[2]),
                vm.parseUint(b.publicKey[3])
            ],
            wallet: bob,
            status: IValidatorTypes.ValidatorStatus.Active,
            attestationCount: 100,
            invalidAttestations: 10
        });

        RewardsParams memory params =
            RewardsParams({recipients: validators, epoch: 1, epochDuration: 600});

        vm.prank(address(validatorManagerA));
        stakeManagerA.distributeRewards(params);

        assertEq(stakeManagerA.getLatestRewards(alice), 0);
        assertTrue(stakeManagerA.getLatestRewards(bob) > 0);
    }
}
