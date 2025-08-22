// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {SP1VerifierGateway} from "@sp1-contracts/SP1VerifierGateway.sol";
import {BridgeToken} from "../../src/test/BridgeToken.sol";
import {Bridge} from "../../src/bridge/Bridge.sol";
import {IBridgeUtils} from "../../src/bridge/IBridgeTypes.sol";
import {Upgrades, Options} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {LocalExitTreeLib, SparseMerkleTree} from "../../src/libs/LocalExitTreeLib.sol";

abstract contract BridgeBaseTest is Test, IBridgeUtils {
    using LocalExitTreeLib for SparseMerkleTree.Bytes32SMT;
    using SparseMerkleTree for SparseMerkleTree.Bytes32SMT;

    /// @notice Program verification key for SP1 verifier
    bytes32 public constant PROGRAM_VKEY = hex"005a0f7559959ae95bb66f020e3d30b7b091755fb43e911dd8b967c901489a83";

    /// @notice Test user addresses
    address public alice;
    address public spha;
    address public james;
    address public owner;
    address public bob;
    address public jenifer;

    /// @notice Default token balances for testing
    uint256 public immutable defaultOwnerTokenBalance = 99999999999999 ether;
    uint256 public immutable defaultTokenBalance = 1000 ether;
    uint256 public immutable defaultTransferAmount = 100 ether;

    /// @notice Bridge tokens for Chain A
    BridgeToken public TOKEN_CHAINA;

    /// @notice Bridge tokens for Chain B
    BridgeToken public TOKEN_CHAINB;

    /// @notice Bridge contracts for both chains
    Bridge public CHAINA;
    Bridge public CHAINB;

    /// @notice Fork IDs for chain simulation
    uint256 public FORKA_ID;
    uint256 public FORKB_ID;

    /// @notice Fork IDs for chain simulation
    uint256 public CHAINA_ID;
    uint256 public CHAINB_ID;

    /// @dev Upgrades Option
    Options public options;

    /// @dev Tree Chain A
    SparseMerkleTree.Bytes32SMT internal treeA;
    /// @dev Tree Chain B
    SparseMerkleTree.Bytes32SMT internal treeB;

    function setUp() public virtual {
        owner = _createUser("owner");
        spha = _createUser("spha");
        james = _createUser("james");
        alice = _createUser("alice");
        bob = _createUser("bob");
        jenifer = _createUser("jenifer");
        options.unsafeSkipAllChecks = true;

        FORKA_ID = vm.createSelectFork(vm.envString("ETH_RPC_URL"), 23164198);
        FORKB_ID = vm.createSelectFork(vm.envString("BASE_RPC_URL"), 34342799);

        vm.selectFork(FORKA_ID);
        _setupChainA();

        vm.selectFork(FORKB_ID);
        _setupChainB();

        _distributeTokens();

        _labelAddresses();
    }

    function test_token_Config() external {
        vm.selectFork(FORKA_ID);
        assertEq(TOKEN_CHAINA.totalSupply(), defaultOwnerTokenBalance);
        assertEq(TOKEN_CHAINA.name(), "TOKEN Chain A");
        assertEq(TOKEN_CHAINA.symbol(), "TKCA");
    }

    function _setupChainA() internal {
        vm.startPrank(owner);

        TOKEN_CHAINA = new BridgeToken("TOKEN Chain A", "TKCA");

        TOKEN_CHAINA.mint(owner, defaultOwnerTokenBalance);

        address bridgeChainA =
            Upgrades.deployUUPSProxy("Bridge.sol", abi.encodeCall(Bridge.initialize, (owner)), options);
        CHAINA = Bridge(payable(bridgeChainA));
        CHAINA_ID = block.chainid;
        treeA.initialize();
        vm.stopPrank();
    }

    function _setupChainB() internal {
        vm.startPrank(owner);

        TOKEN_CHAINB = new BridgeToken("TOKEN Chain B A", "TKCBA");

        TOKEN_CHAINB.mint(owner, defaultOwnerTokenBalance);

        address bridgeChainB =
            Upgrades.deployUUPSProxy("Bridge.sol", abi.encodeCall(Bridge.initialize, (owner)), options);
        CHAINB = Bridge(payable(bridgeChainB));
        CHAINB_ID = block.chainid;
        treeB.initialize();
        vm.stopPrank();
    }

    function _distributeTokens() internal {
        vm.selectFork(FORKA_ID);
        _distributeTokensOnChain(TOKEN_CHAINA);

        vm.selectFork(FORKB_ID);
        _distributeTokensOnChain(TOKEN_CHAINB);
    }

    function _distributeTokensOnChain(BridgeToken token) internal {
        vm.startPrank(owner);

        address[] memory users = new address[](4);
        users[0] = spha;
        users[1] = james;
        users[2] = alice;
        users[3] = bob;

        for (uint256 i = 0; i < users.length; i++) {
            token.transfer(users[i], defaultTokenBalance);
            assertEq(token.balanceOf(users[i]), defaultTokenBalance);
        }

        vm.stopPrank();
    }

    function _labelAddresses() internal {
        vm.label(address(TOKEN_CHAINA), "Token Chain A - A");
        vm.label(address(TOKEN_CHAINB), "Token Chain B - A");
        vm.label(address(CHAINA), "Bridge Chain A");
        vm.label(address(CHAINB), "Bridge Chain B");
        vm.label(spha, "Spha address");
        vm.label(alice, "Alice address");
        vm.label(james, "James address");
        vm.label(owner, "Owner address");
        vm.label(bob, "Bob address");
    }

    function _createUser(string memory name) internal returns (address payable) {
        address payable user = payable(makeAddr(name));
        vm.deal({account: user, newBalance: 1000 ether});
        return user;
    }

    function _createUserWithTokenBalance(string memory name, BridgeToken token) internal returns (address payable) {
        vm.startPrank(owner);
        address payable user = payable(makeAddr(name));
        vm.deal({account: user, newBalance: 1000 ether});
        token.transfer(user, defaultTokenBalance);
        assertEq(token.balanceOf(user), defaultTokenBalance);
        vm.stopPrank();
        return user;
    }

    function _switchToChainA() internal {
        vm.selectFork(FORKA_ID);
    }

    function _switchToChainB() internal {
        vm.selectFork(FORKB_ID);
    }
}
