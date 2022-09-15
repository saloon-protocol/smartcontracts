// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.4;

import "openzeppelin-contracts/contracts/proxy/Clones.sol";
import "./BountyProxy.sol";
import "./IBountyProxyFactory.sol";
import "./BountyPool.sol";

// import "./interfaces/IMIMOProxy.sol";
// import "./interfaces/IMIMOProxyFactory.sol";
// import "./MIMOProxy.sol";

// contract BountyProxyFactory is IMIMOProxyFactory {
contract BountyProxyFactory {
    using Clones for address;
    /// PUBLIC STORAGE ///

    address payable public immutable bountyProxyBase;

    address public immutable manager;

    uint256 public constant VERSION = 1;

    /// INTERNAL STORAGE ///

    /// @dev Internal mapping to track all deployed proxies.
    mapping(address => bool) internal _proxies;

    constructor(address payable _bountyProxyBase, address _manager) {
        bountyProxyBase = _bountyProxyBase;
        manager = _manager;
    }

    modifier onlyManager() {
        require(msg.sender == manager, "Only manager allowed");
        _;
    }

    function deployBounty(
        address _beacon,
        address _projectWallet,
        bytes memory _data
    ) public onlyManager returns (BountyPool bountyPool) {
        address payable proxy = payable(Clones.clone(bountyProxyBase));

        BountyProxy newBounty = BountyProxy(proxy);
        BountyPool bountyPool = BountyPool(proxy);
        newBounty.initialize(_beacon, _data, msg.sender);
    }
}
