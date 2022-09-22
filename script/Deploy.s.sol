// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "forge-std/Script.sol";
import "../src/BountyProxy.sol";
import "../src/BountyProxyFactory.sol";
import "../src/IBountyProxyFactory.sol";

import "../src/SaloonWallet.sol";
import "../src/BountyPool.sol";
// import "../src/UpgradeableBeacon.sol";
import "../src/BountyProxiesManager.sol";
import "../src/ManagerProxy.sol";

contract MyScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        bytes memory data = "";
        BountyProxy bountyProxy = new BountyProxy();
        BountyProxyFactory proxyFactory = new BountyProxyFactory();
        BountyPool bountyPoool = new BountyPool();
        UpgradeableBeacon beacon = new UpgradeableBeacon(address(bountyPoool));
        BountyProxiesManager bountyProxiesManager = new BountyProxiesManager(
            proxyFactory,
            beacon,
            address(bountyPoool)
        );
        ManagerProxy managerProxy = new ManagerProxy(
            address(bountyProxiesManager),
            data,
            msg.sender
        );
        bountyPoool.initialize(address(managerProxy));
        bountyProxy.initialize(address(beacon), data, address(managerProxy));
        proxyFactory.initiliaze(
            payable(address(bountyProxy)),
            address(managerProxy)
        );

        vm.stopBroadcast();
    }
}
