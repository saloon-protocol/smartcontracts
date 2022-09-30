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

contract BountyInteract is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        bytes memory data = "";
        address wmatic = 0x9c3C9283D3e44854697Cd22D3Faa240Cfb032889;
        // @audit INSERT YOUR OWN BELOW
        address projectwallet = 0x0376e82258Ed00A9D7c6513eC9ddaEac015DEdFc;
        address managerAddress = 0xbA2C02d5c59238d5607aDcbc277c80a51694e73F;
        BountyProxiesManager manager = BountyProxiesManager(managerAddress);
        string memory bountyName = "TestBounty2";
        manager.deployNewBounty(data, bountyName, wmatic, projectwallet);
        address bountyAddress = manager.getBountyAddressByName(bountyName);

        // CAN PROBABLY COMMENT THIS OUT IF TESTING WITH SAME BOUNTY
        ERC20(wmatic).approve(bountyAddress, 100 ether);

        // FEEL FREE TO DELETE/ADD ANY FUNCTION BELOW
        manager.projectDeposit(bountyName, 0.1 ether);
        manager.setBountyCapAndAPY(bountyName, 0.5 ether, 100 ether);
        manager.viewBountyInfo(bountyName);
        manager.viewProjectDeposit(bountyName);
        manager.viewBountyBalance(bountyName);
        vm.stopBroadcast();
    }
}
