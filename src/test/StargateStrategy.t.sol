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

    function setUp() external {
        string memory rpc = vm.envString("ETH_RPC_URL");
        uint256 forkId = vm.createFork(rpc);
        vm.selectFork(forkId);

        stargateStrategy = new StargateStrategy();

        vm.deal(USDCHolder, 500 ether);
        vm.deal(address(this), 500 ether);

        // USDC holder transfers address(this) 100 USDC for testing
        vm.prank(USDCHolder);
        USDC.transfer(address(this), 100 * (10**6));
    }

    // ============================
    // Test Implementation Update
    // ============================
    function testDeposit() external {
        uint256 USDCBalance = USDC.balanceOf(address(this));
        USDC.approve(address(stargateStrategy), USDCBalance);
        uint256 lpDepositBalance = stargateStrategy.despositToStrategy(
            1,
            USDCBalance
        );
        int256 balanceDiff = int256(USDCBalance) - int256(lpDepositBalance);
        // LP tokens aren't minted 1:1, so only checking that the returned LP is close to input.
        assert(balanceDiff < int256(USDCBalance) / 100);

        (uint256 amount, uint256 rewardDebt) = stargateStrategy.userInfo();
        (
            uint256 lpToken,
            uint256 allocPoint,
            uint256 lastRewardBlock,
            uint256 accStargatePerShare
        ) = stargateStrategy.poolInfo();
        assertEq(lastRewardBlock, block.number);

        vm.roll(block.number + 1000); // STG rewards based on passed blocks, not timestamp
        uint256 pendingRewards = stargateStrategy.pendingRewardBalance();
        assert(pendingRewards > 0);
    }

    function testWithdraw() external {
        uint256 USDCBalance = USDC.balanceOf(address(this));
        USDC.approve(address(stargateStrategy), USDCBalance);
        uint256 lpAdded = stargateStrategy.despositToStrategy(1, USDCBalance);

        vm.roll(block.number + 1000); // STG rewards based on passed blocks, not timestamp
        uint256 amountWithdrawn = stargateStrategy.withdrawFromStrategy(
            1,
            lpAdded
        );

        uint256 finalUSDCBalance = USDC.balanceOf(address(this));
        assert(finalUSDCBalance >= USDCBalance); // Small 1 wei (USDC) precision loss
    }

    function testCompound() external {
        uint256 USDCBalance = USDC.balanceOf(address(this));
        USDC.approve(address(stargateStrategy), USDCBalance);
        stargateStrategy.despositToStrategy(1, USDCBalance);

        uint256 lpDepositBalanceInitial = stargateStrategy.lpDepositBalance();

        vm.roll(block.number + 100); // STG rewards based on passed blocks, not timestamp
        uint256 lpAdded = stargateStrategy.compound();
        assert(lpAdded > 0); // Small 1 wei (USDC) precision loss

        uint256 lpDepositBalanceFinal = stargateStrategy.lpDepositBalance();
        assert(lpDepositBalanceFinal > lpDepositBalanceInitial);
        assertEq(lpDepositBalanceFinal, lpDepositBalanceInitial + lpAdded);
    }

    function testDepositCompoundWithdraw() external {
        uint256 USDCBalanceInitial = USDC.balanceOf(address(this));
        USDC.approve(address(stargateStrategy), USDCBalanceInitial);
        stargateStrategy.despositToStrategy(1, USDCBalanceInitial);

        uint256 lpDepositBalanceInitial = stargateStrategy.lpDepositBalance();

        vm.roll(block.number + 1000); // STG rewards based on passed blocks, not timestamp
        stargateStrategy.compound();

        uint256 lpDepositBalanceIntermediate = stargateStrategy
            .lpDepositBalance();
        stargateStrategy.withdrawFromStrategy(1, lpDepositBalanceIntermediate);
        uint256 USDCBalanceFinal = USDC.balanceOf(address(this));
        assert(USDCBalanceFinal > USDCBalanceInitial);
    }
}
