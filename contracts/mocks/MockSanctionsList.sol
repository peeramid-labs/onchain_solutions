// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

contract MockSanctionsList {
    mapping(address => bool) private sanctioned;

    function setSanctioned(address account, bool isSanctioned) external {
        sanctioned[account] = isSanctioned;
    }

    function isSanctioned(address account) external view returns (bool) {
        return sanctioned[account];
    }
}
