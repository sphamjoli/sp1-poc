// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {PausableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {BridgeStorage} from "./BridgeStorage.sol";
import {IBridge} from "./IBridge.sol";
import {LocalExitTreeLib, SparseMerkleTree} from "../libs/LocalExitTreeLib.sol";

/// @title Bridge
/// @author brianspha
/// @notice Cross-chain bridge implementation with symmetric tree architecture
/// @dev Handles both deposits (source chain) and claims (destination chain)
contract Bridge is
    IBridge,
    BridgeStorage,
    Initializable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    PausableUpgradeable
{
    using LocalExitTreeLib for SparseMerkleTree.Bytes32SMT;

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable constructor
    uint256 public immutable CHAIN_ID;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        CHAIN_ID = block.chainid;
        _disableInitializers();
    }

    /// @inheritdoc IBridge
    function initialize(address owner) external initializer {
        require(owner != address(0), ZeroAddress());

        __Pausable_init();
        __Ownable_init(owner);
        __UUPSUpgradeable_init();
    }

    /// @inheritdoc IBridge
    function deposit(DepositParams calldata depositParams) external payable whenNotPaused {
        require(depositParams.amount > 0, InvalidTransaction());
        require(
            depositParams.destinationChain != CHAIN_ID,
            SameChainTransfer(depositParams.destinationChain)
        );

        if (depositParams.token == address(0)) {
            require(msg.value == depositParams.amount, InvalidTransaction());
        } else {
            IERC20 tokenContract = IERC20(depositParams.token);
            require(
                tokenContract.allowance(msg.sender, address(this)) >= depositParams.amount,
                BridgeNotApproved(depositParams.token, depositParams.amount)
            );
            require(
                tokenContract.balanceOf(msg.sender) >= depositParams.amount,
                InsufficientBalance(depositParams.token, depositParams.amount)
            );
            require(
                tokenContract.transferFrom(msg.sender, address(this), depositParams.amount),
                InsufficientBalance(depositParams.token, depositParams.amount)
            );
        }

        DepositParams memory params = DepositParams({
            amount: depositParams.amount,
            token: depositParams.token,
            to: depositParams.to,
            destinationChain: depositParams.destinationChain
        });

        (bytes32 depositRoot, uint256 depositIndex) = __addToDepositTree(params);

        emit Deposit(
            msg.sender,
            depositParams.amount,
            depositParams.token,
            depositParams.to,
            CHAIN_ID,
            depositParams.destinationChain,
            depositIndex,
            depositRoot
        );
    }

    /// @inheritdoc IBridge
    function claim(ClaimParams calldata claimParams) external whenNotPaused {
        require(claimParams.amount > 0, InvalidTransaction());
        require(claimParams.originChain != CHAIN_ID, SameChainTransfer(claimParams.originChain));

        require(
            isRootValid(claimParams.originChain, claimParams.sourceRoot),
            InvalidSourceRoot(claimParams.originChain, claimParams.sourceRoot)
        );
        require(
            !isDepositClaimed(claimParams.originChain, claimParams.depositIndex),
            AlreadyClaimed(claimParams.originChain, claimParams.depositIndex)
        );
        require(msg.sender == claimParams.to, InvalidTransaction());

        DepositParams memory originalDeposit = DepositParams({
            amount: claimParams.amount,
            token: claimParams.token,
            to: claimParams.to,
            destinationChain: CHAIN_ID
        });

        bytes32 expectedLeaf = LocalExitTreeLib.computeExitLeaf(originalDeposit);
        require(
            claimParams.proof.value == expectedLeaf, InvalidMerkleProof(claimParams.depositIndex)
        );
        require(claimParams.proof.existence, InvalidMerkleProof(claimParams.depositIndex));
        require(
            !_verifyProofAgainstRoot(claimParams.proof, claimParams.sourceRoot),
            InvalidMerkleProof(claimParams.depositIndex)
        );

        markDepositClaimed(claimParams.originChain, claimParams.depositIndex);

        ClaimLeaf memory claimLeaf = ClaimLeaf({
            sourceDepositIndex: claimParams.depositIndex,
            sourceChain: claimParams.originChain,
            sourceRoot: claimParams.sourceRoot,
            claimer: msg.sender,
            recipient: claimParams.to,
            amount: claimParams.amount,
            token: claimParams.token,
            timestamp: block.timestamp
        });

        (bytes32 claimRoot, uint256 claimIndex) = __addToClaimTree(claimLeaf);

        if (claimParams.token == address(0)) {
            require(
                address(this).balance > claimParams.amount,
                InsufficientBalance(address(0), claimParams.amount)
            );

            (bool success,) = claimParams.to.call{value: claimParams.amount}("");
            require(success, ClaimFailed(address(0), claimParams.to, claimParams.amount));
        } else {
            IERC20 tokenContract = IERC20(claimParams.token);
            require(
                tokenContract.balanceOf(address(this)) > claimParams.amount,
                InsufficientBalance(claimParams.token, claimParams.amount)
            );
            require(
                tokenContract.transfer(claimParams.to, claimParams.amount),
                ClaimFailed(claimParams.token, claimParams.to, claimParams.amount)
            );
        }

        emit Claimed(
            msg.sender,
            claimParams.amount,
            claimParams.token,
            claimParams.to,
            claimParams.originChain,
            claimParams.depositIndex,
            claimIndex,
            claimParams.sourceRoot,
            claimRoot
        );
    }

    /// @notice Update valid root for source chain
    /// @param sourceChain Source chain ID
    /// @param root Root hash to mark as valid
    /// @dev Only owner can mark roots as valid (in production this would be automated)
    function updateValidRoot(uint256 sourceChain, bytes32 root) external onlyOwner {
        markRootValid(sourceChain, root);
    }

    /// @notice Verify proof against a root hash without requiring tree storage
    /// @param proof Merkle proof to verify
    /// @param root Root hash to verify against
    /// @return valid Whether the proof is valid against the root
    function _verifyProofAgainstRoot(
        SparseMerkleTree.Proof memory proof,
        bytes32 root
    )
        internal
        pure
        returns (bool valid)
    {
        if (!proof.existence) {
            return false;
        }

        bytes32 computedRoot = proof.value;
        uint256 index = uint256(proof.key);

        for (uint256 i = 0; i < proof.siblings.length; i++) {
            bytes32 sibling = proof.siblings[i];
            if (((index >> i) & 1) == 1) {
                computedRoot = keccak256(abi.encodePacked(sibling, computedRoot));
            } else {
                computedRoot = keccak256(abi.encodePacked(computedRoot, sibling));
            }
        }

        return computedRoot == root;
    }

    /// @inheritdoc IBridge
    function rescueEth(uint256 amount, address to) external onlyOwner {
        require(to != address(0), ZeroAddress());
        require(address(this).balance >= amount, InsufficientBalance(address(0), amount));
        (bool success,) = to.call{value: amount}("");
        require(success, FailedToRescueEther());
    }

    /// @inheritdoc IBridge
    function rescueTokens(address token, uint256 amount, address to) external onlyOwner {
        require(token != address(0), ZeroAddress());
        require(to != address(0), ZeroAddress());

        IERC20 tokenContract = IERC20(token);
        require(
            tokenContract.balanceOf(address(this)) >= amount, InsufficientBalance(token, amount)
        );
        require(tokenContract.transfer(to, amount), ClaimFailed(token, to, amount));
    }

    /// @inheritdoc IBridge
    function pause() external onlyOwner {
        _pause();
    }

    /// @inheritdoc IBridge
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @inheritdoc IBridge
    function getBalance(address token) external view returns (uint256) {
        if (token == address(0)) {
            return address(this).balance;
        }
        return IERC20(token).balanceOf(address(this));
    }

    /// @notice Authorize contract upgrades
    /// @dev Only owner can authorize upgrades per UUPS pattern
    /// @param newImplementation Address of new implementation contract
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /// @notice Receive ETH deposits
    /// @dev Allows contract to receive ETH for bridging operations
    receive() external payable {}
}
