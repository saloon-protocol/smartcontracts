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

    address wmatic = 0x9c3C9283D3e44854697Cd22D3Faa240Cfb032889;
    // address projectwallet = address(1);
    address projectwallet = 0x0376e82258Ed00A9D7c6513eC9ddaEac015DEdFc;
    address investor = address(1);
    address owner = 0xb4c79daB8f259C7Aee6E5b2Aa729821864227e84;
    string bountyName = "YEEHAW";

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
        manager = BountyProxiesManager(address(managerProxy));
    }

    function testInitContracts() public {
        bountyPool.initializeImplementation(address(managerProxy));
        manager.initialize(proxyFactory, beacon, address(bountyPool));
        // // //@audit does it still work if I initialize the proxyBase??? or does it affect all else
        // bountyProxy.initialize(address(beacon), data, address(managerProxy));
        proxyFactory.initiliaze(
            payable(address(bountyProxy)),
            address(managerProxy)
        );
        manager.updateTokenWhitelist(address(wmatic), true);
        manager.deployNewBounty("", bountyName, address(wmatic), projectwallet);
        address bountyAddress = manager.getBountyAddressByName(bountyName);

        vm.startPrank(projectwallet);
        ERC20(wmatic).approve(bountyAddress, 100 ether);
        wmatic.call{value: 80 ether}(abi.encodeWithSignature("deposit()", ""));
        manager.projectDeposit(bountyName, 20 ether);
        manager.setBountyCapAndAPY(bountyName, 5000 ether, 20 ether);
        vm.stopPrank();

        manager.viewBountyInfo(bountyName);
        manager.viewProjectDeposit(bountyName);
        manager.viewBountyBalance(bountyName);

        vm.startPrank(investor);
        wmatic.call{value: 80 ether}(abi.encodeWithSignature("deposit()", ""));

        ERC20(wmatic).approve(bountyAddress, 100 ether);
        manager.stake(bountyName, 20 ether);
        manager.scheduleUnstake(bountyName, 20 ether);
        vm.stopPrank();
    }

    function testDeployandUpdateBBounty() public {
        assertTrue(true);
    }
}
