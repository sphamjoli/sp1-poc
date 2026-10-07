// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BridgeBaseTest} from "../base/BridgeBase.t.sol";

contract BridgeDepositTest is BridgeBaseTest {
    /// @notice Basic sanity checks for Chain A token configuration
    function test_token_Config() external {
        vm.selectFork(FORKA_ID);
        assertEq(TOKEN_CHAINA.totalSupply(), DEFAULT_OWNER_TOKEN_BALANCE);
        assertEq(TOKEN_CHAINA.name(), "TOKEN Chain A");
        assertEq(TOKEN_CHAINA.symbol(), "TKCA");
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
