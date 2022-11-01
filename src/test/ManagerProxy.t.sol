// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "ds-test/test.sol";
import "forge-std/Script.sol";
import "forge-std/Script.sol";
import "../../src/BountyProxy.sol";
import "../../src/BountyPool.sol";
import "../../src/SaloonWallet.sol";
import "../../src/BountyProxiesManager.sol";
import "../../src/ManagerProxy.sol";

// import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

// import "solmate/tokens/WETH.sol";

contract ManagerProxyTest is DSTest, Script {
    bytes data = "";
    BountyProxy bountyProxy;
    BountyProxyFactory proxyFactory;
    BountyPool bountyPool;
    UpgradeableBeacon beacon;
    BountyProxiesManager bountyProxiesManager;
    ManagerProxy managerProxy;
    BountyProxiesManager manager;
    SaloonWallet saloonwallet;

    address wmatic = 0x9c3C9283D3e44854697Cd22D3Faa240Cfb032889;
    address projectwallet = address(1);
    address investor = address(2);
    address investor2 = address(4);
    address whitehat = address(3);
    address owner = 0xb4c79daB8f259C7Aee6E5b2Aa729821864227e84;
    string bountyName = "YEEHAW";
    address bountyAddress;

    function setUp() external {
        string memory mumbai = vm.envString("MUMBAI_RPC_URL");
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        uint256 forkId = vm.createFork(mumbai);
        vm.selectFork(forkId);

        vm.deal(projectwallet, 500 ether);
        vm.deal(investor, 500 ether);
        vm.deal(investor2, 500 ether);

        bountyProxy = new BountyProxy();
        proxyFactory = new BountyProxyFactory();
        bountyPool = new BountyPool();
        beacon = new UpgradeableBeacon(address(bountyPool));
        bountyProxiesManager = new BountyProxiesManager();

        managerProxy = new ManagerProxy(
            address(bountyProxiesManager),
            data,
            msg.sender
        );

        saloonwallet = new SaloonWallet(address(managerProxy));
        manager = BountyProxiesManager(address(managerProxy));
        // transfer Beacon ownership to saloon
        beacon.transferOwnership(address(manager));
        // bountyPool.initializeImplementation(address(managerProxy), 18);
        manager.initialize(proxyFactory, beacon, address(bountyPool));
        // bountyProxy.initialize(address(beacon), data, address(managerProxy));
        proxyFactory.initiliaze(
            payable(address(bountyProxy)),
            address(managerProxy)
        );
        manager.updateSaloonWallet(address(saloonwallet));
        manager.updateTokenWhitelist(address(wmatic), true);
        manager.deployNewBounty("", bountyName, address(wmatic), projectwallet);
        bountyAddress = manager.getBountyAddressByName(bountyName);
    }

    function testManager() public {
        vm.startPrank(projectwallet);
        ERC20(wmatic).approve(bountyAddress, 1000 ether);
        wmatic.call{value: 40 ether}(abi.encodeWithSignature("deposit()", ""));

        ///////// test init project setting up ////////////
        manager.projectDeposit(bountyName, 20);
        uint256 projectDeposit = manager.viewProjectDeposit(bountyName);
        assertEq(20 ether, projectDeposit);

        manager.scheduleProjectDepositWithdrawal(bountyName, 5);

        manager.setBountyCapAndAPY(bountyName, 5000, 10);

        uint256 payout = manager.viewHackerPayout(bountyName);
        assertEq(18 ether, payout);

        vm.warp(block.timestamp + 8 days);
        manager.projectDepositWithdrawal(bountyName, 5);

        uint256 projectDeposit2 = manager.viewProjectDeposit(bountyName);
        assertEq(15 ether, projectDeposit2);

        manager.scheduleProjectDepositWithdrawal(bountyName, 5);
        vm.warp(block.timestamp + 8 days);
        manager.projectDepositWithdrawal(bountyName, 5);

        uint256 projectDeposit3 = manager.viewProjectDeposit(bountyName);
        assertEq(10 ether, projectDeposit3);

        vm.stopPrank();
        ///////// test init project setting up  END ////////////

        //// TEST UPGRADE MANAGER ////
        BountyProxiesManager newImplementation = new BountyProxiesManager();
        manager.upgradeTo(address(newImplementation));
        /////////////////////////////////////////////

        ///////// test stake, billPremium and claimPremium///////////
        vm.startPrank(investor);
        wmatic.call{value: 80 ether}(abi.encodeWithSignature("deposit()", ""));

        ERC20(wmatic).approve(bountyAddress, 1000 ether);
        manager.stake(bountyName, 20);

        vm.warp(block.timestamp + 52 weeks);
        manager.billPremiumForOnePool(bountyName);
        // uint256 payout2 = manager.viewHackerPayout(bountyName);
        // assertEq(31.5, payout2);

        vm.warp(block.timestamp);
        manager.claimPremium(bountyName);

        manager.scheduleUnstake(bountyName, 5); //

        vm.warp(block.timestamp + 8 days);
        manager.unstake(bountyName, 5);
        vm.stopPrank();

        // test bill premium for one pool
        // warp x and bill
        vm.warp(block.timestamp + 52 weeks);
        manager.billPremiumForOnePool(bountyName);

        // test first claim premium as investor

        vm.warp(block.timestamp);
        vm.startPrank(investor);
        manager.claimPremium(bountyName);

        manager.scheduleUnstake(bountyName, 15); //

        vm.warp(block.timestamp + 8 days);
        manager.unstake(bountyName, 15);
        vm.stopPrank();

        vm.warp(block.timestamp + 200 weeks);
        vm.startPrank(investor);
        manager.claimPremium(bountyName);
        vm.stopPrank();
        ///////// test stake, billPremium and claimPremium END ///////////

        ///////// test payBounty ////////////////////////////////////////////
        uint256 balance = manager.viewBountyBalance(bountyName);
        assertEq(balance, 1);
        // test payBounty
        manager.payBounty(bountyName, whitehat, 10);
        uint256 whitehatBalance = ERC20(wmatic).balanceOf(whitehat);
        // check hunters balance is correct
        assertEq(whitehatBalance, 9 ether);
        // check saloon balance is correct
        uint256 saloonBalance = ERC20(wmatic).balanceOf(address(saloonwallet));
        assertEq(saloonBalance, 1 ether);
        uint256 saloonLocal = manager.viewSaloonBalance();
        assertEq(saloonLocal, 1 ether);

        // uint256 totalDeposit = manager.viewProjectDeposit(bountyName);

        manager.withdrawSaloon(wmatic, projectwallet, 1);
        // assertEq(totalDeposit,);
        // uint256 managerBalance2 = ERC20(wmatic).balanceOf(address(manager));
        // assertEq(managerBalance2, 1);

        // should fail (working)
        // manager.payBounty(bountyName, whitehat, 9);
        ///////// test payBounty END ////////////////////////////////////////////

        /////////test payout with multiple stakers covering it /////////////////
        vm.startPrank(investor2);
        wmatic.call{value: 80 ether}(abi.encodeWithSignature("deposit()", ""));

        ERC20(wmatic).approve(bountyAddress, 1000 ether);
        manager.stake(bountyName, 10);
        vm.stopPrank();

        vm.startPrank(investor);
        ERC20(wmatic).approve(bountyAddress, 1000 ether);
        manager.stake(bountyName, 50);
        vm.stopPrank();

        uint256 balance2 = manager.viewBountyBalance(bountyName);
        // assertEq(balance2, 1);

        manager.payBounty(bountyName, whitehat, 50);

        uint256 investorDeposit = manager.viewUserStakingBalance(
            bountyName,
            investor
        );
        assertEq(investorDeposit, 0);
        uint256 investorDeposit2 = manager.viewUserStakingBalance(
            bountyName,
            investor2
        );
        assertEq(investorDeposit2, 0);
        ///////////////////// END  ///////////////////////////////////

        ////////////// test mixed payout (stakers and project) ////////////////////////////////////
        vm.startPrank(projectwallet);
        wmatic.call{value: 80 ether}(abi.encodeWithSignature("deposit()", ""));

        ERC20(wmatic).approve(bountyAddress, 1000 ether);
        manager.projectDeposit(bountyName, 20);
        vm.stopPrank();

        vm.startPrank(investor);
        manager.stake(bountyName, 5);
        vm.stopPrank();

        vm.startPrank(investor2);
        manager.stake(bountyName, 10);
        vm.stopPrank();

        manager.payBounty(bountyName, whitehat, 32);
        uint256 totalDeposit2 = manager.viewProjectDeposit(bountyName);
        assertEq(totalDeposit2, 13 ether);
        uint256 stakersDeposit2 = manager.viewstakersDeposit(bountyName);
        assertEq(stakersDeposit2, 0);
        uint256 investorDeposit6 = manager.viewUserStakingBalance(
            bountyName,
            investor2
        );
        assertEq(investorDeposit6, 0);
        ///////////////////// END  ///////////////////////////////////

        ///////////// test payout with no stakers //////////////////////////
        manager.payBounty(bountyName, whitehat, 13);
        // should fail (working)
        // manager.payBounty(bountyName, whitehat, 1);

        // test decrease pool cap
        vm.startPrank(projectwallet);
        manager.schedulePoolCapChange(bountyName, 100);
        vm.warp(block.timestamp + 2 weeks);
        manager.setPoolCap(bountyName, 100);
        vm.stopPrank();
        ///////////////////// END  ///////////////////////////////////

        ////////////// / test increase pool cap //////////////////////////
        vm.startPrank(projectwallet);
        manager.schedulePoolCapChange(bountyName, 200);
        vm.warp(block.timestamp + 2 weeks);
        manager.setPoolCap(bountyName, 200);
        uint256 poolCap = manager.viewPoolCap(bountyName);
        assertEq(poolCap, 200 ether);
        vm.stopPrank();
        ///////////////////// END  ///////////////////////////////////

        /////////////// test decrease pool cap when full //////////////////////////
        vm.startPrank(projectwallet);
        wmatic.call{value: 150 ether}(abi.encodeWithSignature("deposit()", ""));
        manager.projectDeposit(bountyName, 100);
        vm.stopPrank();

        vm.startPrank(investor);
        wmatic.call{value: 150 ether}(abi.encodeWithSignature("deposit()", ""));
        manager.stake(bountyName, 100);
        vm.stopPrank();

        vm.startPrank(investor2);
        wmatic.call{value: 150 ether}(abi.encodeWithSignature("deposit()", ""));
        manager.stake(bountyName, 100);
        vm.stopPrank();

        vm.startPrank(projectwallet);
        manager.schedulePoolCapChange(bountyName, 100);
        vm.warp(block.timestamp + 2 weeks);
        manager.setPoolCap(bountyName, 100);
        uint256 poolCap2 = manager.viewPoolCap(bountyName);
        assertEq(poolCap2, 100 ether);
        vm.stopPrank();
        // - testing reimbursement
        // note this is returning slightly more 50. Timestamps in this test
        // must make it so "investor" already claimed his share in past tests but no "investor2"
        vm.startPrank(investor2);
        manager.claimPremium(bountyName);
        vm.stopPrank();

        vm.startPrank(investor);

        manager.claimPremium(bountyName);
        vm.stopPrank();

        uint256 investorDeposit3 = manager.viewUserStakingBalance(
            bountyName,
            investor
        );
        assertEq(investorDeposit3, 50 ether);
        uint256 investorDeposit4 = manager.viewUserStakingBalance(
            bountyName,
            investor2
        );
        assertEq(investorDeposit4, 50 ether);
        // ///////////////////// END  ///////////////////////////////////

        // ///////////////// test decrease apy /////////////////////////
        vm.startPrank(projectwallet);
        manager.scheduleAPYChange(bountyName, 20);
        vm.warp(block.timestamp + 2 weeks);
        manager.setAPY(bountyName, 20);
        uint256 apy = manager.viewDesiredAPY(bountyName);
        assertEq(apy, 20 ether);
        vm.stopPrank();
        manager.billPremiumForOnePool(bountyName);
        ///////////////////// END  ///////////////////////////////////

        // ////////////////// test increase apy /////////////////////////
        // vm.startPrank(projectwallet);
        // manager.scheduleAPYChange(bountyName, 100);
        // vm.warp(block.timestamp + 2 weeks);
        // manager.setAPY(bountyName, 100);
        // uint256 apy2 = manager.viewDesiredAPY(bountyName);
        // assertEq(apy2, 100 ether);
        // vm.stopPrank();
        // ///////////////////// END  ///////////////////////////////////

        // ////////////////// test collect saloon premium /////////////////////////
        // manager.withdrawSaloonPremiumFees();
        // uint256 saloonBalance2 = ERC20(wmatic).balanceOf(address(saloonwallet));
        // // assertEq(saloonBalance2, 0);
        // ///////////////////// END  ///////////////////////////////////

        // ////////////////// test Upgrade Bountypool contract ///////////////////////////////////
        // BountyPool newBountyPool = new BountyPool();
        // vm.prank(owner);
        // manager.updateBountyPoolImplementation(address(newBountyPool));
        // // note: currently no way of transferring ownership from Manager to anyone else.
        // ///////////////////// END  ///////////////////////////////////

        // ////////////////// project wallet can’t be billed fully causing APY change ///////////////////////////////////
        // vm.warp(block.timestamp + 200000 weeks);
        // vm.startPrank(investor2);
        // manager.claimPremium(bountyName);
        // vm.stopPrank();

        // uint256 apy3 = manager.viewDesiredAPY(bountyName);
        // assertEq(apy3, 100 ether);
        ///////////////////// END  ///////////////////////////////////

        //todo test bill premium for all
        // warp x and bill
    }
}
