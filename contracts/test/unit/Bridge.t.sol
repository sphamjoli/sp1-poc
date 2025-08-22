// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BridgeBaseTest} from "../base/BridgeBase.t.sol";
import "forge-std/Test.sol";

contract BridgeTest is BridgeBaseTest {
    function test_depositChainA() public {
        vm.selectFork(FORKA_ID);
        vm.startPrank(spha);
        assert(TOKEN_CHAINA.approve(address(CHAINA), type(uint256).max));
        DepositParams memory deposit =
            DepositParams({amount: 10 ether, token: address(TOKEN_CHAINA), to: jenifer, destinationChain: CHAINB_ID});
        vm.expectEmit(true, true, false, true, address(CHAINA));
        //emit Deposit(spha, 10 ether, address(TOKEN_CHAINA), jenifer, CHAINA_ID, CHAINB_ID);
        CHAINA.deposit(deposit);
        vm.stopPrank();
    }

    function test_depositChainB() public {
        vm.selectFork(FORKB_ID);
        vm.startPrank(spha);
        assert(TOKEN_CHAINB.approve(address(CHAINB), type(uint256).max));
        DepositParams memory deposit =
            DepositParams({amount: 10 ether, token: address(TOKEN_CHAINB), to: jenifer, destinationChain: CHAINA_ID});
        vm.expectEmit(true, true, false, true, address(CHAINB));
        //emit Deposit(spha, 10 ether, address(TOKEN_CHAINB), jenifer, CHAINB_ID, CHAINA_ID);
        CHAINA.deposit(deposit);
        vm.stopPrank();
    }
}
