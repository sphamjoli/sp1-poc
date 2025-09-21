// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IValidatorTypes} from "./IValidatorTypes.sol";

/// @title ValidatorManagerStorage
/// @notice Abstract storage layer for VM operations
abstract contract ValidatorManagerStorage is IValidatorTypes {
    /// @dev Protects unauthorised calls not made by the ValidatorManager contract
    modifier onlyValidatorManager() {
        require(msg.sender == VALIDATOR_MANAGER, NotValidatorManager());
        _;
    }

    /// @dev Validator Manager storage position
    bytes32 internal constant VM_STORAGE_SLOT =
        bytes32(uint256(keccak256(abi.encodePacked("com.validatorManager.storage"))) - 1);

    /// @dev The bridge contract address
    address public immutable VALIDATOR_MANAGER;

    constructor() {
        VALIDATOR_MANAGER = msg.sender;
    }

    /// @notice Get Validator Manager storage
    /// @return $ Storage struct
    function _loadStorage() internal pure returns (VMStorage storage $) {
        bytes32 position = VM_STORAGE_SLOT;
        assembly {
            $.slot := position
        }
    }

    /// @notice Get Validator Manager storage key
    /// @return Storage position key
    function _getStorageKey() internal pure returns (bytes32) {
        return VM_STORAGE_SLOT;
    }
}
