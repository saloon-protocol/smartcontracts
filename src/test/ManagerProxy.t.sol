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
    // address projectwallet = address(1);
    address projectwallet = 0x0376e82258Ed00A9D7c6513eC9ddaEac015DEdFc;
    address investor = address(1);
    address whitehat = address(2);
    address owner = 0xb4c79daB8f259C7Aee6E5b2Aa729821864227e84;
    string bountyName = "YEEHAW";
    address bountyAddress;

    function setUp() external {
        string memory mumbai = vm.envString("MUMBAI_RPC_URL");
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        uint256 forkId = vm.createFork(mumbai);
        vm.selectFork(forkId);

        vm.deal(projectwallet, 100 ether);
        vm.deal(investor, 100 ether);

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
        bountyPool.initializeImplementation(address(managerProxy));
        manager.initialize(proxyFactory, beacon, address(bountyPool));
        // // //@audit does it still work if I initialize the proxyBase??? or does it affect all else
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
        ERC20(wmatic).approve(bountyAddress, 100 ether);
        wmatic.call{value: 30 ether}(abi.encodeWithSignature("deposit()", ""));

        manager.projectDeposit(bountyName, 20 ether);
        manager.setBountyCapAndAPY(bountyName, 5000 ether, 10 ether);
        manager.scheduleProjectDepositWithdrawal(bountyName, 5 ether);
        uint256 payout = manager.viewHackerPayout(bountyName);
        assertEq(18 ether, payout);
        vm.warp(block.timestamp + 3 weeks);
        manager.projectDepositWithdrawal(bountyName, 5 ether);

        vm.stopPrank();

        //// TEST UPGRADE MANAGER ////
        BountyProxiesManager newImplementation = new BountyProxiesManager();
        manager.upgradeTo(address(newImplementation));
        /////////

        manager.viewBountyInfo(bountyName);
        manager.viewProjectDeposit(bountyName);
        manager.viewBountyBalance(bountyName);

        ///////// INVESTOR ///////////
        vm.startPrank(investor);
        wmatic.call{value: 80 ether}(abi.encodeWithSignature("deposit()", ""));

        ERC20(wmatic).approve(bountyAddress, 100 ether);
        manager.stake(bountyName, 20 ether);
        // uint256 payout2 = manager.viewHackerPayout(bountyName);
        // assertEq(31.5 ether, payout2);
        // assertEq()
        manager.scheduleUnstake(bountyName, 5 ether); // NOTE OR THIS

        vm.warp(block.timestamp + 4 weeks);
        manager.unstake(bountyName, 5 ether);
        vm.stopPrank();
        ///////// INVESTOR END ///////////

        // uint256 payout3 = manager.viewHackerPayout(bountyName);
        // assertEq(27 ether, payout3);

        // test bill premium for one pool
        // warp x and bill
        // vm.warp(block.timestamp + 50 weeks);
        // manager.billPremiumForOnePool(bountyName);

        // test first claim premium as investor
        // warp is not cummulative....
        // NOTE: for some reason if I call billPremium before this event it doesnt work.
        // TODO: Test on Live testnet to make sure this is only a mistake with the testing set up
        vm.warp(block.timestamp + 100 weeks);
        vm.startPrank(investor);
        manager.claimPremium(bountyName);
        vm.stopPrank();

        // test second claim premium as investor

        // test payBounty
        // bounty should have 30 ethers by this point
        // manager.payBounty(bountyName, whitehat, 20 ether);
        // uint256 whitehatBalance = ERC20(wmatic).balanceOf(whitehat);
        // // check hunters balance is correct
        // assertEq(18 ether, whitehatBalance);
        // // check saloon balance is correct
        // uint256 saloonBalance = ERC20(wmatic).balanceOf(address(saloonwallet));
        // assertEq(2 ether, saloonBalance);

        // test collect saloon premium
        // assert how much premium saloonwallet has

        // test bill premium for all
        // warp x and bill

        // test Upgrade Bountypool contract

        // test Upgrade factory contract

        // test upgrade maanger contract
    }
}
