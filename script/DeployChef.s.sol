// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "forge-std/Script.sol";
import "../src/BountyProxy.sol";
import "../src/BountyProxyFactory.sol";
import "../src/BountyPool.sol";
import "../src/SaloonChef.sol";
import "../src/SaloonWallet.sol";
import "../src/BountyProxiesManager.sol";
import "../src/ManagerProxy.sol";
import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract Deploy is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // bytes memory data = "";
        // BountyProxy bountyProxy = new BountyProxy();
        // BountyProxyFactory proxyFactory = new BountyProxyFactory();
        // UpgradeableBeacon beacon = new UpgradeableBeacon(address(bountyPool));
        address projectwallet = 0x0376e82258Ed00A9D7c6513eC9ddaEac015DEdFc;
        address SUSDC = 0x302dE6226DDc73dF0C3d9c55C9910dEBDdd8AFE6;
        string memory bountyName = "YEEHAW";

        BountyProxiesManager bountyProxiesManager = new BountyProxiesManager();
        bountyProxiesManager.initialize();
        bountyProxiesManager.updateTokenWhitelist(SUSDC, true);
        bountyProxiesManager.deployNewBounty(
            "",
            bountyName,
            SUSDC,
            projectwallet
        );
        address bountyAddress = bountyProxiesManager.getBountyAddressByName(bountyName);
        ERC20(SUSDC).approve(bountyAddress, 10000*(10**6));
        // ERC20(SUSDC).transfer(bountyAddress, 100*(10**6));

        bountyProxiesManager.setBountyCapAndAPY(bountyName, 10000, 10000);


        // ManagerProxy managerProxy = new ManagerProxy(
        //     address(bountyProxiesManager),
        //     data,
        //     msg.sender
        // );
        // BountyProxiesManager manager = BountyProxiesManager(
        //     address(managerProxy)
        // );
        // bountyPool.initializeImplementation(address(managerProxy), 18);
        // manager.initialize(proxyFactory, beacon, address(bountyPool));
        // bountyProxy.initialize(address(beacon), data, address(managerProxy));
        // proxyFactory.initiliaze(
        //     payable(address(bountyProxy)),
        //     address(managerProxy)
        // );
        // // NOTE INTERACT

        // address usdc = 0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d;
        // address projectwallet = 0x84bB382457299Ed13E946529E010ee54Cfa047ab;
        // string memory bountyName = "YEEHAW";
        // manager.updateTokenWhitelist(usdc, true);
        // manager.deployNewBounty("", bountyName, usdc, projectwallet);
        // manager.viewBountyOwner(bountyName);
        // // get new proxy address
        // address bountyAddress = manager.getBountyAddressByName(bountyName);
        // // approve transferFrom
        // ERC20(usdc).approve(bountyAddress, 1000 ether);
        // manager.projectDeposit(bountyName, 100);
        // manager.setBountyCapAndAPY(bountyName, 47, 10000);
        // // manager.viewBountyInfo(bountyName);
        // // manager.viewProjectDeposit(bountyName);
        // // manager.viewBountyBalance(bountyName);
        // // manager.stake(bountyName, 0.01 ether);

        

        vm.stopBroadcast();
    }
}
