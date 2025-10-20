// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IStakeManagerTypes} from "../stake/IStakeManager.sol";

/// @title ArrayContainsLib
/// @author brianspha
/// @notice Gas-optimised library for checking array membership using assembly
/// @dev Experimental implementation - not audited for production use
/// @dev All functions use assembly for direct memory access and reduced gas consumption
library ArrayContainsLib {
    /// @notice Checks if bytes array contains element using keccak256 comparison
    /// @dev Uses assembly for optimised iteration, hashes compared for equality
    /// @param array Array to search
    /// @param element Element to find
    /// @return found True if element exists, false otherwise
    function contains(
        bytes[] memory array,
        bytes memory element
    )
        internal
        pure
        returns (bool found)
    {
        assembly {
            let elLen := mload(element)
            let elHash := keccak256(add(element, 0x20), elLen)
            let p := add(array, 0x20)
            let end := add(p, shl(5, mload(array)))

            for {} lt(p, end) { p := add(p, 0x20) } {
                let it := mload(p)
                if eq(mload(it), elLen) {
                    if eq(keccak256(add(it, 0x20), elLen), elHash) {
                        found := 1
                        p := end
                    }
                }
            }
        }
    }

    /// @notice Checks if string array contains element using keccak256 comparison
    /// @dev Converts strings to bytes for hashing, uses assembly for iteration
    /// @param array Array to search
    /// @param element Element to find
    /// @return found True if element exists, false otherwise
    function contains(
        string[] memory array,
        string memory element
    )
        internal
        pure
        returns (bool found)
    {
        assembly {
            let elLen := mload(element)
            let elHash := keccak256(add(element, 0x20), elLen)
            let p := add(array, 0x20)
            let end := add(p, shl(5, mload(array)))

            for {} lt(p, end) { p := add(p, 0x20) } {
                let it := mload(p)
                if eq(mload(it), elLen) {
                    if eq(keccak256(add(it, 0x20), elLen), elHash) {
                        found := 1
                        p := end
                    }
                }
            }
        }
    }

    /// @notice Checks if bytes32 array contains element
    /// @dev Direct comparison without hashing, assembly-optimised loop
    /// @param array Array to search
    /// @param element Element to find
    /// @return found True if element exists, false otherwise
    function contains(bytes32[] memory array, bytes32 element) internal pure returns (bool found) {
        assembly {
            let p := add(array, 0x20)
            let end := add(p, shl(5, mload(array)))
            for {} lt(p, end) { p := add(p, 0x20) } {
                if eq(mload(p), element) {
                    found := 1
                    p := end
                }
            }
        }
    }

    /// @notice Checks if address array contains element
    /// @dev Direct comparison, eliminates bounds checking via assembly
    /// @param array Array to search
    /// @param element Element to find
    /// @return found True if element exists, false otherwise
    function contains(address[] memory array, address element) internal pure returns (bool found) {
        assembly {
            let p := add(array, 0x20)
            let end := add(p, shl(5, mload(array)))
            for {} lt(p, end) { p := add(p, 0x20) } {
                if eq(mload(p), element) {
                    found := 1
                    p := end
                }
            }
        }
    }

    /// @notice Checks if uint256 array contains element
    /// @dev Assembly-optimised for reduced gas cost
    /// @param array Array to search
    /// @param element Element to find
    /// @return found True if element exists, false otherwise
    function contains(uint256[] memory array, uint256 element) internal pure returns (bool found) {
        assembly {
            let p := add(array, 0x20)
            let end := add(p, shl(5, mload(array)))
            for {} lt(p, end) { p := add(p, 0x20) } {
                if eq(mload(p), element) {
                    found := 1
                    p := end
                }
            }
        }
    }

    /// @notice Checks if IStakeManagerTypes.SlashParams memory array contains element
    /// @dev Direct memory comparison via assembly
    /// @param array Array to search
    /// @param element Element to find
    /// @return found True if element exists, false otherwise
    function contains(
        IStakeManagerTypes.SlashParams[] memory array,
        IStakeManagerTypes.SlashParams memory element
    )
        internal
        pure
        returns (bool found)
    {
        assembly {
            let validator := mload(element)
            let slashAmount := mload(add(element, 0x20))
            let p := add(array, 0x20)
            let end := add(p, mul(mload(array), 0x40))

            for {} lt(p, end) { p := add(p, 0x40) } {
                if and(eq(mload(p), validator), eq(mload(add(p, 0x20)), slashAmount)) {
                    found := 1
                    p := end
                }
            }
        }
    }

    /// @notice Checks if IStakeManagerTypes.SlashParams calldata array contains element
    /// @dev Direct calldata comparison via assembly
    /// @param array Array to search
    /// @param element Element to find
    /// @return found True if element exists, false otherwise
    function containsCalldata(
        IStakeManagerTypes.SlashParams[] calldata array,
        IStakeManagerTypes.SlashParams calldata element
    )
        internal
        pure
        returns (bool found)
    {
        assembly {
            let validator := calldataload(element)
            let slashAmount := calldataload(add(element, 0x20))
            let p := add(array.offset, 0x20)
            let end := add(p, mul(array.length, 0x40))

            for {} lt(p, end) { p := add(p, 0x40) } {
                if and(eq(calldataload(p), validator), eq(calldataload(add(p, 0x20)), slashAmount))
                {
                    found := 1
                    p := end
                }
            }
        }
    }

    /// @dev Direct memory comparison via assembly
    /// @param array Array to search
    /// @param element Element to find
    /// @return found True if element exists, false otherwise
    function contains(
        IStakeManagerTypes.SlashParams[] memory array,
        address element
    )
        internal
        pure
        returns (bool found)
    {
        assembly {
            let p := add(array, 0x20)
            let end := add(p, shl(6, mload(array)))

            for {} lt(p, end) { p := add(p, 0x40) } {
                if eq(mload(p), element) {
                    found := 1
                    p := end
                }
            }
        }
    }

    /// @notice Checks if element calldata array contains element
    /// @dev Direct calldata comparison via assembly
    /// @param array Array to search
    /// @param element Element to find
    /// @return found True if element exists, false otherwise
    function containsCalldata(
        IStakeManagerTypes.SlashParams[] calldata array,
        address element
    )
        internal
        pure
        returns (bool found)
    {
        assembly {
            let p := add(array.offset, 0x20)
            let end := add(p, shl(6, array.length))

            for {} lt(p, end) { p := add(p, 0x40) } {
                if eq(calldataload(p), element) {
                    found := 1
                    p := end
                }
            }
        }
    }
}
