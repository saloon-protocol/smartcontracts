// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../Saloon.sol";
import "../SaloonProxy.sol";
import "../StrategyFactory.sol";
import "../lib/ERC20.sol";
import "ds-test/test.sol";
import "forge-std/Script.sol";

// import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract SaloonTest is BountyTokenNFT, DSTest, Script {
    Saloon saloonImplementation;
    SaloonProxy saloonProxy;
    Saloon saloon;
    bytes data = "";

    ERC20 usdc;
    ERC20 dai;
    address project = address(0xDEF1);
    address hunter = address(0xD0);
    address staker = address(0x5ad);
    address staker2 = address(0x5ad2);
    address saloonWallet = address(0x999999);
    address deployer;
    address newOwner = address(0x5ad3);

    uint256 pid;

    function setUp() external {
        string memory mumbai = vm.envString("ETH_RPC_URL");
        // uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        uint256 forkId = vm.createFork(mumbai);
        vm.selectFork(forkId);

        saloonImplementation = new Saloon();
        saloonProxy = new SaloonProxy(address(saloonImplementation), data);
        saloon = Saloon(address(saloonProxy));
        StrategyFactory factory = new StrategyFactory();
        saloon.initialize(address(factory));

        usdc = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
        address USDCHolder = address(
            0x7713974908Be4BEd47172370115e8b1219F4A5f0
        );
        vm.prank(USDCHolder);
        usdc.transfer(address(this), 100000 * (10**6));

        saloon.updateTokenWhitelist(address(usdc), true, 10 * 10**6);
        usdc.transfer(project, 10000 * (10**6));
        usdc.transfer(staker, 1000 * (10**6));
        usdc.transfer(staker2, 1000 * (10**6));

        dai = new ERC20("DAI", "DAI", 18);
        dai.mint(project, 500 ether);
        dai.mint(staker, 500 ether);
        dai.mint(staker2, 500 ether);

        vm.deal(project, 500 ether);

        deployer = address(this);
    }

    // ============================
    // Test Implementation Update
    // ============================
    function testUpdate() external {
        Saloon NewSaloon = new Saloon();
        saloon.upgradeTo(address(NewSaloon));

        vm.prank(staker);
        vm.expectRevert("Ownable: caller is not the owner");
        saloon.upgradeTo(address(NewSaloon));

        // Test first step of ownership transfer and accept reverts for random caller
        saloon.transferOwnership(newOwner);

        // Test new owner accepts ownership and can deploy new bounty
        vm.startPrank(newOwner);
        saloon.acceptOwnershipTransfer();
        saloon.upgradeTo(address(NewSaloon));
        vm.stopPrank();
    }

    // ============================
    // Test addNewBountyPool with non-whitelisted token
    // ============================
    function testaddNewBountyPoolBadToken() external {
        saloon.updateTokenWhitelist(address(usdc), false, 10 * 10**6);
        vm.expectRevert("token not whitelisted");
        pid = saloon.addNewBountyPool(address(usdc), project, "yeehaw");
    }

    // ============================
    // Test updateTokenWhitelist
    // ============================
    function testUpdateTokenWhitelist() external {
        saloon.updateTokenWhitelist(address(usdc), false, 10 * 10**6);
        saloon.updateTokenWhitelist(address(usdc), true, 10 * 10**6);
    }

    // ============================
    // Test addNewBountyPool
    // ============================
    function testaddNewBountyPool() external {
        pid = saloon.addNewBountyPool(address(usdc), project, "yeehaw");
    }

    // ============================
    // Test setAPYandPoolCapAndDeposit
    // ============================
    function testsetAPYandPoolCapAndDeposit() external {
        pid = saloon.addNewBountyPool(address(usdc), project, "yeehaw");
        vm.startPrank(project);
        usdc.approve(address(saloon), 1000 * 10**6);
        saloon.setAPYandPoolCapAndDeposit(
            pid,
            100 * 10**6,
            1000, // 10%
            1 * 10**6,
            "Stargate"
        );

        // Test if APY and PoolCap can be set again (should revert)
        vm.expectRevert("Pool already initialized");
        saloon.setAPYandPoolCapAndDeposit(
            pid,
            100 * 10**6,
            1000,
            0,
            "Stargate"
        );

        // todo Test if poolCap can be exceeded by stakers
    }

    // ============================
    // Test makeProjectDeposit
    // ============================
    function testMakeProjectDeposit() external {
        pid = saloon.addNewBountyPool(address(usdc), project, "yeehaw");
        vm.startPrank(project);
        usdc.approve(address(saloon), 1000 * 10**6);
        saloon.makeProjectDeposit(pid, 10 * 10**6, "Stargate");
        uint256 bountyBalance = saloon.viewBountyBalance(pid);
        assertEq(bountyBalance, 10 * 10**6);
    }

    // ============================
    // Test scheduleProjectDepositWithdrawal
    // ============================
    function testscheduleProjectDepositWithdrawal() external {
        pid = saloon.addNewBountyPool(address(usdc), project, "yeehaw");
        vm.startPrank(project);
        usdc.approve(address(saloon), 1000 * 10**6);
        saloon.makeProjectDeposit(pid, 10 * 10**6, "Stargate");
        bool scheduled = saloon.scheduleProjectDepositWithdrawal(
            pid,
            10 * 10**6
        );

        assert(true == scheduled);
    }

    // ============================
    // Test projectDepositWithdrawal
    // ============================
    function testProjectDepositWithdrawal() external {
        pid = saloon.addNewBountyPool(address(usdc), project, "yeehaw");
        vm.startPrank(project);
        usdc.approve(address(saloon), 1000 * 10**6);
        saloon.makeProjectDeposit(pid, 10 * 10**6, "Stargate");
        saloon.scheduleProjectDepositWithdrawal(pid, 10 * 10**6);

        vm.warp(block.timestamp + 8 days);
        // Test if withdrawal is successfull during withdrawal window
        bool completed = saloon.projectDepositWithdrawal(pid, 10 * 10**6 - 10); // Immediate redeems from Stargate may return 1 wei less token.
        assert(true == completed);

        // Test if withdrawal fails outside withdrawal window
        saloon.makeProjectDeposit(pid, 10 * 10**6, "Stargate");
        saloon.scheduleProjectDepositWithdrawal(pid, 10 * 10**6);
        vm.warp(block.timestamp + 6 days);
        vm.expectRevert("Timelock not set or not completed in time");
        saloon.projectDepositWithdrawal(pid, 10 * 10**6);

        saloon.makeProjectDeposit(pid, 10 * 10**6, "Stargate");
        saloon.scheduleProjectDepositWithdrawal(pid, 10 * 10**6);
        vm.warp(block.timestamp + 11 days);
        vm.expectRevert("Timelock not set or not completed in time");
        saloon.projectDepositWithdrawal(pid, 10 * 10**6);
    }

    // ============================
    // Test stake
    // ============================
    function testStake() external {
        pid = saloon.addNewBountyPool(address(usdc), project, "yeehaw");
        vm.startPrank(project);
        usdc.approve(address(saloon), 1000 * 10**6);
        saloon.setAPYandPoolCapAndDeposit(
            pid,
            100 * 10**6,
            1000,
            1 * 10**6,
            "Stargate"
        );
        vm.stopPrank();

        vm.startPrank(staker);
        usdc.approve(address(saloon), 1000 * 10**6);

        vm.expectRevert("Min stake not met");
        saloon.stake(pid, 5 * 10**6);

        uint256 tokenId = saloon.stake(pid, 10 * 10**6);
        (uint256 stake, , , , ) = saloon.viewTokenInfo(tokenId);
        assertEq(stake, 10 * 10**6);
        assertEq(saloon.ownerOf(tokenId), staker);
    }

    // ============================
    // Test pendingPremium
    // ============================
    function testPendingPremium() external {
        pid = saloon.addNewBountyPool(address(usdc), project, "yeehaw");
        vm.startPrank(project);
        usdc.approve(address(saloon), 1000 * 10**6);
        uint256 poolCap = 100 * 10**6;
        uint16 apy = 1000;
        uint256 deposit = 1 * 10**6;

        saloon.setAPYandPoolCapAndDeposit(
            pid,
            poolCap,
            apy,
            deposit,
            "Stargate"
        );
        vm.stopPrank();

        vm.startPrank(staker);
        usdc.approve(address(saloon), 1000 * 10**6);
        uint256 stakeAmount = 10 * 10**6;

        // uint256 tokenId = saloon.stake(pid, stakeAmount);
        // (uint256 tokenAmount1, uint256 tokenAPY1, , , ) = saloon.viewTokenInfo(
        //     tokenId
        // );
        // assertEq(tokenAmount1, stakeAmount);

        // vm.warp(block.timestamp + 365 days);
        // (uint256 pending, , ) = saloon.pendingPremium(tokenId);

        // assertEq(pending, (tokenAmount1 * tokenAPY1) / 10000); // 10% APY over 365 days
        // assertEq(pending, 4168000); // 10e6 stake => 10% of pool = 41.68% APY on 10% avg APY, for 1 year = 4.168e6 USDC

        // uint256 tokenId2 = saloon.stake(pid, stakeAmount);
        // (uint256 tokenAmount2, uint256 tokenAPY2, , , ) = saloon.viewTokenInfo(
        //     tokenId2
        // );
        // assertEq(tokenAmount2, stakeAmount);
        // // 2nd token must have lower APY than 1st token due to nature of dynamic APY curve
        // assert(tokenAPY2 < tokenAPY1);

        uint256 tokenX;
        uint256 tokenAmountX;
        uint256 tokenAPYX;

        uint256[10] memory APYs;

        for (uint256 i = 0; i < 10; ++i) {
            tokenX = saloon.stake(pid, stakeAmount);
            (tokenAmountX, tokenAPYX, , , ) = saloon.viewTokenInfo(tokenX);
            APYs[i] = tokenAPYX;
        }

        for (uint256 i = 0; i < 9; ++i) {
            assert(APYs[i] > APYs[i + 1]);
        }

        // Pool = $100
        // Avg APY = 1000 (10%)
        // This test makes 10 individual stakes of $10 each
        // Here are the output effective APYs:

        // [4168, 1627, 1030, 755, 597, 493, 420, 366, 324, 291]
    }

    function testConsolidate() external {
        pid = saloon.addNewBountyPool(address(usdc), project, "yeehaw");
        vm.startPrank(project);
        usdc.approve(address(saloon), 1000 * 10**6);
        uint256 poolCap = 100 * 10**6;
        uint16 apy = 1000;
        uint256 deposit = 1 * 10**6;

        saloon.setAPYandPoolCapAndDeposit(
            pid,
            poolCap,
            apy,
            deposit,
            "Stargate"
        );
        vm.stopPrank();

        vm.startPrank(staker);
        usdc.approve(address(saloon), 1000 * 10**6);
        uint256 stakeAmount = 10 * 10**6;
        uint256 tokenId = saloon.stake(pid, stakeAmount);
        (uint256 tokenAmount1, uint256 tokenAPY1, , , ) = saloon.viewTokenInfo(
            tokenId
        );
        assertEq(tokenAmount1, stakeAmount);

        uint256 tokenId2 = saloon.stake(pid, stakeAmount);
        (uint256 tokenAmount2, uint256 tokenAPY2, , , ) = saloon.viewTokenInfo(
            tokenId2
        );
        assertEq(tokenAmount2, stakeAmount);
        // 2nd token must have lower APY than 1st token due to nature of dynamic APY curve
        assert(tokenAPY2 < tokenAPY1);

        uint256 tokenId3 = saloon.stake(pid, stakeAmount);
        (uint256 tokenAmount3, uint256 tokenAPY3, , , ) = saloon.viewTokenInfo(
            tokenId3
        );
        assertEq(tokenAmount3, stakeAmount);
        // 2nd token must have lower APY than 1st token due to nature of dynamic APY curve
        assert(tokenAPY3 < tokenAPY2);

        //schedule unstake
        bool scheduled = saloon.scheduleUnstake(tokenId);
        assert(scheduled == true);

        // unstake
        vm.warp(block.timestamp + 8 days);
        bool unstaked = saloon.unstake(tokenId, true);
        (uint256 stakeAfter, , , , ) = saloon.viewTokenInfo(tokenId);
        assertEq(stakeAfter, 0);

        // Consolidate pool. Should increase APY for token2 and token3.
        saloon.consolidate(pid);

        (, uint256 tokenAPY2New, , , ) = saloon.viewTokenInfo(tokenId2);
        (, uint256 tokenAPY3New, , , ) = saloon.viewTokenInfo(tokenId3);
        assertEq(tokenAPY2New, tokenAPY1);
        assertEq(tokenAPY3New, tokenAPY2);
    }

    // ============================
    // Test scheduleUnstake
    // ============================
    function testScheduleUnstake() external {
        pid = saloon.addNewBountyPool(address(usdc), project, "yeehaw");
        vm.startPrank(project);
        usdc.approve(address(saloon), 1000 * 10**6);
        saloon.setAPYandPoolCapAndDeposit(
            pid,
            100 * 10**6,
            1000,
            1 * 10**6,
            "Stargate"
        );
        vm.stopPrank();
        //stake
        vm.startPrank(staker);
        usdc.approve(address(saloon), 1000 * 10**6);
        uint256 tokenId = saloon.stake(pid, 10 * 10**6);
        (uint256 stake, , , , ) = saloon.viewTokenInfo(tokenId);
        assertEq(stake, 10 * 10**6);

        //schedule unstake
        bool scheduled = saloon.scheduleUnstake(tokenId);
        assert(scheduled == true);
    }

    // ============================
    // Test unstake
    // ============================
    function testUnstake() external {
        pid = saloon.addNewBountyPool(address(usdc), project, "yeehaw");
        vm.startPrank(project);
        usdc.approve(address(saloon), 1000 * 10**6);
        saloon.setAPYandPoolCapAndDeposit(
            pid,
            100 * 10**6,
            1000,
            1 * 10**6,
            "Stargate"
        );
        vm.stopPrank();
        //stake
        vm.startPrank(staker);
        usdc.approve(address(saloon), 1000 * 10**6);
        uint256 tokenId = saloon.stake(pid, 10 * 10**6);
        (uint256 stake, , , , ) = saloon.viewTokenInfo(tokenId);
        assertEq(stake, 10 * 10**6);

        //schedule unstake
        bool scheduled = saloon.scheduleUnstake(tokenId);
        assert(scheduled == true);

        // unstake
        vm.warp(block.timestamp + 8 days);
        bool unstaked = saloon.unstake(tokenId, true);
        (uint256 stakeAfter, , , , ) = saloon.viewTokenInfo(tokenId);
        assertEq(stakeAfter, 0);

        //test unstake fails before schedule window opens
        uint256 tokenId2 = saloon.stake(pid, 10 * 10**6);
        (uint256 stake2, , , , ) = saloon.viewTokenInfo(tokenId2);
        assertEq(stake2, 10 * 10**6);
        bool scheduled2 = saloon.scheduleUnstake(tokenId2);
        assert(scheduled2 == true);

        // unstake before window opens
        vm.warp(block.timestamp + 6 days);
        vm.expectRevert("Timelock not set or not completed in time");
        saloon.unstake(tokenId2, true);

        //test unstake fails after schedule window closes
        bool scheduled3 = saloon.scheduleUnstake(tokenId2);
        assert(scheduled3 == true);
        vm.warp(block.timestamp + 11 days);
        vm.expectRevert("Timelock not set or not completed in time");
        saloon.unstake(tokenId2, true);
    }

    // ============================
    // Test unstake with unclaimed
    // ============================
    function testUnstakeWithUnclaimed() external {
        pid = saloon.addNewBountyPool(address(usdc), project, "yeehaw");
        vm.startPrank(project);
        usdc.approve(address(saloon), 1000 * 10**6);
        saloon.setAPYandPoolCapAndDeposit(
            pid,
            100 * 10**6,
            1000,
            1 * 10**6,
            "Stargate"
        );
        usdc.approve(address(saloon), 0);
        vm.stopPrank();
        //stake
        vm.startPrank(staker);
        usdc.approve(address(saloon), 1000 * 10**6);

        uint256 tokenId = saloon.stake(pid, 100 * 10**6);
        (uint256 stake, , , , ) = saloon.viewTokenInfo(tokenId);
        assertEq(stake, 100 * 10**6);

        // // Transfer away all extra staker $$ to reset balance to 0
        // uint256 originalUSDCBalance = usdc.balanceOf(staker);
        // usdc.transfer(address(0), originalUSDCBalance);

        vm.warp(block.timestamp + 6 days);
        (
            uint256 totalPending,
            uint256 actualPending,
            uint256 newPending
        ) = saloon.pendingPremium(tokenId);
        (, , uint256 actualPendingTokenInfo, , ) = saloon.viewTokenInfo(
            tokenId
        );
        assertEq(actualPending, actualPendingTokenInfo);

        saloon.claimPremium(tokenId);
        (
            uint256 requiredPremiumBalancePerPeriod,
            uint256 premiumBalance,
            uint256 premiumAvailable
        ) = saloon.viewPoolPremiumInfo(pid);
        assertEq(
            premiumBalance,
            requiredPremiumBalancePerPeriod - totalPending
        );

        //schedule unstake
        bool scheduled = saloon.scheduleUnstake(tokenId);
        assert(scheduled == true);

        // unstake
        vm.warp(block.timestamp + 8 days);
        (totalPending, actualPending, newPending) = saloon.pendingPremium(
            tokenId
        );
        (
            requiredPremiumBalancePerPeriod,
            premiumBalance,
            premiumAvailable
        ) = saloon.viewPoolPremiumInfo(pid);
        assert(totalPending > premiumBalance);
        assertEq(totalPending, (requiredPremiumBalancePerPeriod * 8) / 7 + 1); // Staked full cap for 8 days, divide by PERIOD (7 days)
        assertEq(newPending, totalPending);
        vm.expectRevert("ERC20: transfer amount exceeds allowance"); //Project revoked allowance so user can't claim while unstaking
        bool unstaked = saloon.unstake(tokenId, true);

        // Unstake again but set _shouldHarvest to false. Stored pending in user.unclaimed.
        unstaked = saloon.unstake(tokenId, false);
        // uint256 usdcBalance = usdc.balanceOf(staker);
        (uint256 stakeAfter, , uint256 pendingAfter, , ) = saloon.viewTokenInfo(
            tokenId
        );
        assertEq(stakeAfter, 0);
        assertEq(pendingAfter, actualPending);
        vm.stopPrank();

        // Project re-sets approvals
        vm.startPrank(project);
        usdc.approve(address(saloon), 1000 * 10**6);
        vm.stopPrank();

        // Staker can claim their premium now
        vm.startPrank(staker);
        saloon.claimPremium(tokenId);
        (stakeAfter, , pendingAfter, , ) = saloon.viewTokenInfo(tokenId);
        assertEq(stakeAfter, 0);
        assertEq(pendingAfter, 0);
        vm.stopPrank();

        // Ensure that pool has been topped up
        (
            requiredPremiumBalancePerPeriod,
            premiumBalance,
            premiumAvailable
        ) = saloon.viewPoolPremiumInfo(pid);
        assertEq(premiumBalance, requiredPremiumBalancePerPeriod);
        assertEq(premiumAvailable, (premiumBalance * 9000) / 10000 + 1); // +1 due precision loss
    }

    // ============================
    // Test claimPremium
    // ============================
    function testClaimPremium() external {
        pid = saloon.addNewBountyPool(address(usdc), project, "yeehaw");
        vm.startPrank(project);
        usdc.approve(address(saloon), 1000 * 10**6);
        saloon.setAPYandPoolCapAndDeposit(
            pid,
            100 * 10**6,
            1000,
            1 * 10**6,
            "Stargate"
        );
        vm.stopPrank();
        //stake
        vm.startPrank(staker);
        uint256 originalStakerBalance = usdc.balanceOf(staker);
        usdc.approve(address(saloon), 1000 * 10**6);
        uint256 tokenId = saloon.stake(pid, 10 * 10**6);
        (uint256 stake, , , , ) = saloon.viewTokenInfo(tokenId);
        assertEq(stake, 10 * 10**6);

        vm.warp(block.timestamp + 365 days);
        (
            uint256 totalPending,
            uint256 actualPending,
            uint256 newPending
        ) = saloon.pendingPremium(tokenId);
        assertEq(totalPending, 1 * 10**6);
        assertEq(actualPending, 9 * 10**5);
        assertEq(newPending, 1 * 10**6);

        saloon.claimPremium(tokenId);
        // mint - stake + premium -> 500 - 10 + (10 * (10% * 90%)) = 409 * 10**6
        uint256 stakerBalance = usdc.balanceOf(staker);
        assertEq(stakerBalance, originalStakerBalance - stake + actualPending);

        // test unstake and claim
        saloon.scheduleUnstake(tokenId);
        vm.warp(block.timestamp + 1 weeks + 1 days);
        (, uint256 actualPending2, ) = saloon.pendingPremium(tokenId);
        saloon.unstake(tokenId, true);
        // previous balance - stake + premium -> 481.797534246575342466 + 20 + (20 * (8/365 * 10% * 90%)) = 501.836986301
        uint256 stakerBalance2 = usdc.balanceOf(staker);
        assertEq(
            stakerBalance2,
            originalStakerBalance + actualPending + actualPending2
        );
        assert(stakerBalance2 > originalStakerBalance);
    }

    // ============================
    // Test billPremium
    // ============================
    function testBillPremium() external {
        pid = saloon.addNewBountyPool(address(usdc), project, "yeehaw");
        vm.startPrank(project);
        usdc.approve(address(saloon), 1000 * 10**6);
        saloon.setAPYandPoolCapAndDeposit(
            pid,
            100 * 10**6,
            1000,
            1 * 10**6,
            "Stargate"
        );
        vm.stopPrank();

        vm.startPrank(staker);
        usdc.approve(address(saloon), 1000 * 10**6);
        uint256 tokenId = saloon.stake(pid, 10 * 10**6);
        (uint256 stake, , , , ) = saloon.viewTokenInfo(tokenId);
        assertEq(stake, 10 * 10**6);
        vm.stopPrank();

        (
            uint256 requiredPremiumBalancePerPeriod,
            uint256 premiumBalance,
            uint256 premiumAvailable
        ) = saloon.viewPoolPremiumInfo(pid);
        assertEq(requiredPremiumBalancePerPeriod, 191780);

        // requiredPremiumBalancePerPeriod should be equal premiumBalance
        assertEq(premiumBalance, requiredPremiumBalancePerPeriod);
        assertEq(premiumAvailable, (premiumBalance * 9000) / 10000);

        uint256 balanceBefore = usdc.balanceOf(address(saloon));
        uint256 topUpBalance = 10 * 10**6 + requiredPremiumBalancePerPeriod; // +1 from stake, deposit was sent to strategy
        assertEq(balanceBefore, topUpBalance);

        vm.warp(block.timestamp + 365 days);
        (uint256 totalPending, uint256 actualPending, ) = saloon.pendingPremium(
            tokenId
        );
        assertEq(totalPending, 4168000); // 10e6 stake => 10% of pool = 41.68% APY on 10% avg APY, for 1 year = 4.168e6 USDC
        assertEq(actualPending, (4168000 * 9) / 10);

        saloon.billPremium(pid);
        // should be the same as no one has claimed premium and requiredPremiumBalancePerPeriod = premiumBalance
        uint256 balanceAfterBilling = usdc.balanceOf(address(saloon));
        assertEq(balanceAfterBilling, balanceBefore);

        // requiredPremiumBalancePerPeriod should be equal premiumBalance
        (, uint256 premiumBalance2, ) = saloon.viewPoolPremiumInfo(pid);
        assertEq(premiumBalance2, requiredPremiumBalancePerPeriod);

        vm.startPrank(staker);
        //test if after claiming balance decreases by the amount of pending
        saloon.claimPremium(tokenId);
        // 2 * 10**6 + requiredPremiumBalancePerPeriod
        uint256 balanceExpected = 10 * 10**6 + requiredPremiumBalancePerPeriod; // +10 from stake, deposit was sent to strategy. Dynamic APY made it so that premium surpassed balance
        uint256 balanceAfterClaim = usdc.balanceOf(address(saloon));
        assertEq(balanceAfterClaim, balanceExpected);

        // test if requiredPremiumBalancePerPeriod is topped up when premiumAvailable is not enough
        vm.warp(block.timestamp + 730 days);
        (totalPending, actualPending, ) = saloon.pendingPremium(tokenId);
        assertEq(totalPending, ((10 * 10**6 * 1000) / 10000) * 2);

        saloon.claimPremium(tokenId);
        // stake balance + requiredBalancePerPeriod + Saloon Fee for 3 years (user's pending / 2 years * 3 years * 10%)
        uint256 newBalanceExpected = 10 *
            10**6 +
            requiredPremiumBalancePerPeriod +
            (((totalPending / 2) * 3 * 1000) / 10000); // +1 from stake, deposit was sent to strategy
        uint256 balanceAfterClaim2 = usdc.balanceOf(address(saloon));
        assertEq(balanceAfterClaim2, newBalanceExpected);
        (
            uint256 requiredPremiumBalancePerPeriod3,
            uint256 premiumBalance3,
            uint256 premiumAvailable3
        ) = saloon.viewPoolPremiumInfo(pid);
        assertEq(premiumBalance3, requiredPremiumBalancePerPeriod3);
        uint256 newAvailableExpected = (premiumBalance3 * 9000) / 10000;
        assertEq(premiumAvailable3, newAvailableExpected);
        vm.stopPrank();

        // todo test saloonCommission?
    }

    // ============================
    // Test payBounty
    // ============================
    function testPayBountyStakingCovers() external {
        pid = saloon.addNewBountyPool(address(usdc), project, "yeehaw");
        vm.startPrank(project);
        usdc.approve(address(saloon), 1000 * 10**6);
        saloon.setAPYandPoolCapAndDeposit(
            pid,
            100 * 10**6,
            1000,
            30 * 10**6,
            "Stargate"
        );
        vm.stopPrank();

        vm.startPrank(staker);
        usdc.approve(address(saloon), 1000 * 10**6);
        uint256 tokenId = saloon.stake(pid, 10 * 10**6);
        (uint256 stake, , , , ) = saloon.viewTokenInfo(tokenId);
        assertEq(stake, 10 * 10**6);
        vm.stopPrank();

        vm.startPrank(staker2);
        usdc.approve(address(saloon), 1000 * 10**6);
        uint256 tokenId2 = saloon.stake(pid, 10 * 10**6);
        (uint256 stake2, , , , ) = saloon.viewTokenInfo(tokenId2);
        assertEq(stake2, 10 * 10**6);
        vm.stopPrank();

        vm.prank(newOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        saloon.payBounty(pid, newOwner, 10 * 10**6);

        saloon.payBounty(pid, hunter, 10 * 10**6);

        // test hunters balance got the right amount
        uint256 hunterBalance = usdc.balanceOf(hunter);
        assertEq(hunterBalance, 9 * 10**6); // 0.9 usdc

        // test saloonBountyProfit got the right amount
        (
            uint256 totalProfit,
            uint256 bountyProfit,
            uint256 strategyProfit,
            uint256 premiumProfit
        ) = saloon.viewSaloonProfitBalance(address(usdc));
        assertEq(bountyProfit, 1 * 10**6); // 0.1 usdc

        // test stakers balance was reduced properly
        (uint256 stakerAmount, , , , ) = saloon.viewTokenInfo(tokenId);
        (uint256 stakerAmount2, , , , ) = saloon.viewTokenInfo(tokenId2);
        assertEq(stakerAmount2, stakerAmount); // balances should be 0.5 usdc both

        // total staked should be 1 total now. total Pool value = 4 usdc
        uint256 bountyBalance = saloon.viewBountyBalance(pid);
        assertEq(bountyBalance, 40 * 10**6);

        saloon.payBounty(pid, hunter, 40 * 10**6 - 1); // Subtracting 1 wei because Stargate returns 1 wei less if withdrawn in same block
        // test stakers balance was reduced properly
        (uint256 stakerAmountt, , , , ) = saloon.viewTokenInfo(tokenId);
        (uint256 stakerAmountt2, , , , ) = saloon.viewTokenInfo(tokenId2);
        assertEq(stakerAmountt2, stakerAmountt); // should be zero

        // test saloon bountyprofit
        (
            uint256 totalProfit2,
            uint256 bountyProfit2,
            uint256 strategyProfit2,
            uint256 premiumProfit2
        ) = saloon.viewSaloonProfitBalance(address(usdc));
        assertEq(bountyProfit2, 5 * 10**6 - 1); // subtracting 1 wei due to precision loss from stargate staking
    }

    function testPayBountyStrategyDepositNeeded() external {
        pid = saloon.addNewBountyPool(address(usdc), project, "yeehaw");
        vm.startPrank(project);
        usdc.approve(address(saloon), 1000 * 10**6);
        saloon.setAPYandPoolCapAndDeposit(
            pid,
            100 * 10**6,
            1000,
            30 * 10**6,
            "Stargate"
        );
        vm.stopPrank();

        vm.prank(newOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        saloon.payBounty(pid, newOwner, 1 * 10**6);

        saloon.payBounty(pid, hunter, 1 * 10**6);

        // test hunters balance got the right amount
        uint256 hunterBalance = usdc.balanceOf(hunter);
        assertEq(hunterBalance, 9 * 10**5); // 0.9 usdc

        // test saloonBountyProfit got the right amount
        (
            uint256 totalProfit,
            uint256 bountyProfit,
            uint256 strategyProfit,
            uint256 premiumProfit
        ) = saloon.viewSaloonProfitBalance(address(usdc));
        assertEq(bountyProfit, 1 * 10**5); // 0.1 usdc
    }

    // ============================
    // Test collectSaloonProfits
    // ============================
    function testCollectSaloonProfits() external {
        pid = saloon.addNewBountyPool(address(usdc), project, "yeehaw");
        vm.startPrank(project);
        usdc.approve(address(saloon), 1000 * 10**6);
        saloon.setAPYandPoolCapAndDeposit(
            pid,
            100 * 10**6,
            1000,
            30 * 10**6,
            "Stargate"
        );
        vm.stopPrank();

        vm.startPrank(staker);
        usdc.approve(address(saloon), 1000 * 10**6);
        uint256 tokenId = saloon.stake(pid, 10 * 10**6);
        (uint256 stake, , , , ) = saloon.viewTokenInfo(tokenId);
        assertEq(stake, 10 * 10**6);
        vm.stopPrank();

        vm.startPrank(staker2);
        usdc.approve(address(saloon), 1000 * 10**6);
        uint256 tokenId2 = saloon.stake(pid, 10 * 10**6);
        (uint256 stake2, , , , ) = saloon.viewTokenInfo(tokenId2);
        assertEq(stake2, 10 * 10**6);
        vm.stopPrank();

        saloon.payBounty(pid, hunter, 50 * 10**6 - 1); // -1 wei due to stargate precision loss

        saloon.collectSaloonProfits(address(usdc), saloonWallet);

        // test wallet has received amount
        uint256 walletBalance = usdc.balanceOf(saloonWallet);
        assertEq(walletBalance, 5 * 10**6 - 1); // -1 wei due to stargate precision loss

        // test variables have been reset
        (
            uint256 totalProfit,
            uint256 bountyProfit,
            uint256 strategyProfit,
            uint256 premiumProfit
        ) = saloon.viewSaloonProfitBalance(address(usdc));
        assertEq(totalProfit, 0);
    }

    // ============================
    // Test collectAllSaloonProfits
    // ============================
    function testCollectAllSaloonProfits() external {
        pid = saloon.addNewBountyPool(address(usdc), project, "yeehaw");
        vm.startPrank(project);
        usdc.approve(address(saloon), 1000 * 10**6);
        saloon.setAPYandPoolCapAndDeposit(
            pid,
            100 * 10**6,
            1000,
            30 * 10**6,
            ""
        );
        vm.stopPrank();

        vm.startPrank(staker);
        usdc.approve(address(saloon), 1000 * 10**6);
        uint256 tokenId = saloon.stake(pid, 10 * 10**6);
        (uint256 stake, , , , ) = saloon.viewTokenInfo(tokenId);
        assertEq(stake, 10 * 10**6);
        vm.stopPrank();

        vm.startPrank(staker2);
        usdc.approve(address(saloon), 1000 * 10**6);
        uint256 tokenId2 = saloon.stake(pid, 10 * 10**6);
        (uint256 stake2, , , , ) = saloon.viewTokenInfo(tokenId2);
        assertEq(stake2, 10 * 10**6);
        vm.stopPrank();

        saloon.payBounty(pid, hunter, 50 * 10**6);

        // Repeat with pool with token DAI

        saloon.updateTokenWhitelist(address(dai), true, 10 ether);
        uint256 pid2 = saloon.addNewBountyPool(address(dai), project, "yeehaw");
        vm.startPrank(project);
        dai.approve(address(saloon), 1000 ether);
        saloon.setAPYandPoolCapAndDeposit(pid2, 100 ether, 1000, 30 ether, ""); // No strategy for DAI at the moment
        vm.stopPrank();

        vm.startPrank(staker);
        dai.approve(address(saloon), 1000 ether);
        uint256 tokenId3 = saloon.stake(pid2, 10 ether);
        (uint256 stake3, , , , ) = saloon.viewTokenInfo(tokenId3);
        assertEq(stake3, 10 ether);
        vm.stopPrank();

        vm.startPrank(staker2);
        dai.approve(address(saloon), 1000 ether);
        uint256 tokenId4 = saloon.stake(pid2, 10 ether);
        (uint256 stake4, , , , ) = saloon.viewTokenInfo(tokenId4);
        assertEq(stake4, 10 ether);
        vm.stopPrank();

        saloon.payBounty(pid2, hunter, 50 ether);

        saloon.collectAllSaloonProfits(saloonWallet);

        // test wallet has received amount
        uint256 walletBalanceUSDC = usdc.balanceOf(saloonWallet);
        assertEq(walletBalanceUSDC, 5 * 10**6);
        uint256 walletBalanceDAI = dai.balanceOf(saloonWallet);
        assertEq(walletBalanceDAI, 5 ether);

        // test variables have been reset
        (
            uint256 totalProfit,
            uint256 bountyProfit,
            uint256 strategyProfit,
            uint256 premiumProfit
        ) = saloon.viewSaloonProfitBalance(address(usdc));
        assertEq(totalProfit, 0);

        (
            uint256 totalProfit2,
            uint256 bountyProfit2,
            uint256 strategyProfit2,
            uint256 premiumProfit2
        ) = saloon.viewSaloonProfitBalance(address(dai));
        assertEq(totalProfit2, 0);
    }

    function testDecimalsCall() external {
        (, bytes memory _decimals) = address(usdc).staticcall(
            abi.encodeWithSignature("decimals()")
        );
        uint8 decimals = abi.decode(_decimals, (uint8));
    }

    // ============================
    // Test Ownership access and functions
    // ============================
    function testOwnershipFunctions() external {
        // Test random user can not call protected functions (pay bounty protection tested in testpayBounty)
        vm.prank(newOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        pid = saloon.addNewBountyPool(address(usdc), project, "yeehaw");

        pid = saloon.addNewBountyPool(address(usdc), project, "yeehaw");
        assertEq(pid, 0);

        // Test first step of ownership transfer and accept reverts for random caller
        saloon.transferOwnership(newOwner);
        vm.prank(staker);
        vm.expectRevert("only pending owner can accept transfer");
        saloon.acceptOwnershipTransfer();

        // Test new owner accepts ownership and can deploy new bounty
        vm.startPrank(newOwner);
        saloon.acceptOwnershipTransfer();
        pid = saloon.addNewBountyPool(address(usdc), project, "yeehaw");
        assertEq(pid, 1);
        vm.stopPrank();

        // Test original owner cannot deploy new bounty
        vm.expectRevert("Ownable: caller is not the owner");
        pid = saloon.addNewBountyPool(address(usdc), project, "yeehaw");
    }

    function testWindDownBounty() external {
        pid = saloon.addNewBountyPool(address(usdc), project, "yeehaw");
        vm.startPrank(project);
        usdc.approve(address(saloon), 1000 * 10**6);
        saloon.setAPYandPoolCapAndDeposit(
            pid,
            100 * 10**6,
            1000,
            1 * 10**6,
            "Stargate"
        );
        vm.stopPrank();

        vm.startPrank(staker);
        usdc.approve(address(saloon), 1000 * 10**6);
        uint256 tokenId = saloon.stake(pid, 10 * 10**6);
        (uint256 stake, , , , ) = saloon.viewTokenInfo(tokenId);
        assertEq(stake, 10 * 10**6);
        vm.stopPrank();

        vm.startPrank(project);
        vm.warp(block.timestamp + 7 days);
        saloon.windDownBounty(pid);
        vm.stopPrank();

        // Even though 14 days has passed, user only receives pending up until the bounty was wound down
        vm.startPrank(staker);
        vm.warp(block.timestamp + 7 days);
        (uint256 stake2, , uint256 actualPending2, , ) = saloon.viewTokenInfo(
            tokenId
        );
        (tokenId);
        uint256 actualPending = actualPending2;
        uint256 expectedPending = (((((stake2 * 1000) / 10000) * 9000) /
            10000) * 7 days) / 365 days;
        assertEq(actualPending, expectedPending - 1); // -1 Precision loss

        // Staking should fail after pool is wound down
        vm.expectRevert("pool not active");
        saloon.stake(pid, 10 * 10**6);

        //schedule unstake
        bool scheduled = saloon.scheduleUnstake(tokenId);
        assert(scheduled == true);

        // Can still unstake and collect premium even if bounty is wound down
        vm.warp(block.timestamp + 8 days);
        bool unstaked = saloon.unstake(tokenId, true);
        (uint256 stakeAfter, , , , ) = saloon.viewTokenInfo(tokenId);
        assertEq(stakeAfter, 0);
    }

    ///////////////////////// Strategy Integration //////////////////////////////

    // Commented due to private visibility
    // function testDeployStrategy() external {
    //     address deployedStrategy = saloon.deployStrategyIfNeeded(0, "Stargate");
    //     assert(deployedStrategy != address(0));
    // }
}
