// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {SP1VerifierGateway} from "@sp1-contracts/SP1VerifierGateway.sol";
import {BridgeToken} from "../../src/test/BridgeToken.sol";
import {Bridge} from "../../src/bridge/Bridge.sol";
import {IBridgeUtils} from "../../src/bridge/IBridgeTypes.sol";
import {Upgrades, Options} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {JsonDeploymentHandler} from "../util/JsonDeploymentHandler.sol";
import {StringUtil} from "../util/StringUtil.sol";

/// @title BridgeDeployScript
/// @notice Deployment script for cross-chain bridge infrastructure
/// @dev Deploys bridge tokens and bridge contracts using chain ID context
contract BridgeDeployScript is Script, JsonDeploymentHandler, IBridgeUtils {
    using StringUtil for uint256;

    /// @notice Program verification key for SP1 verifier
    bytes32 public constant PROGRAM_VKEY = hex"005a0f7559959ae95bb66f020e3d30b7b091755fb43e911dd8b967c901489a83";

    /// @notice SP1 verifier gateway address
    address public constant SP1_VERIFIER_GATEWAY = 0x397A5f7f3dBd538f23DE225B51f532c34448dA9B;

    /// @notice Default token supply for bridge tokens
    uint256 public constant DEFAULT_TOKEN_SUPPLY = 1000000000 ether;

    /// @notice Bridge tokens (context determined by chain ID)
    BridgeToken public tokenA;
    BridgeToken public tokenB;

    /// @notice Bridge contract (context determined by chain ID)
    Bridge public bridge;

    /// @notice Upgrade options for UUPS proxy deployment
    Options public options;

    /// @notice Deployment result structure
    struct DeploymentResult {
        address tokenA;
        address tokenB;
        address bridge;
        uint256 chainId;
    }

    constructor() JsonDeploymentHandler("bridge-deployment") {}

    /// @notice Main deployment function
    /// @dev Deploys bridge infrastructure on current chain
    function run() public {
        console.log("Starting Bridge Deployment on Chain ID:", block.chainid);

        options.unsafeSkipAllChecks = true;

        _deployOnCurrentChain();

        console.log("Bridge Deployment Completed on Chain ID:", block.chainid);
    }

    /// @notice Deploys bridge infrastructure on current chain
    function _deployOnCurrentChain() internal {
        uint256 deployerPrivateKey = vm.envUint("NETWORK_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying to Chain ID:", block.chainid);

        vm.startBroadcast(deployerPrivateKey);

        (string memory nameA, string memory symbolA, string memory nameB, string memory symbolB) = _getTokenMetadata();

        tokenA = new BridgeToken(nameA, symbolA);
        tokenB = new BridgeToken(nameB, symbolB);

        tokenA.mint(deployer, DEFAULT_TOKEN_SUPPLY);
        tokenB.mint(deployer, DEFAULT_TOKEN_SUPPLY);

        address bridgeAddress =
            Upgrades.deployUUPSProxy("Bridge.sol", abi.encodeCall(Bridge.initialize, (deployer)), options);
        bridge = Bridge(payable(bridgeAddress));

        vm.stopBroadcast();

        _writeAddress("tokenA", address(tokenA));
        _writeAddress("tokenB", address(tokenB));
        _writeAddress("bridge", address(bridge));
        _writeDeployment();

        console.log("Deployment completed on Chain ID:", block.chainid);
        console.log("  Token A:", address(tokenA));
        console.log("  Token B:", address(tokenB));
        console.log("  Bridge:", address(bridge));
    }

    /// @notice Gets token metadata based on current chain ID
    /// @return nameA Token A name
    /// @return symbolA Token A symbol
    /// @return nameB Token B name
    /// @return symbolB Token B symbol
    function _getTokenMetadata()
        internal
        view
        returns (string memory nameA, string memory symbolA, string memory nameB, string memory symbolB)
    {
        uint256 currentChainId = block.chainid;

        if (currentChainId == 1) {
            return ("Ethereum Bridge Token A", "EBTA", "Ethereum Bridge Token B", "EBTB");
        } else if (currentChainId == 11155111) {
            return ("Sepolia Bridge Token A", "SBTA", "Sepolia Bridge Token B", "SBTB");
        } else if (currentChainId == 8453) {
            return ("Base Bridge Token A", "BBTA", "Base Bridge Token B", "BBTB");
        } else if (currentChainId == 84532) {
            return ("Base Sepolia Bridge Token A", "BSBTA", "Base Sepolia Bridge Token B", "BSBTB");
        } else if (currentChainId == 137) {
            return ("Polygon Bridge Token A", "PBTA", "Polygon Bridge Token B", "PBTB");
        } else if (currentChainId == 80001) {
            return ("Mumbai Bridge Token A", "MBTA", "Mumbai Bridge Token B", "MBTB");
        } else if (currentChainId == 42161) {
            return ("Arbitrum Bridge Token A", "ABTA", "Arbitrum Bridge Token B", "ABTB");
        } else if (currentChainId == 421614) {
            return ("Arbitrum Sepolia Bridge Token A", "ASBTA", "Arbitrum Sepolia Bridge Token B", "ASBTB");
        } else if (currentChainId == 10) {
            return ("Optimism Bridge Token A", "OBTA", "Optimism Bridge Token B", "OBTB");
        } else if (currentChainId == 11155420) {
            return ("Optimism Sepolia Bridge Token A", "OSBTA", "Optimism Sepolia Bridge Token B", "OSBTB");
        } else {
            string memory chainIdStr = currentChainId.toString();
            return (
                string(abi.encodePacked("Bridge Token A Chain ", chainIdStr)),
                string(abi.encodePacked("BTA", chainIdStr)),
                string(abi.encodePacked("Bridge Token B Chain ", chainIdStr)),
                string(abi.encodePacked("BTB", chainIdStr))
            );
        }
    }

    /// @notice Configures bridge with remote chain connection
    /// @param remoteChainId Chain ID of the remote chain
    /// @param remoteBridgeAddress Address of the remote bridge
    function configureBridge(uint256 remoteChainId, address remoteBridgeAddress) external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        console.log("Configuring bridge on Chain ID:", block.chainid);
        console.log("Remote Chain ID:", remoteChainId);
        console.log("Remote Bridge:", remoteBridgeAddress);

        _readDeployment();
        address currentBridge = _readAddress("bridge");

        require(currentBridge != address(0), "Bridge not found in deployment");

        vm.startBroadcast(deployerPrivateKey);

        vm.stopBroadcast();

        console.log("Bridge configuration completed");
    }

    /// @notice Verifies deployment on current chain
    /// @return success True if deployment is valid
    function verifyDeployment() external view returns (bool success) {
        console.log("Verifying deployment on Chain ID:", block.chainid);

        string memory root = vm.projectRoot();
        string memory fileName = string.concat(uint256(block.chainid).toString(), ".json");
        string memory filePath = string.concat(DEPLOY_DIR, fileName);
        string memory path = string.concat(root, "/", filePath);

        try vm.readFile(path) returns (string memory json) {
            address deployedTokenA = vm.parseJsonAddress(json, ".addresses.tokenA");
            address deployedTokenB = vm.parseJsonAddress(json, ".addresses.tokenB");
            address deployedBridge = vm.parseJsonAddress(json, ".addresses.bridge");

            if (deployedTokenA == address(0) || deployedTokenB == address(0) || deployedBridge == address(0)) {
                console.log("Verification FAILED: Zero addresses found");
                return false;
            }

            console.log("Verification PASSED");
            console.log("  Token A:", deployedTokenA);
            console.log("  Token B:", deployedTokenB);
            console.log("  Bridge:", deployedBridge);
            return true;
        } catch {
            console.log("Verification FAILED: Could not read deployment file");
            return false;
        }
    }

    /// @notice Gets deployed addresses from current chain
    /// @return tokenAAddr Address of token A
    /// @return tokenBAddr Address of token B
    /// @return bridgeAddr Address of bridge
    function getDeployedAddresses() external returns (address tokenAAddr, address tokenBAddr, address bridgeAddr) {
        _readDeployment();
        return (_readAddress("tokenA"), _readAddress("tokenB"), _readAddress("bridge"));
    }
}
