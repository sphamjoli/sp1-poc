// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {StringUtil} from "./StringUtil.sol";

/// @title JsonDeploymentHandler
/// @notice Simplified deployment handler for managing contract addresses only
/// @dev Provides JSON-based deployment tracking with chain ID-specific outputs
abstract contract JsonDeploymentHandler is Script {
    using StringUtil for uint256;
    using stdJson for string;

    /// @notice JSON serialization output
    string internal output;

    /// @notice JSON input for reading existing deployments
    string internal readJson;

    /// @notice Current chain ID as string
    string public chainId;

    /// @notice Deployment key identifier
    string public key;

    /// @notice Internal key for JSON serialization
    string internal constant INTERNAL_KEY = "addresses";

    /// @notice Base directory for deployment outputs
    string internal constant DEPLOY_DIR = "./deploy-out/";

    /// @notice Events for deployment tracking
    event ContractDeployed(
        string indexed contractName, address indexed contractAddress, uint256 indexed chainId
    );
    event DeploymentFileCreated(string indexed fileName, uint256 indexed chainId);

    /// @notice Constructor to initialize deployment handler
    /// @param _key Unique identifier for this deployment session
    constructor(string memory _key) {
        chainId = (block.chainid).toString();
        key = _key;
    }

    /// @notice Reads an address from the deployment JSON file
    /// @param contractKey Contract identifier key
    /// @return addr The contract address, or address(0) if not found
    function _readAddress(string memory contractKey) internal view returns (address addr) {
        string memory path = string.concat(".addresses.", contractKey);
        try vm.parseJsonAddress(readJson, path) returns (address parsedAddr) {
            return parsedAddr;
        } catch {
            return address(0);
        }
    }

    /// @notice Reads the existing deployment JSON file for current chain
    /// @dev Attempts to read from chain ID specific deployment file
    function _readDeployment() internal {
        string memory root = vm.projectRoot();
        string memory fileName = string.concat(chainId, ".json");
        string memory filePath = string.concat(DEPLOY_DIR, fileName);
        string memory path = string.concat(root, "/", filePath);

        try vm.readFile(path) returns (string memory content) {
            readJson = content;
        } catch {
            readJson = "";
        }
    }

    /// @notice Writes a contract address to the output JSON
    /// @param contractKey Identifier for the contract
    /// @param contractAddress The deployed contract address
    function _writeAddress(string memory contractKey, address contractAddress) internal {
        output = vm.serializeAddress(INTERNAL_KEY, contractKey, contractAddress);

        emit ContractDeployed(contractKey, contractAddress, block.chainid);
    }

    /// @notice Writes the deployment output to chain-specific JSON file
    function _writeDeployment() internal {
        string memory fileName = string.concat(DEPLOY_DIR, chainId, ".json");
        vm.writeJson(output, fileName);

        emit DeploymentFileCreated(fileName, block.chainid);
    }

    /// @notice Writes deployment to custom file name
    /// @param fileName Custom file name for the output
    function _writeDeployment(string memory fileName) internal {
        string memory fullPath = string.concat(DEPLOY_DIR, fileName);
        vm.writeJson(output, fullPath);

        emit DeploymentFileCreated(fullPath, block.chainid);
    }

    /// @notice Gets the current chain ID
    /// @return currentChainId The chain ID as uint256
    function getChainId() external view returns (uint256 currentChainId) {
        return block.chainid;
    }
}
