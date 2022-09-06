// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.4;

// import "./interfaces/IMIMOProxy.sol";
// import "./interfaces/IMIMOProxyFactory.sol";
// import "./interfaces/IMIMOProxyRegistry.sol";
// import "../core/interfaces/IAddressProvider.sol";
// import "../core/interfaces/IAccessController.sol";
// import { CustomErrors } from "../libraries/CustomErrors.sol";

/// @title MIMOProxyRegistry
contract BountyProxyRegistry is IBountyProxyRegistry {
    /// PUBLIC STORAGE ///

    /// @inheritdoc IMIMOProxyRegistry
    IBountyProxyFactory public override factory;

    _currentProxies[] public proxiesRegister;

    /// INTERNAL STORAGE ///

    /// @notice Internal mapping of projects address to current proxies.
    mapping(address => IBountyProxy) internal _currentProxies;

    /// CONSTRUCTOR ///

    /// @param factory_ The base contract of the factory
    constructor(IBountyProxyFactory factory_) {
        factory = factory_;
    }

    ///// DEPLOY NEW BOUNTY //////
    function deployBounty(address projectsAddress, string projectsName)
        public
        override
        returns (IMIMOProxy proxy)
    {
        IMIMOProxy currentProxy = _currentProxies[owner];

        // Do not deploy if the proxy already exists and the owner is the same.
        if (
            address(currentProxy) != address(0) && currentProxy.owner() == owner
        ) {
            revert CustomErrors.PROXY_ALREADY_EXISTS(owner);
        }

        // Deploy the proxy via the factory.
        proxy = factory.deployFor(owner);

        // increment proxies Register by one and add make it equal to this mapping

        // @audit This should be its own function
        // Set or override the current proxy for the owner.
        _currentProxies[owner] = IMIMOProxy(proxy);
    }

    ////////// VIEW FUNCTIONS ////////////

    // Function to view all bounties name string //

    // Function to view TVL of all pools together //

    // Function to view Total Balance of Pool By Project Name //

    // Function to view Project Deposit to Pool by Project Name //

    // Function to view Total Staker Balance of Pool By Project Name //

    // Function to view individual Staker Balance in Pool by Project Name //

    // Function to find bounty proxy and wallet address by Name
    function getBountyAddressesByName(address owner)
        external
        view
        override
        returns (IMIMOProxy proxy)
    {
        proxy = _currentProxies[owner];
    }

    ////    VIEW FUNCTIONS END  ///////

    //////// PROJECTS FUNCTION TO CHANGE APY /////
    // time locked
    // fails if msg.sender != project owner

    /////// PROJECTS FUNCTION TO DEPOSIT INTO POOL ///////
    // fails if msg.sender != project owner

    /////// PROJECT FUNCTION TO WITHDRAWAL FROM POOL /////
    // time locked
    // fails if msg.sender != project owner

    ////// STAKER FUNCTION TO STAKE INTO POOL//////

    ////// STAKER FUNCTION TO WITHDRAWAL FROM POOL ///////
    // time locked
}
