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
}
