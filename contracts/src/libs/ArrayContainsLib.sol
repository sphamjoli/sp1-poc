// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title ArrayContains
/// @author brianspha
/// @notice Library for checking if arrays contain specific elements
/// @dev Provides contains functionality for common Solidity types
library ArrayContainsLib {
    /// @notice Checks if a bytes array contains a specific element
    /// @param array The array to search in
    /// @param element The element to search for
    /// @return True if element exists in array, false otherwise
    function contains(bytes[] memory array, bytes memory element) internal pure returns (bool) {
        uint256 length = array.length;
        for (uint256 i; i < length;) {
            if (keccak256(array[i]) == keccak256(element)) {
                return true;
            }
            unchecked {
                ++i;
            }
        }
        return false;
    }

    /// @notice Checks if a string array contains a specific element
    /// @param array The array to search in
    /// @param element The element to search for
    /// @return True if element exists in array, false otherwise
    function contains(string[] memory array, string memory element) internal pure returns (bool) {
        uint256 length = array.length;
        for (uint256 i; i < length;) {
            if (keccak256(bytes(array[i])) == keccak256(bytes(element))) {
                return true;
            }
            unchecked {
                ++i;
            }
        }
        return false;
    }

    /// @notice Checks if a bytes32 array contains a specific element
    /// @param array The array to search in
    /// @param element The element to search for
    /// @return True if element exists in array, false otherwise
    function contains(bytes32[] memory array, bytes32 element) internal pure returns (bool) {
        uint256 length = array.length;
        for (uint256 i; i < length;) {
            if (array[i] == element) {
                return true;
            }
            unchecked {
                ++i;
            }
        }
        return false;
    }

    /// @notice Checks if an address array contains a specific element
    /// @param array The array to search in
    /// @param element The element to search for
    /// @return True if element exists in array, false otherwise
    function contains(address[] memory array, address element) internal pure returns (bool) {
        uint256 length = array.length;
        for (uint256 i; i < length;) {
            if (array[i] == element) {
                return true;
            }
            unchecked {
                ++i;
            }
        }
        return false;
    }

    /// @notice Checks if a uint256 array contains a specific element
    /// @param array The array to search in
    /// @param element The element to search for
    /// @return True if element exists in array, false otherwise
    function contains(uint256[] memory array, uint256 element) internal pure returns (bool) {
        uint256 length = array.length;
        for (uint256 i; i < length;) {
            if (array[i] == element) {
                return true;
            }
            unchecked {
                ++i;
            }
        }
        return false;
    }

    /// @notice Checks if a uint128 array contains a specific element
    /// @param array The array to search in
    /// @param element The element to search for
    /// @return True if element exists in array, false otherwise
    function contains(uint128[] memory array, uint128 element) internal pure returns (bool) {
        uint256 length = array.length;
        for (uint256 i; i < length;) {
            if (array[i] == element) {
                return true;
            }
            unchecked {
                ++i;
            }
        }
        return false;
    }

    /// @notice Checks if a uint64 array contains a specific element
    /// @param array The array to search in
    /// @param element The element to search for
    /// @return True if element exists in array, false otherwise
    function contains(uint64[] memory array, uint64 element) internal pure returns (bool) {
        uint256 length = array.length;
        for (uint256 i; i < length;) {
            if (array[i] == element) {
                return true;
            }
            unchecked {
                ++i;
            }
        }
        return false;
    }

    /// @notice Checks if a uint32 array contains a specific element
    /// @param array The array to search in
    /// @param element The element to search for
    /// @return True if element exists in array, false otherwise
    function contains(uint32[] memory array, uint32 element) internal pure returns (bool) {
        uint256 length = array.length;
        for (uint256 i; i < length;) {
            if (array[i] == element) {
                return true;
            }
            unchecked {
                ++i;
            }
        }
        return false;
    }

    /// @notice Checks if a uint16 array contains a specific element
    /// @param array The array to search in
    /// @param element The element to search for
    /// @return True if element exists in array, false otherwise
    function contains(uint16[] memory array, uint16 element) internal pure returns (bool) {
        uint256 length = array.length;
        for (uint256 i; i < length;) {
            if (array[i] == element) {
                return true;
            }
            unchecked {
                ++i;
            }
        }
        return false;
    }

    /// @notice Checks if a uint8 array contains a specific element
    /// @param array The array to search in
    /// @param element The element to search for
    /// @return True if element exists in array, false otherwise
    function contains(uint8[] memory array, uint8 element) internal pure returns (bool) {
        uint256 length = array.length;
        for (uint256 i; i < length;) {
            if (array[i] == element) {
                return true;
            }
            unchecked {
                ++i;
            }
        }
        return false;
    }

    /// @notice Checks if an int256 array contains a specific element
    /// @param array The array to search in
    /// @param element The element to search for
    /// @return True if element exists in array, false otherwise
    function contains(int256[] memory array, int256 element) internal pure returns (bool) {
        uint256 length = array.length;
        for (uint256 i; i < length;) {
            if (array[i] == element) {
                return true;
            }
            unchecked {
                ++i;
            }
        }
        return false;
    }

    /// @notice Checks if an int128 array contains a specific element
    /// @param array The array to search in
    /// @param element The element to search for
    /// @return True if element exists in array, false otherwise
    function contains(int128[] memory array, int128 element) internal pure returns (bool) {
        uint256 length = array.length;
        for (uint256 i; i < length;) {
            if (array[i] == element) {
                return true;
            }
            unchecked {
                ++i;
            }
        }
        return false;
    }

    /// @notice Checks if an int64 array contains a specific element
    /// @param array The array to search in
    /// @param element The element to search for
    /// @return True if element exists in array, false otherwise
    function contains(int64[] memory array, int64 element) internal pure returns (bool) {
        uint256 length = array.length;
        for (uint256 i; i < length;) {
            if (array[i] == element) {
                return true;
            }
            unchecked {
                ++i;
            }
        }
        return false;
    }

    /// @notice Checks if an int32 array contains a specific element
    /// @param array The array to search in
    /// @param element The element to search for
    /// @return True if element exists in array, false otherwise
    function contains(int32[] memory array, int32 element) internal pure returns (bool) {
        uint256 length = array.length;
        for (uint256 i; i < length;) {
            if (array[i] == element) {
                return true;
            }
            unchecked {
                ++i;
            }
        }
        return false;
    }

    /// @notice Checks if an int16 array contains a specific element
    /// @param array The array to search in
    /// @param element The element to search for
    /// @return True if element exists in array, false otherwise
    function contains(int16[] memory array, int16 element) internal pure returns (bool) {
        uint256 length = array.length;
        for (uint256 i; i < length;) {
            if (array[i] == element) {
                return true;
            }
            unchecked {
                ++i;
            }
        }
        return false;
    }

    /// @notice Checks if an int8 array contains a specific element
    /// @param array The array to search in
    /// @param element The element to search for
    /// @return True if element exists in array, false otherwise
    function contains(int8[] memory array, int8 element) internal pure returns (bool) {
        uint256 length = array.length;
        for (uint256 i; i < length;) {
            if (array[i] == element) {
                return true;
            }
            unchecked {
                ++i;
            }
        }
        return false;
    }

    /// @notice Checks if a bool array contains a specific element
    /// @param array The array to search in
    /// @param element The element to search for
    /// @return True if element exists in array, false otherwise
    function contains(bool[] memory array, bool element) internal pure returns (bool) {
        uint256 length = array.length;
        for (uint256 i; i < length;) {
            if (array[i] == element) {
                return true;
            }
            unchecked {
                ++i;
            }
        }
        return false;
    }

    /// @notice Checks if a bytes array contains a specific element (calldata version)
    /// @param array The array to search in
    /// @param element The element to search for
    /// @return True if element exists in array, false otherwise
    function containsCalldata(bytes[] calldata array, bytes calldata element) internal pure returns (bool) {
        uint256 length = array.length;
        for (uint256 i; i < length;) {
            if (keccak256(array[i]) == keccak256(element)) {
                return true;
            }
            unchecked {
                ++i;
            }
        }
        return false;
    }

    /// @notice Checks if a string array contains a specific element (calldata version)
    /// @param array The array to search in
    /// @param element The element to search for
    /// @return True if element exists in array, false otherwise
    function containsCalldata(string[] calldata array, string calldata element) internal pure returns (bool) {
        uint256 length = array.length;
        for (uint256 i; i < length;) {
            if (keccak256(bytes(array[i])) == keccak256(bytes(element))) {
                return true;
            }
            unchecked {
                ++i;
            }
        }
        return false;
    }

    /// @notice Checks if an address array contains a specific element (calldata version)
    /// @param array The array to search in
    /// @param element The element to search for
    /// @return True if element exists in array, false otherwise
    function containsCalldata(address[] calldata array, address element) internal pure returns (bool) {
        uint256 length = array.length;
        for (uint256 i; i < length;) {
            if (array[i] == element) {
                return true;
            }
            unchecked {
                ++i;
            }
        }
        return false;
    }

    /// @notice Checks if a uint256 array contains a specific element (calldata version)
    /// @param array The array to search in
    /// @param element The element to search for
    /// @return True if element exists in array, false otherwise
    function containsCalldata(uint256[] calldata array, uint256 element) internal pure returns (bool) {
        uint256 length = array.length;
        for (uint256 i; i < length;) {
            if (array[i] == element) {
                return true;
            }
            unchecked {
                ++i;
            }
        }
        return false;
    }
}
