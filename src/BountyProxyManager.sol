// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.4;

// import "./interfaces/IMIMOProxy.sol";
// import "./interfaces/IMIMOProxyFactory.sol";
// import "./interfaces/IMIMOProxyRegistry.sol";
// import "../core/interfaces/IAddressProvider.sol";
// import "../core/interfaces/IAccessController.sol";
// import { CustomErrors } from "../libraries/CustomErrors.sol";

/// @title MIMOProxyRegistry
contract BountyProxyManager is IBountyProxyRegistry {
    /// PUBLIC STORAGE ///

    /// @inheritdoc IMIMOProxyRegistry
    IBountyProxyFactory public override factory;

    struct Addresses {
        string projectName;
        address projectWallet;
        address proxyAddress;
    }

    Addresses[] public bountiesList;
    // Project name => project auth address => proxy address
    mapping(string => Addresses) public nameToBounty;

    /// @param factory_ The base contract of the factory
    constructor(IBountyProxyFactory factory_) {
        factory = factory_;
    }

    ///// DEPLOY NEW BOUNTY //////
    function deployNewBounty(string memory _projectName, address _projectWallet)
        public
    {
        // added access control (only owner can deploy new bounty
        // revert if project name already has bounty

        Addresses memory newBounty;
        newBounty.projectName = _projectName;
        newBounty.projectWallet = _projectWallet;

        // call factory to deploy bounty
        _proxyAddress = factory.deployBounty();

        newBounty.proxyAddress = _proxyAddress;

        // Push new bounty to storage array
        bountiesList.push(newBounty);

        // Create new mapping so we can look up bounty details by their name
        nameToBounty[_projectName] = newBounty;
    }

    ////////// VIEW FUNCTIONS ////////////

    // Function to view all bounties name string //

    // Function to view TVL , average APY and remaining  amount to reach total CAP of all pools together //

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

    /// ADMIN WITHDRAWAL FROM POOL  TO PAY BOUNTY ///

    //////// PROJECTS FUNCTION TO CHANGE APY by NAME/////
    // time locked
    // fails if msg.sender != project owner

    //////// PROJECTS FUNCTION TO CHANGE CAP by NAME/////
    // time locked
    // fails if msg.sender != project owner

    /////// PROJECTS FUNCTION TO DEPOSIT INTO POOL by NAME///////
    // fails if msg.sender != project owner

    /////// PROJECT FUNCTION TO WITHDRAWAL FROM POOL  by PROJECT NAME/////
    // time locked
    // fails if msg.sender != project owner

    ////// STAKER FUNCTION TO STAKE INTO POOL by PROJECT NAME//////

    ////// STAKER FUNCTION TO WITHDRAWAL FROM POOL ///////
    // time locked
}
