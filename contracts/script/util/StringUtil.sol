// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @title StringUtil
/// @notice Utility library for string operations and conversions
/// @dev Provides common string manipulation functions for deployment scripts
library StringUtil {
    /// @notice Converts a uint256 to its ASCII string decimal representation
    /// @param value The integer value to convert
    /// @return result The string representation of the value
    function toString(uint256 value) internal pure returns (string memory result) {
        if (value == 0) {
            return "0";
        }

        uint256 temp = value;
        uint256 digits;

        while (temp != 0) {
            digits++;
            temp /= 10;
        }

        bytes memory buffer = new bytes(digits);

        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }

        return string(buffer);
    }
}
