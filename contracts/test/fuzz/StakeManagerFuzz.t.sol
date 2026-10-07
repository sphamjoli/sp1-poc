// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {StakeManagerBaseTest} from "../base/StakeManagerBase.t.sol";

contract StakeManagerFuzzTest is StakeManagerBaseTest {
    function testFuzz_topUpPreservesStakeAgeAndPrincipal(
        uint96 initialAmount,
        uint96 topUpAmount
    )
        public
    {
        vm.selectFork(FORKA_ID);
        uint256 initialStake = bound(uint256(initialAmount), testConfigA.minStakeAmount, 500 ether);
        uint256 topUp = bound(uint256(topUpAmount), 1, 500 ether);
        _stakeAsUser(alice, initialStake, FORKA_ID);
        uint256 originalTimestamp = stakeManagerA.validatorBalance(alice).stakeTimestamp;
        uint256 assetsBefore = TOKEN_CHAINA.balanceOf(address(stakeManagerA));
        skip(1 days);
        _stakeAsUser(alice, topUp, FORKA_ID);
        ValidatorBalance memory balance = stakeManagerA.validatorBalance(alice);
        assertEq(balance.stakeAmount, initialStake + topUp);
        assertEq(balance.stakeTimestamp, originalTimestamp);
        assertEq(TOKEN_CHAINA.balanceOf(address(stakeManagerA)), assetsBefore + topUp);
        assertEq(stakeManagerA.balanceOf(alice), 1);
    }
}
