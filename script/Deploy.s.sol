// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "forge-std/Script.sol";
import "../src/BountyProxy.sol";
import "../src/BountyProxyFactory.sol";
import "../src/BountyPool.sol";
import "../src/SaloonWallet.sol";
import "../src/BountyProxiesManager.sol";
import "../src/ManagerProxy.sol";
import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract MyScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        bytes memory data = "";
        BountyProxy bountyProxy = new BountyProxy();
        BountyProxyFactory proxyFactory = new BountyProxyFactory();
        BountyPool bountyPool = new BountyPool();
        UpgradeableBeacon beacon = new UpgradeableBeacon(address(bountyPool));
        BountyProxiesManager bountyProxiesManager = new BountyProxiesManager();
        ManagerProxy managerProxy = new ManagerProxy(
            address(bountyProxiesManager),
            data,
            msg.sender
        );
        BountyProxiesManager manager = BountyProxiesManager(
            address(managerProxy)
        );
        // @audit initialize baseProxy just so it doesnt end in wrong hands
        bountyPool.initializeImplementation(address(managerProxy));
        manager.initialize(proxyFactory, beacon, address(bountyPool));
        //@audit does it still work if I initialize the proxyBase??? or does it affect all else
        bountyProxy.initialize(address(beacon), data, address(managerProxy));
        proxyFactory.initiliaze(
            payable(address(bountyProxy)),
            address(managerProxy)
        );
        address wmatic = 0x9c3C9283D3e44854697Cd22D3Faa240Cfb032889;
        address projectwallet = 0x0376e82258Ed00A9D7c6513eC9ddaEac015DEdFc;

        manager.updateTokenWhitelist(wmatic, true);
        manager.deployNewBounty("", "YEEHAW", wmatic, projectwallet);
        // get new proxy address
        address bountyAddress = manager.getBountyAddressByName("YEEHAW");
        // approve transferFrom
        ERC20(wmatic).approve(bountyAddress, 100 ether);
        manager.projectDeposit("YEEHAW", 0.1 ether);
        vm.stopBroadcast();
    }
}
