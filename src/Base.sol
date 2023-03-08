// SPDX-License-Identifier: MIT OR Apache-2.0

pragma solidity ^0.8.0;

import "./Storage.sol";
import "./ReentrancyGuard.sol";

/// @title Base contract containing functions accessible to the other facets.
/// @author Matter Labs
contract Base is ReentrancyGuard {
    AppStorage internal s;

    /// @notice Checks that the message sender is owner
    modifier onlyOwner() {
        require(msg.sender == s.owner, "not owner"); // only by owner
        _;
    }
}
