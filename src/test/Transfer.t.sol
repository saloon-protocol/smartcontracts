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

contract TransferTest is DSTest, Script {
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

        manager.transferOwnership(whitehat);
        proxyFactory.transferOwnership(whitehat);
    }

    function testTransfer() public {
        address mOwner = manager.owner();
        assertEq(mOwner, whitehat);

        address pOwner = proxyFactory.owner();
        assertEq(pOwner, whitehat);
    }
}
