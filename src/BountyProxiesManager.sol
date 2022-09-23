//SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

// import "./interfaces/IMIMOProxy.sol";
// import "./interfaces/IBountyProxyFactory.sol";
// import "./interfaces/IMIMOProxyRegistry.sol";
// import "../core/interfaces/IAddressProvider.sol";
// import "../core/interfaces/IAccessController.sol";
// import { CustomErrors } from "../libraries/CustomErrors.sol";
import "./SaloonWallet.sol";
import "./BountyProxyFactory.sol";
import "./IBountyProxyFactory.sol";
import "./BountyPool.sol";

import "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "openzeppelin-contracts/contracts/proxy/utils/UUPSUpgradeable.sol";
import "openzeppelin-contracts/contracts/proxy/beacon/UpgradeableBeacon.sol";

//// THOUGHTS:
// Planning to separate this into contracts:
// 1. Registry contract that holds varaibles
// 2. Manager Contract that hold state changing functions and inherits Registry

contract BountyProxiesManager is OwnableUpgradeable, UUPSUpgradeable {
    /// PUBLIC STORAGE ///

    event DeployNewBounty(
        address indexed sender,
        address indexed _projectWallet,
        BountyPool newProxyAddress
    );

    // should this be a constant?
    BountyProxyFactory public factory;
    UpgradeableBeacon public beacon;
    address public bountyImplementation;
    SaloonWallet public saloonWallet;

    struct Bounties {
        string projectName;
        address projectWallet;
        BountyPool proxyAddress;
        address token;
        bool dead;
    }

    Bounties[] public bountiesList;
    // Project name => project auth address => proxy address
    mapping(string => Bounties) public bountyDetails;
    // Token address => approved or not
    mapping(address => bool) public tokenWhitelist;

    function notDead(bool _isDead) internal pure returns (bool) {
        // if notDead is false return bounty is live(true)
        return _isDead == false ? true : false;
    }

    // factory address might not be known at the time of deployment
    /// @param _factory The base contract of the factory
    // constructor(
    //     BountyProxyFactory factory_,
    //     UpgradeableBeacon _beacon,
    //     address _bountyImplementation
    // ) {
    //     factory = factory_;
    //     beacon = _beacon;
    //     bountyImplementation = _bountyImplementation;
    // }
    function initialize(
        BountyProxyFactory _factory,
        UpgradeableBeacon _beacon,
        address _bountyImplementation
    ) public initializer {
        factory = _factory;
        beacon = _beacon;
        bountyImplementation = _bountyImplementation;
        __Ownable_init();
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        virtual
        override
        onlyOwner
    {}

    //////// UPDATE SALOON WALLET FOR HUNTER PAYOUTS ////// done
    function updateSaloonWallet(address _newWallet) external onlyOwner {
        require(_newWallet != address(0), "Address cant be zero");
        saloonWallet = SaloonWallet(_newWallet);
    }

    //////// WITHDRAW FROM SALOON WALLET ////// done
    function withdrawSaloon(
        address _token,
        address _to,
        uint256 _amount
    ) external onlyOwner returns (bool) {
        require(_to != address(0), "Address Zero");
        saloonWallet.withdrawSaloonFunds(_token, _to, _amount);
        return true;
    }

    ///// DEPLOY NEW BOUNTY ////// done
    function deployNewBounty(
        bytes memory _data,
        string memory _projectName,
        address _token,
        address _projectWallet
    ) external onlyOwner returns (BountyPool, bool) {
        // revert if project name already has bounty
        require(
            bountyDetails[_projectName].proxyAddress == BountyPool(address(0)),
            "Project already has bounty"
        );

        require(tokenWhitelist[_token] == true, "Token not approved");

        Bounties memory newBounty;
        newBounty.projectName = _projectName;
        newBounty.projectWallet = _projectWallet;
        newBounty.token = _token;

        // call factory to deploy bounty
        BountyPool newProxyAddress = factory.deployBounty(
            address(beacon),
            _data
        );
        newProxyAddress.initializeImplementation(address(this));

        newBounty.proxyAddress = newProxyAddress;

        // Push new bounty to storage array
        bountiesList.push(newBounty);

        // Create new mapping so we can look up bounty details by their name
        bountyDetails[_projectName] = newBounty;

        //  NOT NEEDED  update proxyWhitelist in implementation
        // bountyImplementation.updateProxyWhitelist(newProxyAddress, true);
        emit DeployNewBounty(msg.sender, _projectWallet, newProxyAddress);

        return (newProxyAddress, true);
    }

    ///// KILL BOUNTY ////
    function killBounty(string memory _projectName)
        external
        onlyOwner
        returns (bool)
    {
        // attempt to withdraw all money?
        // call (currently non-existent) pause function?
        // look up address by name
        bountyDetails[_projectName].dead = true;

        return true;
    }

    ///// PUBLIC PAY PREMIUM FOR ONE BOUNTY // done
    // todo cache variables for gas efficiency
    function billPremiumForOnePool(string memory _projectName)
        external
        returns (bool)
    {
        // check if active
        require(
            notDead(bountyDetails[_projectName].dead) == true,
            "Bounty is Dead"
        );
        // bill
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
        uint256 length = bountiesArray.length;
        // iterate through all bounty proxies
        for (uint256 i; i < length; ++i) {
            // collect the premium fees from bounty
            if (notDead(bountiesArray[i].dead) == true) {
                continue; // killed bounties are supposed to be skipped.
            }
            bountiesArray[i].proxyAddress.billFortnightlyPremium(
                bountiesArray[i].token,
                bountiesArray[i].projectWallet
            );
        }
        return true;
    }

    /// ADMIN WITHDRAWAL FROM POOL  TO PAY BOUNTY /// done
    function payBounty(
        string memory _projectName,
        address _hunter,
        uint256 _amount
    ) external onlyOwner returns (bool) {
        require(
            notDead(bountyDetails[_projectName].dead) == true,
            "Bounty is Dead"
        );
        bountyDetails[_projectName].proxyAddress.payBounty(
            bountyDetails[_projectName].token,
            address(saloonWallet),
            _hunter,
            _amount
        );
        // update saloonWallet variables
        saloonWallet.bountyPaid(
            bountyDetails[_projectName].token,
            _hunter,
            _amount
        );
        return true;
    }

    /// ADMIN CLAIM PREMIUM FEES for ALL BOUNTIES/// done
    function withdrawSaloonPremiumFees() external onlyOwner returns (bool) {
        // cache bounty bounties listt
        Bounties[] memory bountiesArray = bountiesList;
        uint256 length = bountiesArray.length;
        // iterate through all bounty proxies
        for (uint256 i; i < length; ++i) {
            if (notDead(bountiesArray[i].dead) == true) {
                continue; // killed bounties are supposed to be skipped.
            }
            // collect the premium fees from bounty
            uint256 totalCollected = bountiesArray[i]
                .proxyAddress
                .collectSaloonPremiumFees(
                    bountiesArray[i].token,
                    address(saloonWallet)
                );

            saloonWallet.premiumFeesCollected(
                bountiesArray[i].token,
                totalCollected
            );
        }
        return true;
    }

    /// ADMIN update BountyPool IMPLEMENTATION ADDRESS of UPGRADEABLEBEACON /// done
    function updateBountyPoolImplementation(address _newImplementation)
        external
        onlyOwner
        returns (bool)
    {
        require(_newImplementation != address(0), "Address zero");
        beacon.upgradeTo(_newImplementation);

        return true;
    }

    ///????????????? ADMIN CHANGE ASSIGNED TOKEN TO BOUNTY /// ????????

    /// ADMIN UPDATE APPROVED TOKENS /// done
    function updateTokenWhitelist(address _token, bool whitelisted)
        external
        onlyOwner
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

        // check if active
        require(notDead(bounty.dead) == true, "Bounty is Dead");

        // require msg.sender == projectWallet
        require(msg.sender == bounty.projectWallet, "Not project owner");

        // set cap
        bounty.proxyAddress.setPoolCap(_poolCap);
        // set APY
        bounty.proxyAddress.setDesiredAPY(
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
        // check if active
        require(notDead(bounty.dead) == true, "Bounty is Dead");

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

        // check if active
        require(notDead(bounty.dead) == true, "Bounty is Dead");

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

        // check if active
        require(notDead(bounty.dead) == true, "Bounty is Dead");

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

        // check if active
        require(notDead(bounty.dead) == true, "Bounty is Dead");
        bounty.proxyAddress.stake(bounty.token, msg.sender, _amount);

        return true;
    }

    ////// STAKER FUNCTION TO SCHEDULE UNSTAKE FROM POOL /////// done
    function scheduleUnstake(string memory _projectName, uint256 _amount)
        external
        returns (bool)
    {
        Bounties memory bounty = bountyDetails[_projectName];

        // check if active
        require(notDead(bounty.dead) == true, "Bounty is Dead");

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

        // check if active
        require(notDead(bounty.dead) == true, "Bounty is Dead");

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

        // check if active
        require(notDead(bounty.dead) == true, "Bounty is Dead");

        (uint256 premiumClaimed, ) = bounty.proxyAddress.claimPremium(
            bounty.token,
            msg.sender,
            bounty.projectWallet
        );

        return premiumClaimed;
    }

    // ??????????/  STAKER FUNCTION TO STAKE INTO GLOBAL POOL??????????? //////

    ///////////////////////// VIEW FUNCTIONS //////////////////////

    // Function to view all bounties name string // done
    function viewAllBountiesByName() external view returns (Bounties[] memory) {
        return bountiesList;
    }

    //?????? Function to view TVL , average APY and remaining  amount to reach total CAP of all pools together //

    // Function to view Total Balance of Pool By Project Name // done
    function viewBountyPayout(string memory _projectName)
        external
        view
        returns (uint256)
    {
        Bounties memory bounty = bountyDetails[_projectName];
        return bounty.proxyAddress.viewHackerPayout();
    }

    // Function to view Project Deposit to Pool by Project Name // done
    function viewProjectDeposit(string memory _projectName)
        external
        view
        returns (uint256)
    {
        Bounties memory bounty = bountyDetails[_projectName];
        return bounty.proxyAddress.viewProjecDeposit();
    }

    // Function to view Total Staker Balance of Pool By Project Name // done
    function viewstakersDeposit(string memory _projectName)
        external
        view
        returns (uint256)
    {
        Bounties memory bounty = bountyDetails[_projectName];
        return bounty.proxyAddress.viewStakersDeposit();
    }

    // Function to view individual Staker Balance in Pool by Project Name // done
    function viewUserStakingBalance(string memory _projectName)
        external
        view
        returns (uint256)
    {
        Bounties memory bounty = bountyDetails[_projectName];
        (uint256 stakingBalance, ) = bounty.proxyAddress.viewUserStakingBalance(
            msg.sender
        );
        return stakingBalance;
    }

    // Function to find bounty proxy and wallet address by Name // done
    function getBountyAddressByName(string memory _projectName)
        external
        view
        returns (address)
    {
        return address(bountyDetails[_projectName].proxyAddress);
    }

    function viewBountyOwner(string memory _projectName)external
        view
        returns (address)
    {
        return address(bountyDetails[_projectName].projectWallet);
    }

    function viewSaloonBalance() external view returns (uint256) {
        return saloonWallet.viewSaloonBalance();
    }

    function viewTotalEarnedSaloon() external view returns (uint256) {
        return saloonWallet.viewTotalEarnedSaloon();
    }

    function viewTotalHackerPayouts() external view returns (uint256) {
        return saloonWallet.viewTotalHackerPayouts();
    }

    function viewHunterTotalTokenPayouts(address _token, address _hunter)
        external
        view
        returns (uint256)
    {
        return saloonWallet.viewHunterTotalTokenPayouts(_token, _hunter);
    }

    function viewTotalSaloonCommission() external view returns (uint256) {
        return saloonWallet.viewTotalSaloonCommission();
    }

    function viewTotalPremiums() external view returns (uint256) {
        return saloonWallet.viewTotalPremiums();
    }

    ///////////////////////    VIEW FUNCTIONS END  ////////////////////////
}
