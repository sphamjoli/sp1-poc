// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BridgeBaseTest} from "../base/BridgeBase.t.sol";

contract BridgeAdminTest is BridgeBaseTest {
    function test_ownerCanPauseAndUnpause() public {
        vm.selectFork(FORKA_ID);

        vm.prank(ownerA);
        CHAINA.pause();

        vm.startPrank(alice);
        TOKEN_CHAINA.approve(address(CHAINA), 1 ether);
        vm.expectRevert();
        CHAINA.deposit(
            DepositParams({
                amount: 1 ether,
                token: address(TOKEN_CHAINA),
                to: alice,
                destinationChain: CHAINB_ID
            })
        );
        vm.stopPrank();

        vm.prank(ownerA);
        CHAINA.unpause();

        vm.startPrank(alice);
        TOKEN_CHAINA.approve(address(CHAINA), 1 ether);
        CHAINA.deposit(
            DepositParams({
                amount: 1 ether,
                token: address(TOKEN_CHAINA),
                to: alice,
                destinationChain: CHAINB_ID
            })
        );
        vm.stopPrank();

        assertEq(CHAINA.DEPOSIT_COUNTER(), 1);
    }

    function test_nonOwnerCannotPause() public {
        vm.selectFork(FORKA_ID);
        vm.prank(alice);
        vm.expectRevert();
        CHAINA.pause();
    }

    function test_ownerCanRescueEth() public {
        vm.selectFork(FORKA_ID);

        vm.deal(address(CHAINA), 2 ether);
        uint256 before = ownerA.balance;

        vm.prank(ownerA);
        CHAINA.rescueEth(1 ether, ownerA);

        assertEq(ownerA.balance, before + 1 ether);
    }

    function test_ownerCanRescueTokens() public {
        vm.selectFork(FORKA_ID);

        vm.prank(ownerA);
        TOKEN_CHAINA.transfer(address(CHAINA), 10 ether);
        uint256 before = TOKEN_CHAINA.balanceOf(ownerA);

        vm.prank(ownerA);
        CHAINA.rescueTokens(address(TOKEN_CHAINA), 3 ether, ownerA);

        assertEq(TOKEN_CHAINA.balanceOf(ownerA), before + 3 ether);
    }
}
