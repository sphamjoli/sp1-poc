// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {BridgeToken} from "../../src/test/BridgeToken.sol";
import {Bridge} from "../../src/bridge/Bridge.sol";
import {IBridgeTypes} from "../../src/bridge/BridgeTypes.sol";
import {Upgrades, Options} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {LocalExitTreeLib, SparseMerkleTree} from "../../src/libs/LocalExitTreeLib.sol";

/// @title BridgeBaseTest
/// @notice Base test harness that spins up two forked chains with Bridge and ERC20 test tokens,
/// @notice sets deterministic users/balances, and provides helpers for labeling and owner pranks.
/// @dev Uses Foundry cheatcodes and OpenZeppelin Foundry Upgrades to deploy UUPS proxies.
abstract contract BridgeBaseTest is Test, IBridgeTypes {
    using LocalExitTreeLib for SparseMerkleTree.Bytes32SMT;
    using SparseMerkleTree for SparseMerkleTree.Bytes32SMT;

    /// @notice Program verification key for SP1 verifier
    bytes32 public constant PROGRAM_VKEY =
        hex"005a0f7559959ae95bb66f020e3d30b7b091755fb43e911dd8b967c901489a83";

    /// @notice Verifier address on all networks
    address public constant SP1_VERIFIER = address(0x3B6041173B80E77f038f3F2C0f9744f04837185e);

    /// @notice Test user addresses
    address public alice;
    address public bob;
    address public spha;
    address public james;
    address public jenifer;
    address public ownerA;
    address public ownerB;

    /// @notice Private keys for owners
    uint256 public ownerAPrivateKey;
    uint256 public ownerBPrivateKey;

    /// @notice Default token balances for testing
    uint256 public immutable DEFAULT_OWNER_TOKEN_BALANCE = 99999999999999 ether;
    uint256 public immutable DEFAULT_TOKEN_BALANCE = 1000 ether;

    /// @notice Bridge token for Chain A
    BridgeToken public TOKEN_CHAINA;

    /// @notice Bridge token for Chain B
    BridgeToken public TOKEN_CHAINB;

    /// @notice Bridge contracts for both chains
    Bridge public CHAINA;
    Bridge public CHAINB;

    /// @notice Fork IDs for chain simulation (Foundry fork handles)
    uint256 public FORKA_ID;
    uint256 public FORKB_ID;

    /// @notice Chain IDs observed within each fork after deployment
    uint256 public CHAINA_ID;
    uint256 public CHAINB_ID;

    /// @notice Upgrades deployment options
    Options public options;

    /// @notice Local exit trees for each chain
    SparseMerkleTree.Bytes32SMT internal treeA;
    SparseMerkleTree.Bytes32SMT internal treeB;

    /// @notice End-to-end environment bootstrap across two forks
    /// @dev Creates users, forks, deploys bridge/token contracts per chain, mints and distributes balances, labels addresses.
    function setUp() public virtual noGasMetering {
        (ownerA, ownerAPrivateKey) = _createUserWitPrivateKey("ownerA");
        (ownerB, ownerBPrivateKey) = _createUserWitPrivateKey("ownerB");
        spha = _createUser("spha");
        james = _createUser("james");
        alice = _createUser("alice");
        bob = _createUser("bob");
        jenifer = _createUser("jenifer");

        // Skip bytecode and storage layout checks for faster proxy deploys in tests.
        options.unsafeSkipAllChecks = true;

        // Create forks from RPC URLs provided via environment.
        FORKA_ID = vm.createFork(vm.envString("ETH_RPC_URL"));
        FORKB_ID = vm.createFork(vm.envString("BASE_RPC_URL"));

        // Chain A setup
        vm.selectFork(FORKA_ID);
        _setupChainA();

        // Chain B setup
        vm.selectFork(FORKB_ID);
        _setupChainB();

        // Fund users with test tokens on both chains
        _distributeTokens();

        // Label addresses for debug readability
        _labelAddresses();
    }

    /// @notice Basic sanity checks for Chain A token configuration
    function test_token_Config() external {
        vm.selectFork(FORKA_ID);
        assertEq(TOKEN_CHAINA.totalSupply(), DEFAULT_OWNER_TOKEN_BALANCE);
        assertEq(TOKEN_CHAINA.name(), "TOKEN Chain A");
        assertEq(TOKEN_CHAINA.symbol(), "TKCA");
    }
    /// @notice Deploys a token
    /// @param sender The address to use to deploy
    /// @param forkId The fork to use to deploy
    /// @param name The name of the token
    /// @param symbol The symbol for the token

    function _deployToken(
        address sender,
        uint256 forkId,
        string memory name,
        string memory symbol
    )
        internal
        returns (BridgeToken)
    {
        vm.startPrank(sender);
        vm.selectFork(forkId);
        BridgeToken token = new BridgeToken(name, symbol);
        token.mint(sender, DEFAULT_OWNER_TOKEN_BALANCE);
        return token;
    }

    /// @notice Deploy token and bridge contracts on Chain A and initialize local state
    /// @dev Deploys a UUPS proxy for Bridge with ownerA as the initial owner and initializes the SMT.
    function _setupChainA() internal {
        vm.startPrank(ownerA);

        TOKEN_CHAINA = new BridgeToken("TOKEN Chain A", "TKCA");
        TOKEN_CHAINA.mint(ownerA, DEFAULT_OWNER_TOKEN_BALANCE);

        address bridgeChainA = Upgrades.deployUUPSProxy(
            "Bridge.sol", abi.encodeCall(Bridge.initialize, (ownerA)), options
        );
        CHAINA = Bridge(payable(bridgeChainA));
        CHAINA_ID = block.chainid;

        treeA.initialize();

        vm.stopPrank();
    }

    /// @notice Deploy token and bridge contracts on Chain B and initialize local state
    /// @dev Deploys a UUPS proxy for Bridge with ownerB as the initial owner and initializes the SMT.
    function _setupChainB() internal {
        vm.startPrank(ownerB);

        // Fixed display name typo to keep naming consistent with Chain A
        TOKEN_CHAINB = new BridgeToken("TOKEN Chain B", "TKCB");
        TOKEN_CHAINB.mint(ownerB, DEFAULT_OWNER_TOKEN_BALANCE);

        address bridgeChainB = Upgrades.deployUUPSProxy(
            "Bridge.sol", abi.encodeCall(Bridge.initialize, (ownerB)), options
        );
        CHAINB = Bridge(payable(bridgeChainB));
        CHAINB_ID = block.chainid;

        treeB.initialize();

        vm.stopPrank();
    }

    /// @notice Distribute default token balances to test users on both chains
    /// @dev Calls chain-specific helper after switching to each fork.
    function _distributeTokens() internal {
        vm.selectFork(FORKA_ID);
        _distributeTokensOnChain(TOKEN_CHAINA, FORKA_ID);

        vm.selectFork(FORKB_ID);
        _distributeTokensOnChain(TOKEN_CHAINB, FORKB_ID);
    }

    /// @notice Distribute default token balances to a fixed set of users on a given chain
    /// @param token BridgeToken instance to transfer
    /// @param forkId Fork identifier to select correct owner and chain
    function _distributeTokensOnChain(BridgeToken token, uint256 forkId) internal {
        _prankOwnerOnChain(forkId);

        address[] memory users = new address[](5);
        users[0] = spha;
        users[1] = james;
        users[2] = alice;
        users[3] = bob;
        users[4] = jenifer;

        for (uint256 i = 0; i < users.length; i++) {
            require(
                token.transfer(users[i], DEFAULT_TOKEN_BALANCE),
                "_distributeTokensOnChain:Transfer Failed"
            );
            assertEq(token.balanceOf(users[i]), DEFAULT_TOKEN_BALANCE);
        }

        vm.stopPrank();
    }

    /// @notice Label common addresses for better trace readability in logs
    function _labelAddresses() internal {
        vm.label(address(TOKEN_CHAINA), "Token Chain A");
        vm.label(address(TOKEN_CHAINB), "Token Chain B");
        vm.label(address(CHAINA), "Bridge Chain A");
        vm.label(address(CHAINB), "Bridge Chain B");
        vm.label(spha, "Spha");
        vm.label(alice, "Alice");
        vm.label(james, "James");
        vm.label(bob, "Bob");
        vm.label(jenifer, "Jenifer");
        vm.label(ownerA, "OwnerA");
        vm.label(ownerB, "OwnerB");
    }

    /// @notice Create a new test user with funded native balance and label it
    /// @param name Label to assign to the created address
    /// @return user Newly created payable address
    function _createUser(string memory name) internal returns (address payable user) {
        user = payable(makeAddr(name));
        vm.deal({account: user, newBalance: DEFAULT_TOKEN_BALANCE});
        vm.label(user, name);
    }

    /// @notice Create a new test user with funded native balance and labels it
    /// @param name Label to assign to the created address
    /// @return (account,privateKey) Newly created payable address
    function _createUserWitPrivateKey(string memory name)
        internal
        returns (address payable, uint256)
    {
        (address user, uint256 userPk) = makeAddrAndKey(name);
        vm.deal({account: user, newBalance: DEFAULT_TOKEN_BALANCE});
        vm.label(user, name);
        return (payable(user), userPk);
    }

    /// @notice Create a new test user, fund native and token balances on a specified chain
    /// @param name Label to assign to the created address
    /// @param token BridgeToken to transfer
    /// @param forkId Fork identifier (selects owner prank)
    /// @return user Newly created payable address
    function _createUserWithTokenBalance(
        string memory name,
        BridgeToken token,
        uint256 forkId
    )
        internal
        returns (address payable user)
    {
        _prankOwnerOnChain(forkId);
        user = payable(makeAddr(name));
        vm.deal({account: user, newBalance: DEFAULT_TOKEN_BALANCE});
        require(
            token.transfer(user, DEFAULT_TOKEN_BALANCE),
            "_createUserWithTokenBalance: Transfer failed"
        );
        assertEq(token.balanceOf(user), DEFAULT_TOKEN_BALANCE);
        vm.stopPrank();
    }

    /// @notice Begin an owner prank on the correct chain based on fork id
    /// @param forkId Fork identifier used to choose ownerA or ownerB
    function _prankOwnerOnChain(uint256 forkId)
        internal
        returns (address currentOwner, uint256 currentOwnerPK)
    {
        vm.selectFork(forkId);
        if (forkId == FORKA_ID) {
            vm.startPrank(ownerA);
            currentOwner = ownerA;
            currentOwnerPK = ownerAPrivateKey;
        } else {
            vm.startPrank(ownerB);
            currentOwner = ownerB;
            currentOwnerPK = ownerBPrivateKey;
        }
    }
}
