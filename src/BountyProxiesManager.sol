//SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

// import "./interfaces/IMIMOProxy.sol";
// import "./interfaces/IBountyProxyFactory.sol";
// import "./interfaces/IMIMOProxyRegistry.sol";
// import "../core/interfaces/IAddressProvider.sol";
// import "../core/interfaces/IAccessController.sol";
// import { CustomErrors } from "../libraries/CustomErrors.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";

//// THOUGHTS:
// Planning to separate this into contracts:
// 1. Registry contract that holds varaibles
// 2. Manager Contract that hold state changing functions and inherits Registry

/// @title MIMOProxyRegistry
contract BountyProxiesManager is Owner {
    /// PUBLIC STORAGE ///

    /// @inheritdoc IMIMOProxyRegistry
    IBountyProxyFactory public factory;

    struct Bounties {
        string projectName;
        address projectWallet;
        address proxyAddress;
        address token;
    }

    Bounties[] public bountiesList;
    // Project name => project auth address => proxy address
    mapping(string => Bounties) public bountyDetails;
    // Token address => approved or not
    mapping(address => bool)  public tokenWhitelist;

    modifier onlyProject() {
        require(msg.sender == projectWallet, "Only Project owner allowed");
        _;
    }

    modifier onlySaloon() {
        require(msg.sender == owner, "Only Saloon allowed");
        _;
    }

    // factory address might not be known at the time of deployment
    /// @param factory_ The base contract of the factory
    constructor(IBountyProxyFactory factory_) {
        factory = factory_;
    }

    ///// DEPLOY NEW BOUNTY //////
    function deployNewBounty(string memory _projectName, address _projectWallet, address _token)
        external
        returns (newProxyAddress)
    {
        // added access control (only owner can deploy new bounty
        // revert if project name already has bounty

        require(tokenWhitelist[_token] == true, "Token not approved");

        Bounties memory newBounty;
        newBounty.projectName = _projectName;
        newBounty.projectWallet = _projectWallet;
        newBounty.token = _token;

        // call factory to deploy bounty
        address newProxyAddress = factory.deployBounty(_projectName, _projectWallet, _token);

        newBounty.proxyAddress = newProxyAddress;

        // Push new bounty to storage array
        bountiesList.push(newBounty);

        // Create new mapping so we can look up bounty details by their name
        bountyDetails[_projectName] = newBounty;

        // update proxyWhitelist in implementation
    }

    ///// KILL BOUNTY ////
    function killBounty() external {
        // exclude proxy from proxyWhitelist
    }

    ////////// VIEW FUNCTIONS ////////////

    // Function to view all bounties name string //

    // Function to view TVL , average APY and remaining  amount to reach total CAP of all pools together //

    // Function to view Total Balance of Pool By Project Name //

    // Function to view Project Deposit to Pool by Project Name //

    // Function to view Total Staker Balance of Pool By Project Name //

    // Function to view individual Staker Balance in Pool by Project Name //

    // Function to find bounty proxy and wallet address by Name
    function getBountyAddressByName(string memory _projectName) external view returns () {}

    ////    VIEW FUNCTIONS END  ///////

    ///// PUBLIC PAY PREMIUM FOR ONE BOUNTY
    function collectPremiumForOnePool(string memory _projectName) external returns(bool) {
        // check if premium has already been paid
        if (bountyDetails){
            // if it hasnt pay premium
            bountiesList[i].proxyAddress.payPremium()
            return true;
        }
        return false;


    }
    ///// PUBLIC PAY PREMIUM FOR ALL BOUNTIES
    function collectPremiumForAll() external returns(bool) {
        for(i; i < bountiesList.length;) {

            // check if premium has been paid
            if {
                // if it hasnt pay premium
                bountiesList[i].proxyAddress.payPremium()
            }
            

            unchecked {
                ++i
            }
        }

        return true;
        

    }
    // skip premiums that have already been paid

    /// ADMIN WITHDRAWAL FROM POOL  TO PAY BOUNTY ///

    /// ADMIN CHANNGE IMPLEMENTATION ADDRESS of UPGRADEABLEBEACON ///

    /// ADMIN UPDATE APPROVED TOKENS ///

    /// ADMIN CHANGE ASSIGNED TOKEN TO BOUNTY ///

    //////// PROJECTS FUNCTION TO CHANGE APY and CAP by NAME/////
    // time locked
    // fails if msg.sender != project owner
    function setBountyCapAndAPY() external {
        // look for project address
        // require msg.sender == projectWAllet
        // set cap
        
        // set APY
    }

    /////// PROJECTS FUNCTION TO DEPOSIT INTO POOL by NAME///////
    // fails if msg.sender != project owner
    function projectDeposit(
        string memory _projectName,
        uint256 _amount
    ) external returns (bool) {
        Bounties memory bounty = bountyDetails[_projectName];

        require(msg.sender == bounty.projectWallet, "Not project owner");
        require(msg.sender == bounty.token, "Token not assigned");
        // check if token is same as assigned to project
        
        

        if (bounty.proxyAddress.bountyDeposit(_amount)) {
            return true;
        }
    }

    /////// PROJECT FUNCTION TO WITHDRAWAL FROM POOL  by PROJECT NAME/////
    // time locked
    // fails if msg.sender != project owner

    ////// STAKER FUNCTION TO STAKE INTO POOL by PROJECT NAME//////

    ////// STAKER FUNCTION TO STAKE INTO GLOBAL POOL??????????? //////

    ////// STAKER FUNCTION TO WITHDRAWAL FROM POOL ///////
    // time locked
}
