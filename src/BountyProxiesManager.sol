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
    IBountyProxyFactory public immutable factory;
    // should this be a constant?
    address public immutable beacon;
    address public immutable bountyImplementation;

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
    mapping(address => bool) public tokenWhitelist;

    // Probably exclude this
    // function onlyProject(string memory _projectName) {
    //     require(msg.sender == projectWallet, "Only Project owner allowed");
    // }

    modifier onlySaloon() {
        require(msg.sender == owner, "Only Saloon allowed");
        _;
    }

    // factory address might not be known at the time of deployment
    /// @param factory_ The base contract of the factory
    constructor(
        IBountyProxyFactory factory_,
        address beacon,
        address _bountyImplementation
    ) {
        factory = factory_;
        beacon = _beacon;
        bountyImplementation = _bountyImplementation;
    }

    ///// DEPLOY NEW BOUNTY ////// done
    function deployNewBounty(bytes memory _data)
        external
        onlySaloon
        returns (address, bool)
    {
        // revert if project name already has bounty
        require(bountyDetails[_projectName] == 0, "Project already has bounty");

        require(tokenWhitelist[_token] == true, "Token not approved");

        Bounties memory newBounty;
        newBounty.projectName = _projectName;
        newBounty.projectWallet = _projectWallet;
        newBounty.token = _token;

        // call factory to deploy bounty
        address newProxyAddress = factory.deployBounty(beacon, _data);

        newBounty.proxyAddress = newProxyAddress;

        // Push new bounty to storage array
        bountiesList.push(newBounty);

        // Create new mapping so we can look up bounty details by their name
        bountyDetails[_projectName] = newBounty;

        // update proxyWhitelist in implementation
        bountyImplementation.updateProxyWhitelist(newProxyAddress, true);

        return (newProxyAddress, true);
    }

    ///// KILL BOUNTY //// done
    function killBounty(string memory _projectName)
        external
        onlySaloon
        returns (bool)
    {
        // attempt to withdraw all money?
        // call (currently non-existent) pause function?
        // look up address by name
        Bounties memory bounty = bountyDetails[_projectName];
        // exclude proxy from proxyWhitelist in bounty implementation
        bountyImplementation.updateProxyWhitelist(bounty.proxyAddress, false);

        return true;
    }

    ////////// TODO VIEW FUNCTIONS ////////////

    // Function to view all bounties name string //
    function viewAllBountiesByName() external view returns (Bounties[]) {
        return bountiesList; //done
    }

    // Function to view TVL , average APY and remaining  amount to reach total CAP of all pools together //

    // Function to view Total Balance of Pool By Project Name //

    // Function to view Project Deposit to Pool by Project Name //

    // Function to view Total Staker Balance of Pool By Project Name //

    // Function to view individual Staker Balance in Pool by Project Name //

    //TODO  Function to find bounty proxy and wallet address by Name
    function getBountyAddressByName(string memory _projectName)
        external
        view
        returns (bool)
    {}

    ///////////////////////    VIEW FUNCTIONS END  ////////////////////////

    ///// PUBLIC PAY PREMIUM FOR ONE BOUNTY // done
    function billPremiumForOnePool(string memory _projectName)
        external
        returns (bool)
    {
        bountyDetails[_projectName].proxyAddress.billFortnightlyPremium(
            bountyDetails[_projectName].token,
            bountyDetails[_projectName].projectWallet
        );
        return true;
    }

    ///// PUBLIC PAY PREMIUM FOR ALL BOUNTIES // done
    function billPremiumForAll() external returns (bool) {
        // cache bounty bounties listt
        Bounties[] memory bountiesArray = bountiesList;
        uint256 length = bountiesArray.length();
        // iterate through all bounty proxies
        for (uint256 i; i < length; ++i) {
            // collect the premium fees from bounty
            bountiesArray[i].proxyAddress.billFortnightlyPremium(
                bountiesArray[i].token,
                bountiesArray[i].projectWallet
            );
        }
        return true;
    }

    /// ADMIN WITHDRAWAL FROM POOL  TO PAY BOUNTY /// done
    function payHackerBounty(
        string memory _projectName,
        address _hunter,
        uint256 _amount
    ) external onlySaloon returns (bool) {
        bountyDetails[_projectName].proxyAddress.payBounty(
            bountyDetails[_projectName].token,
            _hunter,
            _amount
        );
        return true;
    }

    /// ADMIN CLAIM PREMIUM FEES for ALL BOUNTIES/// done
    function withdrawSaloonPremiumFees() external onlySaloon returns (bool) {
        // cache bounty bounties listt
        Bounties[] memory bountiesArray = bountiesList;
        uint256 length = bountiesArray.length();
        // iterate through all bounty proxies
        for (uint256 i; i < length; ++i) {
            // collect the premium fees from bounty
            bountiesArray[i].proxyAddress.collectSaloonPremiumFees(
                bountiesArray[i].token
            );
        }
        return true;
    }

    /// TODO ADMIN update BountyPool IMPLEMENTATION ADDRESS of UPGRADEABLEBEACON ///

    ///????????????? ADMIN CHANGE ASSIGNED TOKEN TO BOUNTY /// ????????

    /// ADMIN UPDATE APPROVED TOKENS /// done
    function updateTokenWhitelist(address _token, address whitelisted)
        external
        onlySaloon
        returns (bool)
    {
        tokenWhitelist[_token] = whitelisted;
    }

    //////// PROJECTS FUNCTION TO CHANGE APY and CAP by NAME///// done
    // time locked
    // fails if msg.sender != project owner
    function setBountyCapAndAPY(
        string memory _projectName,
        uint256 _poolCap,
        uint256 _desiredAPY
    ) external returns (bool) {
        // look for project address
        Bounties memory bounty = bountyDetails[_projectName];

        // require msg.sender == projectWallet
        require(msg.sender == bounty.projectWallet, "Not project owner");

        // set cap
        bounty.proxyAddress.setPoolCap(_poolCap);
        // set APY
        bounty.proxyAddress.desiredAPY(
            bounty.token,
            bounty.projectWallet,
            _desiredAPY
        );

        return true;
    }

    /////// PROJECTS FUNCTION TO DEPOSIT INTO POOL by NAME/////// done
    function projectDeposit(string memory _projectName, uint256 _amount)
        external
        returns (bool)
    {
        Bounties memory bounty = bountyDetails[_projectName];
        // check if msg.sender is allowed
        require(msg.sender == bounty.projectWallet, "Not project owner");
        // do deposit
        bounty.proxyAddress.bountyDeposit(
            bounty.token,
            bounty.projectWallet,
            _amount
        );

        return true;
    }

    /////// PROJECT FUNCTION TO SCHEDULE WITHDRAW FROM POOL  by PROJECT NAME///// done
    function scheduleProjectDepositWithdrawal(
        string memory _projectName,
        uint256 _amount
    ) external returns (bool) {
        // cache bounty
        Bounties memory bounty = bountyDetails[_projectName];

        // check if caller is project
        require(msg.sender == bounty.projectWallet, "Not project owner");

        // schedule withdrawal
        bounty.proxyAddress.scheduleprojectDepositWithdrawal(_amount);

        return true;
    }

    /////// PROJECT FUNCTION TO WITHDRAW FROM POOL  by PROJECT NAME///// done
    function projectDepositWithdrawal(
        string memory _projectName,
        uint256 _amount
    ) external returns (bool) {
        // cache bounty
        Bounties memory bounty = bountyDetails[_projectName];

        // check if caller is project
        require(msg.sender == bounty.projectWallet, "Not project owner");

        // schedule withdrawal
        bounty.proxyAddress.projectDepositWithdrawal(
            bounty.token,
            bounty.projectWallet,
            _amount
        );

        return true;
    }

    ////// STAKER FUNCTION TO STAKE INTO POOL by PROJECT NAME////// done
    function stake(string memory _projectName, uint256 _amount)
        external
        returns (bool)
    {
        Bounties memory bounty = bountyDetails[_projectName];
        bounty.proxyAddress.stake(bounty.token, msg.sender, _amount);

        return true;
    }

    ////// STAKER FUNCTION TO SCHEDULE UNSTAKE FROM POOL /////// done
    function scheduleUnstake(string memory _projectName, uint256 _amount)
        external
        returns (bool)
    {
        Bounties memory bounty = bountyDetails[_projectName];

        //todo should all these function check return value like this?
        if (bounty.proxyAddress.askForUnstake(msg.sender, _amount)) {
            return true;
        }
    }

    ////// STAKER FUNCTION TO UNSTAKE FROM POOL /////// done
    function unstake(string memory _projectName, uint256 _amount)
        external
        returns (bool)
    {
        Bounties memory bounty = bountyDetails[_projectName];

        if (bounty.proxyAddress.unstake(bounty.token, msg.sender, _amount)) {
            return true;
        }
    }

    ///// STAKER FUNCTION TO CLAIM PREMIUM by PROJECT NAME////// done
    function claimPremium(string memory _projectName)
        external
        returns (uint256)
    {
        Bounties memory bounty = bountyDetails[_projectName];

        uint256 premiumClaimed = bounty.proxyAddress.claimPremium(
            bounty.token,
            msg.sender
        );

        return premiumClaimed;
    }

    // ??????????/  STAKER FUNCTION TO STAKE INTO GLOBAL POOL??????????? //////
}
