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
import {IValidatorManager} from "../validator/ValidatorManager.sol";
import {IValidatorTypes} from "../validator/IValidatorTypes.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardUpgradeable} from
    "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

/// @title Bridge
/// @author brianspha
/// @notice Cross-chain bridge implementation with symmetric tree architecture
/// @dev Handles both deposits (source chain) and claims (destination chain)
/// @dev THe current version doesnt align with the latest design as it was used
/// To build a POC still needs major updating :XD
contract Bridge is
    IBridge,
    BridgeStorage,
    Initializable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using LocalExitTreeLib for SparseMerkleTree.Bytes32SMT;
    using SafeERC20 for IERC20;

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable constructor
    uint256 public immutable CHAIN_ID;

    /// @notice Address of the validator manager contract
    address public VALIDATOR_MANAGER;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        CHAIN_ID = block.chainid;
        _disableInitializers();
    }

    /// @inheritdoc IBridge
    function initialize(address owner) external override initializer {
        require(owner != address(0), IValidatorTypes.ZeroAddress());
        __Pausable_init();
        __Ownable_init(owner);
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
    }

    /// @inheritdoc IBridge
    function deposit(DepositParams calldata depositParams)
        external
        payable
        whenNotPaused
        nonReentrant
    {
        require(depositParams.amount > 0, InvalidTransaction());
        require(
            depositParams.destinationChain != CHAIN_ID,
            SameChainTransfer(depositParams.destinationChain)
        );

        if (depositParams.token == address(0)) {
            require(msg.value == depositParams.amount, InvalidTransaction());
        } else {
            IERC20(depositParams.token).safeTransferFrom(
                msg.sender, address(this), depositParams.amount
            );
        }

        DepositParams memory params = DepositParams({
            amount: depositParams.amount,
            token: depositParams.token,
            to: depositParams.to,
            destinationChain: depositParams.destinationChain
        });

        (bytes32 depositRoot, uint256 depositIndex) = _addToDepositTree(params, CHAIN_ID);

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
    function updateValidatorManager(address validatorManager) external override onlyBridge {
        require(validatorManager != address(0), IValidatorTypes.ZeroAddress());
        emit ValidatorManagerUpdated(VALIDATOR_MANAGER, validatorManager);
        VALIDATOR_MANAGER = validatorManager;
    }

    /// @inheritdoc IBridge
    function claim(ClaimParams calldata claimParams) external whenNotPaused {
        require(claimParams.amount > 0, InvalidTransaction());
        require(VALIDATOR_MANAGER != address(0), IValidatorTypes.ZeroAddress());
        require(claimParams.sourceChain != CHAIN_ID, SameChainTransfer(claimParams.sourceChain));
        require(
            !isDepositClaimed(claimParams.sourceChain, claimParams.depositIndex),
            AlreadyClaimed(claimParams.sourceChain, claimParams.depositIndex)
        );
        require(msg.sender == claimParams.to, InvalidTransaction());
        IValidatorTypes.RootParams memory params = IValidatorTypes.RootParams({
            chainId: claimParams.sourceChain,
            bridgeRoot: claimParams.sourceRoot,
            blockNumber: claimParams.blockNumber,
            stateRoot: claimParams.stateRoot
        });
        require(
            IValidatorManager(VALIDATOR_MANAGER).isRootVerified(params),
            InvalidRoot(claimParams.sourceRoot)
        );
        DepositParams memory originalDeposit = DepositParams({
            amount: claimParams.amount,
            token: claimParams.token,
            to: claimParams.to,
            destinationChain: CHAIN_ID
        });

        bytes32 expectedLeaf = LocalExitTreeLib.computeExitLeaf(
            originalDeposit, claimParams.sourceChain, claimParams.depositIndex
        );
        require(
            claimParams.proof.value == expectedLeaf, InvalidMerkleProof(claimParams.depositIndex)
        );
        require(claimParams.proof.existence, InvalidMerkleProof(claimParams.depositIndex));
        require(
            _verifyProofAgainstRoot(claimParams.proof, claimParams.sourceRoot),
            InvalidMerkleProof(claimParams.depositIndex)
        );

        markDepositClaimed(claimParams.sourceChain, claimParams.depositIndex);

        ClaimLeaf memory claimLeaf = ClaimLeaf({
            sourceDepositIndex: claimParams.depositIndex,
            sourceChain: claimParams.sourceChain,
            sourceRoot: claimParams.sourceRoot,
            claimer: msg.sender,
            recipient: claimParams.to,
            amount: claimParams.amount,
            token: claimParams.token,
            timestamp: block.timestamp,
            destinationChain: CHAIN_ID
        });

        (bytes32 claimRoot, uint256 claimIndex) = _addToClaimTree(claimLeaf);

        if (claimParams.token == address(0)) {
            require(
                address(this).balance >= claimParams.amount,
                InsufficientBalance(address(0), claimParams.amount)
            );

            (bool success,) = claimParams.to.call{value: claimParams.amount}("");
            require(success, ClaimFailed(address(0), claimParams.to, claimParams.amount));
        } else {
            IERC20(claimParams.token).safeTransfer(claimParams.to, claimParams.amount);
        }

        emit Claimed(
            msg.sender,
            claimParams.amount,
            claimParams.token,
            claimParams.to,
            claimParams.sourceChain,
            claimParams.depositIndex,
            claimIndex,
            claimParams.sourceRoot,
            claimRoot,
            CHAIN_ID
        );
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
        if (!proof.existence) return false;

        bytes32 computed = proof.value;
        uint256 idx = uint256(proof.key);

        for (uint256 i = 0; i < proof.siblings.length; i++) {
            bytes32 sib = proof.siblings[i];
            if (((idx >> i) & 1) == 1) {
                computed = keccak256(abi.encodePacked(sib, computed));
            } else {
                computed = keccak256(abi.encodePacked(computed, sib));
            }
        }
        return computed == root;
    }

    /// @inheritdoc IBridge
    function rescueEth(uint256 amount, address to) external onlyOwner {
        require(to != address(0), IValidatorTypes.ZeroAddress());
        require(address(this).balance >= amount, InsufficientBalance(address(0), amount));
        (bool success,) = to.call{value: amount}("");
        require(success, FailedToRescueEther());
    }

    /// @inheritdoc IBridge
    function rescueTokens(address token, uint256 amount, address to) external onlyOwner {
        require(token != address(0), IValidatorTypes.ZeroAddress());
        require(to != address(0), IValidatorTypes.ZeroAddress());

        IERC20(token).safeTransfer(to, amount);
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
