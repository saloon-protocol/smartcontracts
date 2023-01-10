// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../StargateStrategy.sol";
import "../lib/ERC20.sol";
import "ds-test/test.sol";
import "forge-std/Script.sol";

contract StargateStrategyTest is DSTest, Script {
    StargateStrategy stargateStrategy;

    ERC20 USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address USDCHolder = address(0x451AbAc74B2Ef32790C20817785Dd634f9217D5a);
    address deployer;

    function setUp() external {
        string memory rpc = vm.envString("ETH_RPC_URL");
        uint256 forkId = vm.createFork(rpc);
        vm.selectFork(forkId);

        stargateStrategy = new StargateStrategy();

        deployer = address(this);

        vm.deal(USDCHolder, 500 ether);
        vm.deal(deployer, 500 ether);

        // USDC holder transfers deployer 100 USDC for testing
        vm.startPrank(USDCHolder);
        USDC.transfer(deployer, 100 * (10**6));
    }

    // ============================
    // Test Implementation Update
    // ============================
    function testAddLiquidity() external {
        uint256 USDCBalance = USDC.balanceOf(deployer);
        USDC.approve(address(stargateStrategy), USDCBalance);
        uint256 lpBalance = stargateStrategy.despositToStrategy(1, USDCBalance);
        int256 balanceDiff = int256(USDCBalance) - int256(lpBalance);
        // LP tokens aren't minted 1:1, so only checking that the returned LP is close to input.
        assert(balanceDiff < int256(USDCBalance) / 100);
    }
}
