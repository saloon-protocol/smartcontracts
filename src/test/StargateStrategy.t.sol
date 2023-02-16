// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../StargateStrategy.sol";
import "../lib/ERC20.sol";
import "ds-test/test.sol";
import "forge-std/Script.sol";

contract StargateStrategyTest is DSTest, Script {
    StargateStrategy stargateStrategy;

    ERC20 USDC = ERC20(0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174);
    address USDCHolder = address(0x9810762578aCCF1F314320CCa5B72506aE7D7630);
    address rando = address(0x98);

    function receiveStrategyYield(address _token, uint256 _amount) external {
        ERC20(_token).transferFrom(msg.sender, address(this), _amount); // Roughly mimic action in Saloon.sol
    }

    function setUp() external {
        string memory rpc = vm.envString("POLYGON_RPC_URL");
        uint256 forkId = vm.createFork(rpc);
        vm.selectFork(forkId);

        stargateStrategy = new StargateStrategy(address(this), address(USDC));

        vm.deal(USDCHolder, 500 ether);
        vm.deal(address(this), 500 ether);

        // USDC holder transfers address(this) 100 USDC for testing
        vm.prank(USDCHolder);
        USDC.transfer(address(this), 100 * (10**6));
    }

    function testAccessControl() external {
        vm.startPrank(USDCHolder);
        vm.expectRevert("Not authorized");
        stargateStrategy.depositToStrategy();
        vm.expectRevert("Not authorized");
        stargateStrategy.withdrawFromStrategy(0);
        vm.expectRevert("Not authorized");
        stargateStrategy.compound();
        vm.expectRevert("Not authorized");
        stargateStrategy.withdrawYield();
        vm.expectRevert("Not authorized");
        stargateStrategy.updateStargateAddresses(
            USDCHolder,
            USDCHolder,
            USDCHolder,
            USDCHolder
        );
        vm.expectRevert("Not authorized");
        stargateStrategy.updateSwapRouterAddress(USDCHolder);
    }

    // ============================
    // Test Implementation Update
    // ============================
    function testDeposit() external {
        uint256 USDCBalance = USDC.balanceOf(address(this));
        USDC.transfer(address(stargateStrategy), USDCBalance);
        uint256 lpDepositBalance = stargateStrategy.depositToStrategy();
        int256 balanceDiff = int256(USDCBalance) - int256(lpDepositBalance);
        // LP tokens aren't minted 1:1, so only checking that the returned LP is close to input.
        assert(balanceDiff < int256(USDCBalance) / 100);

        vm.roll(block.number + 10000); // STG rewards based on passed blocks, not timestamp
        uint256 pendingRewards = stargateStrategy.pendingRewardBalance();
        assert(pendingRewards > 0);
    }

    function testWithdraw() external {
        uint256 USDCBalance = USDC.balanceOf(address(this));
        USDC.transfer(address(stargateStrategy), USDCBalance);
        uint256 lpAdded = stargateStrategy.depositToStrategy();

        vm.roll(block.number + 10000); // STG rewards based on passed blocks, not timestamp
        uint256 amountWithdrawn = stargateStrategy.withdrawFromStrategy(
            lpAdded
        );

        uint256 finalUSDCBalance = USDC.balanceOf(address(this));
        assert(finalUSDCBalance >= USDCBalance); // Small 1 wei (USDC) precision loss
    }

    function testCompound() external {
        uint256 USDCBalance = USDC.balanceOf(address(this));
        USDC.transfer(address(stargateStrategy), USDCBalance);
        stargateStrategy.depositToStrategy();

        uint256 lpDepositBalanceInitial = stargateStrategy.lpDepositBalance();

        vm.roll(block.number + 10000); // STG rewards based on passed blocks, not timestamp
        uint256 lpAdded = stargateStrategy.compound();
        assert(lpAdded > 0); // Small 1 wei (USDC) precision loss

        uint256 lpDepositBalanceFinal = stargateStrategy.lpDepositBalance();
        assert(lpDepositBalanceFinal > lpDepositBalanceInitial);
        assertEq(lpDepositBalanceFinal, lpDepositBalanceInitial + lpAdded);
    }

    function testDepositCompoundWithdraw() external {
        uint256 USDCBalanceInitial = USDC.balanceOf(address(this));
        USDC.transfer(address(stargateStrategy), USDCBalanceInitial);
        stargateStrategy.depositToStrategy();

        uint256 lpDepositBalanceInitial = stargateStrategy.lpDepositBalance();

        vm.roll(block.number + 10000); // STG rewards based on passed blocks, not timestamp
        stargateStrategy.compound();

        uint256 lpDepositBalanceIntermediate = stargateStrategy
            .lpDepositBalance();
        stargateStrategy.withdrawFromStrategy(lpDepositBalanceIntermediate);
        uint256 USDCBalanceFinal = USDC.balanceOf(address(this));
        assert(USDCBalanceFinal > USDCBalanceInitial);
    }

    function testWithdrawYield() external {
        uint256 USDCBalanceInitial = USDC.balanceOf(address(this));
        USDC.transfer(address(stargateStrategy), USDCBalanceInitial);
        stargateStrategy.depositToStrategy();

        vm.roll(block.number + 10000); // STG rewards based on passed blocks, not timestamp
        stargateStrategy.withdrawYield();

        uint256 USDCBalanceFinal = USDC.balanceOf(address(this));
        assert(USDCBalanceFinal > 0);
    }
}
