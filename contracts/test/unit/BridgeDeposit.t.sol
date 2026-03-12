// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BridgeBaseTest} from "../base/BridgeBase.t.sol";

contract BridgeDepositTest is BridgeBaseTest {
    function test_depositErc20_UpdatesState() public {
        vm.selectFork(FORKA_ID);
        uint256 amount = 5 ether;

        uint256 userBefore = TOKEN_CHAINA.balanceOf(alice);
        uint256 bridgeBefore = TOKEN_CHAINA.balanceOf(address(CHAINA));
        uint256 counterBefore = CHAINA.DEPOSIT_COUNTER();

        vm.startPrank(alice);
        TOKEN_CHAINA.approve(address(CHAINA), amount);
        CHAINA.deposit(
            DepositParams({
                amount: amount,
                token: address(TOKEN_CHAINA),
                to: alice,
                destinationChain: CHAINB_ID
            })
        );
        vm.stopPrank();

        assertEq(CHAINA.DEPOSIT_COUNTER(), counterBefore + 1);
        assertEq(TOKEN_CHAINA.balanceOf(alice), userBefore - amount);
        assertEq(TOKEN_CHAINA.balanceOf(address(CHAINA)), bridgeBefore + amount);
    }

    function test_depositRevertsOnZeroAmount() public {
        vm.selectFork(FORKA_ID);

        vm.startPrank(alice);
        TOKEN_CHAINA.approve(address(CHAINA), 1 ether);
        vm.expectRevert(InvalidTransaction.selector);
        CHAINA.deposit(
            DepositParams({
                amount: 0,
                token: address(TOKEN_CHAINA),
                to: alice,
                destinationChain: CHAINB_ID
            })
        );
        vm.stopPrank();
    }

    function test_depositRevertsOnSameChain() public {
        vm.selectFork(FORKA_ID);

        vm.startPrank(alice);
        TOKEN_CHAINA.approve(address(CHAINA), 1 ether);
        vm.expectRevert(abi.encodeWithSelector(SameChainTransfer.selector, CHAINA_ID));
        CHAINA.deposit(
            DepositParams({
                amount: 1 ether,
                token: address(TOKEN_CHAINA),
                to: alice,
                destinationChain: CHAINA_ID
            })
        );
        vm.stopPrank();
    }

    function test_depositEthRequiresMatchingMsgValue() public {
        vm.selectFork(FORKA_ID);

        vm.prank(alice);
        vm.expectRevert(InvalidTransaction.selector);
        CHAINA.deposit(
            DepositParams({
                amount: 1 ether,
                token: address(0),
                to: alice,
                destinationChain: CHAINB_ID
            })
        );
    }

    function test_depositEthSuccess() public {
        vm.selectFork(FORKA_ID);
        vm.deal(alice, 1 ether);
        uint256 before = address(CHAINA).balance;

        vm.prank(alice);
        CHAINA.deposit{value: 1 ether}(
            DepositParams({
                amount: 1 ether,
                token: address(0),
                to: alice,
                destinationChain: CHAINB_ID
            })
        );

        assertEq(address(CHAINA).balance, before + 1 ether);
        assertEq(CHAINA.DEPOSIT_COUNTER(), 1);
    }
}
