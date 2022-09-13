// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.4;

import "@openzeppelin/contracts/proxy/Clones.sol";

import "./interfaces/IMIMOProxy.sol";
import "./interfaces/IMIMOProxyFactory.sol";
import "./MIMOProxy.sol";

/// @title MIMOProxyFactory
/// @notice Used to make clones of MIMOProxy for each user
contract MIMOProxyFactory is IMIMOProxyFactory {
    using Clones for address;
    /// PUBLIC STORAGE ///

    address public immutable mimoProxyBase;

    address public immutable manager;

    /// @inheritdoc IMIMOProxyFactory
    uint256 public constant override VERSION = 1;

    /// INTERNAL STORAGE ///

    /// @dev Internal mapping to track all deployed proxies.
    mapping(address => bool) internal _proxies;

    constructor(address _mimoProxyBase, address _manager) {
        mimoProxyBase = _mimoProxyBase;
        manager = _manager;
    }

    modifier onlyManager() {
        require(msg.sender == manager, "Only manager allowed");
        _;
    }

    /// PUBLIC CONSTANT FUNCTIONS ///

    /// @inheritdoc IMIMOProxyFactory
    function isProxy(address proxy)
        external
        view
        override
        returns (bool result)
    {
        result = _proxies[proxy];
    }

    /// PUBLIC NON-CONSTANT FUNCTIONS ///

    // /// @inheritdoc IMIMOProxyFactory
    // function deploy() external override returns (IMIMOProxy proxy) {
    //     proxy = deployFor(msg.sender);
    // }

    // @audit This should only be callable by the Registry
    /// @inheritdoc IMIMOProxyFactory
    function deployBounty(address _beacon, bytes memory _data)
        public
        override
        onlyManager
        returns (IMIMOProxy proxy)
    {
        proxy = IBountyProxy(mimoProxyBase.clone());
        proxy.initialize(_beacon, _data, msg.sender);

        // Transfer the ownership from this factory contract to the specified owner.

        // Mark the proxy as deployed.
        _proxies[address(proxy)] = true;

        // Log the proxy via en event.
        emit DeployProxy(msg.sender, owner, address(proxy));
    }
}
