// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IBridgeUtils} from "./BridgeTypes.sol";
import "@solarity/solidity-lib/libs/data-structures/SparseMerkleTree.sol";
import {LocalExitTreeLib, SparseMerkleTree} from "../libs/LocalExitTreeLib.sol";

/// @title BridgeStorage
/// @notice Abstract storage layer for cross-chain bridge contracts
/// @dev Base contract providing diamond storage with symmetric tree architecture
abstract contract BridgeStorage is IBridgeUtils {
    using SparseMerkleTree for SparseMerkleTree.Bytes32SMT;
    using SparseMerkleTree for SparseMerkleTree.Proof;
    using LocalExitTreeLib for SparseMerkleTree.Bytes32SMT;

    /// @dev Protects unauthorised calls not made by the bridge contract
    modifier onlyBridge() {
        require(msg.sender == BRIDGE, NotBridge());
        _;
    }

    /// @dev Bridge storage position
    bytes32 internal constant BRIDGE_STORAGE_SLOT =
        bytes32(uint256(keccak256(abi.encodePacked("com.bridge.storage"))) - 1);

    /// @dev The bridge contract address
    address public immutable BRIDGE;
    /// @dev SparseTree Max Depth ideally 32
    uint32 public immutable MAX_DEPTH;
    /// @dev SparseTree used for tracking deposits
    SparseMerkleTree.Bytes32SMT internal depositTree;
    /// @dev SparseTree used for tracking claims
    SparseMerkleTree.Bytes32SMT internal claimTree;
    /// @dev Used to keep track of the number of deposits
    uint256 public DEPOSIT_COUNTER;
    /// @dev Used to keep track of the number of claims
    uint256 public CLAIM_COUNTER;

    constructor() {
        BRIDGE = msg.sender;
        MAX_DEPTH = 32;
        depositTree.initialize(MAX_DEPTH);
        claimTree.initialize(MAX_DEPTH);
    }

    /// @notice Get Bridge storage
    /// @return $ Storage struct
    function loadStorage() internal pure returns (Storage storage $) {
        bytes32 position = BRIDGE_STORAGE_SLOT;
        assembly {
            $.slot := position
        }
    }

    /// @notice Add deposit to deposit tree
    /// @param params Deposit parameters
    /// @return newRoot Updated deposit tree root
    /// @return depositIndex Index where deposit was stored
    function __addToDepositTree(DepositParams memory params)
        internal
        onlyBridge
        returns (bytes32 newRoot, uint256 depositIndex)
    {
        bytes32 exitLeaf = LocalExitTreeLib.computeExitLeaf(params);
        depositIndex = DEPOSIT_COUNTER;
        newRoot = depositTree.addDeposit(DEPOSIT_COUNTER++, exitLeaf);
    }

    /// @notice Add claim to claim tree
    /// @param claimLeaf Claim leaf data
    /// @return newRoot Updated claim tree root
    /// @return claimIndex Index where claim was stored
    function __addToClaimTree(ClaimLeaf memory claimLeaf)
        internal
        onlyBridge
        returns (bytes32 newRoot, uint256 claimIndex)
    {
        bytes32 claimHash = keccak256(abi.encode(claimLeaf));
        claimIndex = CLAIM_COUNTER;
        newRoot = claimTree.addDeposit(CLAIM_COUNTER++, claimHash);
    }

    /// @notice Get latest deposit tree root
    /// @return root Current deposit tree root
    function getDepositRoot() public view returns (bytes32 root) {
        return LocalExitTreeLib.getRoot(depositTree);
    }

    /// @notice Get latest claim tree root
    /// @return root Current claim tree root
    function getClaimRoot() public view returns (bytes32 root) {
        return LocalExitTreeLib.getRoot(claimTree);
    }

    /// @notice Generate proof for a deposit
    /// @param depositIndex Index of the deposit
    /// @return proof Merkle proof for the deposit
    function generateDepositProof(uint256 depositIndex)
        internal
        view
        returns (SparseMerkleTree.Proof memory proof)
    {
        return depositTree.getProof(depositIndex);
    }

    /// @notice Generate proof for a claim
    /// @param claimIndex Index of the claim
    /// @return proof Merkle proof for the claim
    function generateClaimProof(uint256 claimIndex)
        internal
        view
        returns (SparseMerkleTree.Proof memory proof)
    {
        return claimTree.getProof(claimIndex);
    }

    /// @notice Check if a deposit exists
    /// @param depositIndex Index to check
    /// @return exists Whether the deposit exists
    /// @return value The deposit leaf value
    function checkDepositExists(uint256 depositIndex)
        internal
        view
        returns (bool exists, bytes32 value)
    {
        return depositTree.checkLeafExists(depositIndex);
    }

    /// @notice Check if a claim exists
    /// @param claimIndex Index to check
    /// @return exists Whether the claim exists
    /// @return value The claim leaf value
    function checkClaimExists(uint256 claimIndex)
        internal
        view
        returns (bool exists, bytes32 value)
    {
        return claimTree.checkLeafExists(claimIndex);
    }

    /// @notice Mark source root as valid
    /// @param sourceChain Source chain ID
    /// @param root Root hash to validate
    /// @dev Only callable by bridge contract
    function markRootValid(uint256 sourceChain, bytes32 root) internal onlyBridge {
        Storage storage $ = loadStorage();
        $.validRoots[sourceChain][root] = true;
    }

    /// @notice Check if source root is valid
    /// @param sourceChain Source chain ID
    /// @param root Root hash to check
    /// @return valid Whether the root is valid
    function isRootValid(uint256 sourceChain, bytes32 root) internal view returns (bool valid) {
        Storage storage $ = loadStorage();
        return $.validRoots[sourceChain][root];
    }

    /// @notice Check if deposit has been claimed
    /// @param sourceChain Source chain ID
    /// @param depositIndex Deposit index to check
    /// @return isClaimed Whether the deposit has been claimed
    function isDepositClaimed(
        uint256 sourceChain,
        uint256 depositIndex
    )
        internal
        view
        returns (bool isClaimed)
    {
        bytes32 claimKey = keccak256(abi.encodePacked(sourceChain, depositIndex));
        Storage storage $ = loadStorage();
        return $.claimed[claimKey];
    }

    /// @notice Mark deposit as claimed
    /// @param sourceChain Source chain ID
    /// @param depositIndex Deposit index
    /// @dev Only callable by bridge contract
    function markDepositClaimed(uint256 sourceChain, uint256 depositIndex) internal onlyBridge {
        bytes32 claimKey = keccak256(abi.encodePacked(sourceChain, depositIndex));
        Storage storage $ = loadStorage();
        $.claimed[claimKey] = true;
    }

    /// @notice Get Bridge storage key
    /// @return Storage position key
    function getStorageKey() internal pure returns (bytes32) {
        return BRIDGE_STORAGE_SLOT;
    }
}
