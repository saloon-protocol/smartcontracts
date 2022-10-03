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

import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

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
    address projectwallet = 0x0376e82258Ed00A9D7c6513eC9ddaEac015DEdFc;
    string bountyName = "YEEHAW";

    // manager.updateTokenWhitelist(wmatic, true);
    // manager.deployNewBounty("", bountyName, wmatic, projectwallet);
    // // get new proxy address
    // address bountyAddress = manager.getBountyAddressByName(bountyName);
    // // approve transferFrom
    // ERC20(wmatic).approve(bountyAddress, 100 ether);
    // manager.projectDeposit(bountyName, 0.1 ether);
    // manager.setBountyCapAndAPY(bountyName, 0.5 ether, 100 ether);
    // manager.viewBountyInfo(bountyName);
    // manager.viewProjectDeposit(bountyName);
    // manager.viewBountyBalance(bountyName);
    // manager.stake(bountyName, 0.01 ether);

    function setUp() external {
        string memory mumbai = vm.envString("MUMBAI_RPC_URL");
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        uint256 forkId = vm.createFork(mumbai);
        vm.selectFork(forkId);
        vm.deal(projectwallet, 100 ether);
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
        bountyProxy.initialize(address(beacon), data, address(managerProxy));
        proxyFactory.initiliaze(
            payable(address(bountyProxy)),
            address(managerProxy)
        );
    }

    // function testExample() public {

    //     assertTrue(manager.updateTokenWhitelist(address(wmatic), true));

    //     manager.deployNewBounty("", bountyName, address(wmatic), projectwallet);

    //     address bountyAddress = manager.getBountyAddressByName(bountyName);

    //     vm.startPrank(projectwallet);
    //     ERC20(wmatic).approve(bountyAddress, 100 ether);
    //     manager.projectDeposit(bountyName, 0.1 ether);
    //     manager.setBountyCapAndAPY(bountyName, 0.5 ether, 100 ether);
    //     vm.stopPrank();
    //     manager.viewBountyInfo(bountyName);
    //     manager.viewProjectDeposit(bountyName);
    //     manager.viewBountyBalance(bountyName);
    //     manager.stake(bountyName, 0.01 ether);
    //     // assertTrue(true);
    // }
}
