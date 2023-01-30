// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../StargateStrategy.sol";
import "../lib/ERC20.sol";
import "ds-test/test.sol";
import "forge-std/Script.sol";

contract StargateStrategyTest is DSTest, Script {
    StargateStrategy stargateStrategy;

    ERC20 USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address USDCHolder = address(0x7713974908Be4BEd47172370115e8b1219F4A5f0);
    address rando = address(0x98);

    function setUp() external {
        string memory rpc = vm.envString("ETH_RPC_URL");
        uint256 forkId = vm.createFork(rpc);
        vm.selectFork(forkId);

        stargateStrategy = new StargateStrategy(address(this));

        vm.deal(USDCHolder, 500 ether);
        vm.deal(address(this), 500 ether);

        // USDC holder transfers address(this) 100 USDC for testing
        vm.prank(USDCHolder);
        USDC.transfer(address(this), 100 * (10**6));
    }

    function testAccessControl() external {
        vm.startPrank(USDCHolder);
        vm.expectRevert("Not authorized");
        stargateStrategy.depositToStrategy(1);
        vm.expectRevert("Not authorized");
        stargateStrategy.withdrawFromStrategy(1, 0);
        vm.expectRevert("Not authorized");
        stargateStrategy.compound();
        vm.expectRevert("Not authorized");
        stargateStrategy.withdrawYield();
        vm.expectRevert("Not authorized");
        stargateStrategy.updateStargateAddresses(
            USDCHolder,
            USDCHolder,
            USDCHolder
        );
        vm.expectRevert("Not authorized");
        stargateStrategy.updateUniswapRouterAddress(USDCHolder);
    }

    function testOwnershipTransfer() external {
        vm.prank(USDCHolder);
        vm.expectRevert("Not pending owner");
        stargateStrategy.acceptOwnershipTransfer();

        stargateStrategy.setPendingOwner(rando);

        vm.startPrank(USDCHolder);
        vm.expectRevert("Not pending owner");
        stargateStrategy.acceptOwnershipTransfer();
        vm.stopPrank();

        vm.startPrank(rando);
        stargateStrategy.acceptOwnershipTransfer();
        address owner = stargateStrategy.owner();
        assertEq(owner, rando);
    }

    // ============================
    // Test Implementation Update
    // ============================
    function testDeposit() external {
        uint256 USDCBalance = USDC.balanceOf(address(this));
        USDC.transfer(address(stargateStrategy), USDCBalance);
        uint256 lpDepositBalance = stargateStrategy.depositToStrategy(1);
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
        USDC.transfer(address(stargateStrategy), USDCBalance);
        uint256 lpAdded = stargateStrategy.depositToStrategy(1);

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
        USDC.transfer(address(stargateStrategy), USDCBalance);
        stargateStrategy.depositToStrategy(1);

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
        USDC.transfer(address(stargateStrategy), USDCBalanceInitial);
        stargateStrategy.depositToStrategy(1);

        uint256 lpDepositBalanceInitial = stargateStrategy.lpDepositBalance();

        vm.roll(block.number + 1000); // STG rewards based on passed blocks, not timestamp
        stargateStrategy.compound();

        uint256 lpDepositBalanceIntermediate = stargateStrategy
            .lpDepositBalance();
        stargateStrategy.withdrawFromStrategy(1, lpDepositBalanceIntermediate);
        uint256 USDCBalanceFinal = USDC.balanceOf(address(this));
        assert(USDCBalanceFinal > USDCBalanceInitial);
    }

    function testWithdrawYield() external {
        uint256 USDCBalanceInitial = USDC.balanceOf(address(this));
        USDC.transfer(address(stargateStrategy), USDCBalanceInitial);
        stargateStrategy.depositToStrategy(1);

        vm.roll(block.number + 1000); // STG rewards based on passed blocks, not timestamp
        stargateStrategy.withdrawYield();

        uint256 USDCBalanceFinal = USDC.balanceOf(address(this));
        assert(USDCBalanceFinal > 0);
    }
}