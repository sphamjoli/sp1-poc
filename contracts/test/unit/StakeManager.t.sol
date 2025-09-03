// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../base/StakeManagerBase.t.sol";

contract StakeManagerTest is StakeManagerBaseTest {
    function test_bls_test_data_is_valid() public view {
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

    function test_initialize_sets_correct_values() public {
        vm.selectFork(FORKA_ID);
        _prankOwnerOnChain(FORKA_ID);

        assertEq(stakeManagerA.NAME(), "StakeManager");
        assertEq(stakeManagerA.VERSION(), "1");
        assertEq(stakeManagerA.VALIDATOR_MANAGER(), address(validatorManagerA));
        assertEq(stakeManagerA.EARLY_BONUS_EPOCHS(), 12960);
        assertEq(stakeManagerA.MIN_PERFORMANCE_THRESHOLD(), 80);
        assertEq(stakeManagerA.EARLY_BONUS_AMOUNT(), 1e18);
    }

    function test_stake_successful_with_valid_bls_proof() public {
        _stakeAsUser(alice, 200 ether, FORKA_ID);
    }

    function test_stake_mints_nft_for_new_validator() public {
        _stakeAsUser(alice, 200 ether, FORKA_ID);

        assertEq(stakeManagerA.balanceOf(alice), 1);
        assertEq(stakeManagerA.ownerOf(1), alice);
    }

    function test_stake_reverts_when_paused() public {
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

    function test_stake_reverts_with_invalid_stake_version() public {
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

    function test_stake_reverts_with_insufficient_amount() public {
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

    function test_stake_reverts_with_insufficient_allowance() public {
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

        vm.expectRevert(NotApproved.selector);
        stakeManagerA.stake(params, proof);
        vm.stopPrank();
    }

    function test_stake_increases_existing_validator_stake() public {
        _stakeAsUser(alice, 200 ether, FORKA_ID);
        ValidatorBalance memory balanceBefore = stakeManagerA.validatorBalance(alice);
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
        ValidatorBalance memory balanceAfter = stakeManagerA.validatorBalance(alice);

        assertEq(stakeManagerA.balanceOf(alice), 1);
        assertEq(balanceAfter.stakeAmount, balanceBefore.stakeAmount + params.stakeAmount);
        vm.stopPrank();
    }

    function test_begin_unstaking_sets_exit_timestamp() public {
        _stakeAsUser(alice, 200 ether, FORKA_ID);
        skip(1 days);
        UnstakingParams memory params = UnstakingParams({
            stakeAmount: 100 ether,
            stakeVersion: testConfigVersionA,
            validator: alice
        });

        vm.prank(address(validatorManagerA));
        stakeManagerA.beginUnstaking(params);
        ValidatorBalance memory balance = stakeManagerA.validatorBalance(alice);
        assertEq(balance.stakeExitTimestamp, block.timestamp + testConfigA.minUnstakeDelay);
    }

    function test_begin_unstaking_reverts_with_invalid_validator() public {
        _stakeAsUser(alice, 200 ether, FORKA_ID);
        skip(1 days);
        UnstakingParams memory params = UnstakingParams({
            stakeAmount: 100 ether,
            stakeVersion: testConfigVersionA,
            validator: bob
        });

        vm.prank(address(validatorManagerA));
        vm.expectRevert(ValidatorNotFound.selector);
        stakeManagerA.beginUnstaking(params);
    }

    function test_begin_unstaking_reverts_when_already_unstaking() public {
        _stakeAsUser(alice, 200 ether, FORKA_ID);
        _beginUnstakingAsValidator(alice, 100 ether, FORKA_ID);

        skip(1 days);
        UnstakingParams memory params = UnstakingParams({
            stakeAmount: 100 ether,
            stakeVersion: testConfigVersionA,
            validator: bob
        });

        vm.prank(address(validatorManagerA));
        vm.expectRevert(NotAllowed.selector);
        stakeManagerA.beginUnstaking(params);
    }

    function test_begin_unstaking_reverts_for_non_validator_manager() public {
        _stakeAsUser(alice, 200 ether, FORKA_ID);
        skip(1 days);
        UnstakingParams memory params = UnstakingParams({
            stakeAmount: 100 ether,
            stakeVersion: testConfigVersionA,
            validator: alice
        });

        vm.prank(alice);
        vm.expectRevert(NotValidatorManager.selector);
        stakeManagerA.beginUnstaking(params);
    }

    function test_complete_unstaking_transfers_tokens() public {
        _stakeAsUser(alice, 200 ether, FORKA_ID);
        _beginUnstakingAsValidator(alice, 100 ether, FORKA_ID);

        skip(10 days);
        uint256 balanceBefore = TOKEN_CHAINA.balanceOf(alice);

        vm.prank(address(validatorManagerA));
        vm.expectEmit(true, true, true, true);
        emit ValidatorExit(alice, testConfigVersionA, 0, true);
        stakeManagerA.completeUnstaking(alice);
        uint256 balanceAfter = TOKEN_CHAINA.balanceOf(alice);
        assertEq(balanceAfter - balanceBefore, 100 ether);
    }

    function test_complete_unstaking_burns_nft_on_full_exit() public {
        _stakeAsUser(alice, 200 ether, FORKA_ID);
        _beginUnstakingAsValidator(alice, 200 ether, FORKA_ID);

        skip(10 days);
        uint256 balanceBefore = TOKEN_CHAINA.balanceOf(alice);

        vm.prank(address(validatorManagerA));
        vm.expectEmit(true, true, true, true);
        emit ValidatorExit(alice, testConfigVersionA, 0, false);
        stakeManagerA.completeUnstaking(alice);
        uint256 balanceAfter = TOKEN_CHAINA.balanceOf(alice);
        assertEq(balanceAfter - balanceBefore, 200 ether);
        assertEq(stakeManagerA.balanceOf(alice), 0);
    }

    function test_complete_unstaking_reverts_before_delay() public {
        _stakeAsUser(alice, 200 ether, FORKA_ID);
        _beginUnstakingAsValidator(alice, 200 ether, FORKA_ID);

        skip(1 days);

        vm.prank(address(validatorManagerA));
        vm.expectRevert(NotAllowed.selector);
        stakeManagerA.completeUnstaking(alice);
    }

    function test_slash_validator_reduces_stake() public {
        _stakeAsUser(alice, 200 ether, FORKA_ID);
        SlashParams memory params = SlashParams({validator: alice, slashAmount: 50 ether});

        vm.prank(address(validatorManagerA));
        emit ValidatorSlashed(alice, 50 ether, 200 ether, 150 ether, block.timestamp);
        stakeManagerA.slashValidator(params);
    }

    function test_slash_validator_reverts_with_zero_amount() public {
        _stakeAsUser(alice, 200 ether, FORKA_ID);
        SlashParams memory params = SlashParams({validator: alice, slashAmount: 0});

        vm.prank(address(validatorManagerA));
        vm.expectRevert(ZeroSlashAmount.selector);
        stakeManagerA.slashValidator(params);
    }

    function test_slash_validator_reverts_with_insufficient_stake() public {
        _stakeAsUser(alice, 200 ether, FORKA_ID);
        SlashParams memory params = SlashParams({validator: alice, slashAmount: 300 ether});

        vm.prank(address(validatorManagerA));
        vm.expectRevert(InsufficientStakeToSlash.selector);
        stakeManagerA.slashValidator(params);
    }

    function test_distribute_rewards_allocates_rewards_to_validators() public {
        _stakeAsUser(alice, 200 ether, FORKA_ID);
        _stakeAsUser(bob, 200 ether, FORKA_ID);

        BlsTestData memory aliceData = validatorBlsData[alice];
        BlsTestData memory bobData = validatorBlsData[bob];

        IValidatorTypes.ValidatorInfo[] memory validators = new IValidatorTypes.ValidatorInfo[](2);
        validators[0] = IValidatorTypes.ValidatorInfo({
            blsPublicKey: [
                vm.parseUint(aliceData.publicKey[0]),
                vm.parseUint(aliceData.publicKey[1]),
                vm.parseUint(aliceData.publicKey[2]),
                vm.parseUint(aliceData.publicKey[3])
            ],
            wallet: alice,
            status: IValidatorTypes.ValidatorStatus.Active,
            attestationCount: 100,
            invalidAttestations: 10
        });
        validators[1] = IValidatorTypes.ValidatorInfo({
            blsPublicKey: [
                vm.parseUint(bobData.publicKey[0]),
                vm.parseUint(bobData.publicKey[1]),
                vm.parseUint(bobData.publicKey[2]),
                vm.parseUint(bobData.publicKey[3])
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
}
