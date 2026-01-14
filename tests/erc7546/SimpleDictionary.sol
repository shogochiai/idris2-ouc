// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Minimal ERC-7546 Dictionary for testing
contract SimpleDictionary {
    mapping(bytes4 => address) private _implementations;

    function setImplementation(bytes4 selector, address impl) external {
        _implementations[selector] = impl;
    }

    function getImplementation(bytes4 selector) external view returns (address) {
        return _implementations[selector];
    }
}
