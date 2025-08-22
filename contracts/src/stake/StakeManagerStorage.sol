// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {StakeManagerTypes} from "./StakeManagerTypes.sol";

/// @title StakeManagerStorage
/// @notice Abstract storage layer for Staking operations
abstract contract StakeManagerStorage is StakeManagerTypes {
    /// @dev Protects unauthorised calls not made by the ValidatorManager contract
    modifier onlyStakeManager() {
        require(msg.sender == STAKE_MANAGER, NotStakeManager());
        _;
    }

    /// @dev StakeManager storage position
    bytes32 internal constant SM_STORAGE_SLOT =
        bytes32(uint256(keccak256(abi.encodePacked("com.stakeManager.storage"))) - 1);

    /// @dev The StakeManager contract address
    address public immutable STAKE_MANAGER;

    constructor() {
        STAKE_MANAGER = msg.sender;
    }

    /// @notice Get StakeManager storage
    /// @return $ Storage struct
    function __loadStorage() internal pure returns (SMStorage storage $) {
        bytes32 position = SM_STORAGE_SLOT;
        assembly {
            $.slot := position
        }
    }

    /// @notice Get StakeManager storage key
    /// @return Storage position key
    function __getStorageKey() internal pure returns (bytes32) {
        return SM_STORAGE_SLOT;
    }
}
