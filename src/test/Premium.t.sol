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

contract PremiumTest is DSTest, Script {
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

    function testPremium() public {
        vm.startPrank(projectwallet);
        ERC20(wmatic).approve(bountyAddress, 1000 ether);
        wmatic.call{value: 100 ether}(abi.encodeWithSignature("deposit()", ""));

        manager.projectDeposit(bountyName, 20);
        uint256 projectDeposit = manager.viewProjectDeposit(bountyName);
        assertEq(20 ether, projectDeposit);
        manager.setBountyCapAndAPY(bountyName, 5000, 10);
        vm.stopPrank();

        vm.startPrank(investor);
        wmatic.call{value: 80 ether}(abi.encodeWithSignature("deposit()", ""));

        ERC20(wmatic).approve(bountyAddress, 1000 ether);
        vm.warp(block.timestamp + 2 weeks);
        manager.stake(bountyName, 20);
        vm.stopPrank();

        vm.warp(block.timestamp + 52 weeks);
        manager.billPremiumForOnePool(bountyName);

        vm.warp(block.timestamp + 2 weeks);
        manager.billPremiumForOnePool(bountyName);

        // vm.startPrank(projectwallet);
        // manager.scheduleAPYChange(bountyName, 20);
        // vm.warp(block.timestamp + 2 weeks);
        // manager.setAPY(bountyName, 20);
        // vm.stopPrank();
        // uint256 apy = manager.viewDesiredAPY(bountyName);
        // assertEq(apy, 20 ether);
        // vm.warp(block.timestamp + 52 weeks);
        // manager.billPremiumForOnePool(bountyName);

        vm.startPrank(projectwallet);
        vm.warp(block.timestamp + 52 weeks);
        manager.scheduleAPYChange(bountyName, 5);
        vm.warp(block.timestamp + 2 weeks);
        manager.setAPY(bountyName, 5);
        vm.stopPrank();

        vm.startPrank(projectwallet);
        vm.warp(block.timestamp + 104 weeks);
        manager.scheduleAPYChange(bountyName, 10);
        vm.warp(block.timestamp + 2 weeks);
        manager.setAPY(bountyName, 10);
        vm.stopPrank();

        vm.warp(block.timestamp + 156 weeks);
        manager.billPremiumForOnePool(bountyName);
    }
}
