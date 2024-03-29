// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "forge-std/Script.sol";
import "../src/SaloonProxy.sol";
import "../src/Saloon.sol";
import "openzeppelin-contracts/contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";

contract PayBounty is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        ERC20PresetFixedSupply USDC = ERC20PresetFixedSupply(
            0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d
        ); // Mainnet
        address saloon = 0x5088CE3706104d36DD3083B63e98b162C3f89A38;
        Saloon saloonProxy = Saloon(saloon);

        saloonProxy.payBounty(
            0,
            0xC77dDf4A215874D0Ee52dC2207bf72b468De6651,
            1000, // 10%
            0
        );

        // USDC.approve(saloon, 2500 ether);

        vm.stopBroadcast();
    }
}
