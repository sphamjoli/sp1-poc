// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {StringUtil} from "./StringUtil.sol";

/// @title AddressReader
/// @notice Utility script for reading deployed contract addresses across chains
/// @dev Provides helper functions to read addresses from deployment JSON files
contract AddressReader is Script {
    using StringUtil for uint256;
    using stdJson for string;

    /// @notice Base directory for deployment outputs
    string internal constant DEPLOY_DIR = "./deploy-out/";

    /// @notice Reads bridge address for a specific chain
    /// @param chainId The chain ID to read from
    /// @return bridgeAddress The bridge contract address
    function readBridgeAddress(uint256 chainId) external view returns (address bridgeAddress) {
        return _readContractAddress(chainId, "bridge");
    }

    /// @notice Reads token A address for a specific chain
    /// @param chainId The chain ID to read from
    /// @return tokenAddress The token A contract address
    function readTokenA(uint256 chainId) external view returns (address tokenAddress) {
        return _readContractAddress(chainId, "tokenA");
    }

    /// @notice Reads token B address for a specific chain
    /// @param chainId The chain ID to read from
    /// @return tokenAddress The token B contract address
    function readTokenB(uint256 chainId) external view returns (address tokenAddress) {
        return _readContractAddress(chainId, "tokenB");
    }

    /// @notice Reads all deployed addresses for a specific chain
    /// @param chainId The chain ID to read from
    /// @return tokenA Token A address
    /// @return tokenB Token B address
    /// @return bridge Bridge address
    function readAllAddresses(uint256 chainId)
        external
        view
        returns (address tokenA, address tokenB, address bridge)
    {
        string memory json = _readDeploymentFile(chainId);

        tokenA = vm.parseJsonAddress(json, ".addresses.tokenA");
        tokenB = vm.parseJsonAddress(json, ".addresses.tokenB");
        bridge = vm.parseJsonAddress(json, ".addresses.bridge");

        return (tokenA, tokenB, bridge);
    }

    /// @notice Lists all available deployment files
    /// @dev Scans the deploy-out directory for deployment files
    function listDeployments() external view {
        console.log("Available deployment files in", DEPLOY_DIR);

        // Common chain IDs to check
        uint256[] memory chainIds = new uint256[](10);
        chainIds[0] = 1;
        chainIds[1] = 11155111;
        chainIds[2] = 8453;
        chainIds[3] = 84532;
        chainIds[4] = 137;
        chainIds[5] = 80001;
        chainIds[6] = 42161;
        chainIds[7] = 421614;
        chainIds[8] = 10;
        chainIds[9] = 11155420;

        for (uint256 i = 0; i < chainIds.length; i++) {
            if (_deploymentExists(chainIds[i])) {
                console.log("- deployment-", chainIds[i].toString(), ".json");
            }
        }
    }

    /// @notice Compares bridge addresses across two chains
    /// @param chainId1 First chain ID
    /// @param chainId2 Second chain ID
    function compareBridges(uint256 chainId1, uint256 chainId2) external view {
        address bridge1 = _readContractAddress(chainId1, "bridge");
        address bridge2 = _readContractAddress(chainId2, "bridge");

        console.log("Bridge Comparison:");
        console.log("Chain", chainId1.toString(), "Bridge:", bridge1);
        console.log("Chain", chainId2.toString(), "Bridge:", bridge2);

        if (bridge1 == address(0)) {
            console.log("Warning: No bridge found for chain", chainId1.toString());
        }
        if (bridge2 == address(0)) {
            console.log("Warning: No bridge found for chain", chainId2.toString());
        }
    }

    /// @notice Creates a summary of all deployments
    function deploymentSummary() external view {
        console.log("=== DEPLOYMENT SUMMARY ===");

        uint256[] memory chainIds = new uint256[](10);
        chainIds[0] = 1;
        chainIds[1] = 11155111;
        chainIds[2] = 8453;
        chainIds[3] = 84532;
        chainIds[4] = 137;
        chainIds[5] = 80001;
        chainIds[6] = 42161;
        chainIds[7] = 421614;
        chainIds[8] = 10;
        chainIds[9] = 11155420;

        for (uint256 i = 0; i < chainIds.length; i++) {
            uint256 chainId = chainIds[i];
            if (_deploymentExists(chainId)) {
                (address tokenA, address tokenB, address bridge) = this.readAllAddresses(chainId);

                console.log("");
                console.log("Chain ID:", chainId.toString());
                console.log("  Token A:", tokenA);
                console.log("  Token B:", tokenB);
                console.log("  Bridge: ", bridge);
            }
        }

        console.log("");
        console.log("=== END SUMMARY ===");
    }

    /// @notice Internal function to read a specific contract address
    /// @param chainId The chain ID
    /// @param contractKey The contract identifier
    /// @return contractAddress The contract address
    function _readContractAddress(
        uint256 chainId,
        string memory contractKey
    )
        internal
        view
        returns (address contractAddress)
    {
        string memory json = _readDeploymentFile(chainId);
        string memory path = string.concat(".addresses.", contractKey);

        try vm.parseJsonAddress(json, path) returns (address addr) {
            return addr;
        } catch {
            console.log("Warning: Could not read", contractKey, "for chain", chainId.toString());
            return address(0);
        }
    }

    /// @notice Internal function to read deployment file for a chain
    /// @param chainId The chain ID
    /// @return json The JSON content
    function _readDeploymentFile(uint256 chainId) internal view returns (string memory json) {
        string memory root = vm.projectRoot();
        string memory fileName = string.concat("deployment-", chainId.toString(), ".json");
        string memory path = string.concat(root, "/", DEPLOY_DIR, fileName);

        try vm.readFile(path) returns (string memory content) {
            return content;
        } catch {
            console.log("Error: Could not read deployment file for chain", chainId.toString());
            return "";
        }
    }

    /// @notice Internal function to check if deployment exists
    /// @param chainId The chain ID to check
    /// @return exists True if deployment file exists
    function _deploymentExists(uint256 chainId) internal view returns (bool exists) {
        string memory json = _readDeploymentFile(chainId);
        return bytes(json).length > 0;
    }
}
