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

        ERC20PresetFixedSupply USDC = ERC20PresetFixedSupply(
            0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d
        ); // Mainnet
        address saloon = 0x5088CE3706104d36DD3083B63e98b162C3f89A38;
        Saloon saloonProxy = Saloon(saloon);

        uint256 pid = saloonProxy.addNewBountyPool(
            address(USDC),
            0x1B7FE02Da6c7a7175a33D109397492c2872c6A5e,
            "DUMMY2"
        );

        // USDC.approve(saloon, 0 ether);

        vm.stopBroadcast();
    }
}
