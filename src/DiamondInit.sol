// SPDX-License-Identifier: MIT OR Apache-2.0

pragma solidity ^0.8.0;

import "./lib/Diamond.sol";
import "./Base.sol";

/// @author Matter Labs
/// @dev The contract is used only once to initialize the diamond proxy.
/// @dev The deployment process takes care of this contract's initialization.
contract DiamondInit is Base {
    constructor() reentrancyGuardInitializer {}

    /// @notice zkSync contract initialization
    /// @param _owner address who can manage the contract

    /// @return Magic 32 bytes, which indicates that the contract logic is expected to be used as a diamond proxy initializer
    function initialize(address _owner)
        external
        reentrancyGuardInitializer
        returns (bytes32)
    {
        s.owner = _owner;

        return Diamond.DIAMOND_INIT_SUCCESS_RETURN_VALUE;
    }
}
