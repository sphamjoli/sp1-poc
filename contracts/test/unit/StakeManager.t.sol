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
        vm.selectFork(CHAINA_ID);
        vm.prank(owner);

        assertEq(stakeManagerA.NAME(), "StakeManager");
        assertEq(stakeManagerA.VERSION(), "1");
        assertEq(stakeManagerA.VALIDATOR_MANAGER(), address(validatorManagerA));
        assertEq(stakeManagerA.EARLY_BONUS_EPOCHS(), 12960);
        assertEq(stakeManagerA.MIN_PERFORMANCE_THRESHOLD(), 80);
        assertEq(stakeManagerA.EARLY_BONUS_AMOUNT(), 1e18);
    }

    function test_stake_successful_with_valid_bls_proof() public {
        BlsTestData memory data = validatorBlsData[alice];
        // Need to fix the staking version issue
        vm.startPrank(alice);
        vm.selectFork(CHAINA_ID);
        TOKEN_CHAINA.approve(address(stakeManagerA), 200 ether);

        uint256[4] memory pubkey = [
            vm.parseUint(data.publicKey[0]),
            vm.parseUint(data.publicKey[1]),
            vm.parseUint(data.publicKey[2]),
            vm.parseUint(data.publicKey[3])
        ];

        uint256[2] memory signature =
            [vm.parseUint(data.proofOfPossession[0]), vm.parseUint(data.proofOfPossession[1])];

        StakeParams memory params = StakeParams({
            stakeAmount: 200 ether,
            stakeVersion: stakeManagerA.getStakeVersion(testConfig)
        });

        BlsOwnerShip memory proof = BlsOwnerShip({signature: signature, pubkey: pubkey});

        vm.expectEmit(true, true, true, true);
        emit ValidatorStaked(alice, testConfigVersionA, 200 ether, block.timestamp);

        stakeManagerA.stake(params, proof);
        vm.stopPrank();
    }
}
