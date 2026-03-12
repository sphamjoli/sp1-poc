// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BridgeBaseTest} from "../base/BridgeBase.t.sol";

contract BridgeDepositFuzzTest is BridgeBaseTest {
    function testFuzz_DepositErc20_StateUpdates(
        uint96 rawAmount,
        uint32 destinationChain,
        address recipient
    ) public {
        vm.selectFork(FORKA_ID);

        uint256 amount = bound(uint256(rawAmount), 1, DEFAULT_TOKEN_BALANCE);
        vm.assume(destinationChain != CHAINA_ID);
        vm.assume(recipient != address(0));

        uint256 counterBefore = CHAINA.DEPOSIT_COUNTER();
        uint256 userBefore = TOKEN_CHAINA.balanceOf(alice);

        vm.startPrank(alice);
        TOKEN_CHAINA.approve(address(CHAINA), amount);
        CHAINA.deposit(
            DepositParams({
                amount: amount,
                token: address(TOKEN_CHAINA),
                to: recipient,
                destinationChain: destinationChain
            })
        );
        vm.stopPrank();

        assertEq(CHAINA.DEPOSIT_COUNTER(), counterBefore + 1);
        assertEq(TOKEN_CHAINA.balanceOf(alice), userBefore - amount);
    }

    function testFuzz_DepositSameChainAlwaysReverts(uint96 rawAmount) public {
        vm.selectFork(FORKA_ID);

        uint256 amount = bound(uint256(rawAmount), 1, DEFAULT_TOKEN_BALANCE);

        vm.startPrank(alice);
        TOKEN_CHAINA.approve(address(CHAINA), amount);

        vm.expectRevert(abi.encodeWithSelector(SameChainTransfer.selector, CHAINA_ID));
        CHAINA.deposit(
            DepositParams({
                amount: amount,
                token: address(TOKEN_CHAINA),
                to: alice,
                destinationChain: CHAINA_ID
            })
        );
        vm.stopPrank();
    }
}
