// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "forge-std/Script.sol";
import "../src/SaloonProxy.sol";
import "../src/Saloon.sol";
import "openzeppelin-contracts/contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";

contract Deploy is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        ERC20PresetFixedSupply USDC = ERC20PresetFixedSupply(0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d); // Mainnet
        address projectWallet = 0x84bB382457299Ed13E946529E010ee54Cfa047ab; // Mainnet
        // address projectWallet = 0x1B7FE02Da6c7a7175a33D109397492c2872c6A5e; // Testnet
        bytes memory data = "";

        Saloon saloonImplementation = new Saloon();
        SaloonProxy saloonProxy = new SaloonProxy(address(saloonImplementation), data);
        Saloon saloon = Saloon(address(saloonProxy));
        saloon.initialize();

        // // START TESTNET
        // ERC20PresetFixedSupply USDC = new ERC20PresetFixedSupply("Saloon USDC", "SUSDC", 10000000 ether, projectWallet);
        // // END TESTNET

        saloon.updateTokenWhitelist(address(USDC), true);
        USDC.approve(address(saloonProxy), 1000 ether);
        uint256 pid = saloon.addNewBountyPool(address(USDC), projectWallet, "Saloon");
        saloon.setAPYandPoolCapAndDeposit(pid, 10000 ether, 4700, 0 ether);

        vm.stopBroadcast();
    }
}