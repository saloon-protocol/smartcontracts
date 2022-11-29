// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../Saloon.sol";
import "../SaloonProxy.sol";
import "../lib/ERC20.sol";
import "ds-test/test.sol";
import "forge-std/Script.sol";

// import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract SaloonTest is DSTest, Script {
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
        string memory mumbai = vm.envString("MUMBAI_RPC_URL");
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        uint256 forkId = vm.createFork(mumbai);
        vm.selectFork(forkId);

        saloonImplementation = new Saloon();
        saloonProxy = new SaloonProxy(address(saloonImplementation), data);
        saloon = Saloon(address(saloonProxy));
        saloon.initialize();

        usdc = new ERC20("USDC", "USDC");
        saloon.updateTokenWhitelist(address(usdc), true);
        usdc.mint(project, 500 ether);
        usdc.mint(staker, 500 ether);
        usdc.mint(staker2, 500 ether);

        dai = new ERC20("DAI", "DAI");
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
    }

    // ============================
    // Test addNewBountyPool with non-whitelisted token
    // ============================
    function testaddNewBountyPoolBadToken() external {
        saloon.updateTokenWhitelist(address(usdc), false);
        vm.expectRevert("token not whitelisted");
        pid = saloon.addNewBountyPool(address(usdc), project, "yeehaw");
    }

    // ============================
    // Test updateTokenWhitelist
    // ============================
    function testUpdateTokenWhitelist() external {
        saloon.updateTokenWhitelist(address(usdc), false);
        saloon.updateTokenWhitelist(address(usdc), true);
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
        usdc.approve(address(saloon), 1000 ether);
        saloon.setAPYandPoolCapAndDeposit(pid, 100 ether, 1000, 1 ether);

        // Test if APY and PoolCap can be set again (should revert)
        vm.expectRevert("Pool already initialized");
        saloon.setAPYandPoolCapAndDeposit(pid, 100 ether, 1000, 0 ether);

        // todo Test if poolCap can be exceeded by stakers
    }

    // ============================
    // Test makeProjectDeposit
    // ============================
    function testmakeProjectDeposit() external {
        pid = saloon.addNewBountyPool(address(usdc), project, "yeehaw");
        vm.startPrank(project);
        usdc.approve(address(saloon), 1000 ether);
        saloon.makeProjectDeposit(pid, 10 ether);
        uint256 bountyBalance = saloon.viewBountyBalance(pid);
        assertEq(bountyBalance, 10 ether);
    }

    // ============================
    // Test scheduleProjectDepositWithdrawal
    // ============================
    function testscheduleProjectDepositWithdrawal() external {
        pid = saloon.addNewBountyPool(address(usdc), project, "yeehaw");
        vm.startPrank(project);
        usdc.approve(address(saloon), 1000 ether);
        saloon.makeProjectDeposit(pid, 10 ether);
        bool scheduled = saloon.scheduleProjectDepositWithdrawal(pid, 10 ether);

        assert(true == scheduled);
    }

    // ============================
    // Test projectDepositWithdrawal
    // ============================
    function testprojectDepositWithdrawal() external {
        pid = saloon.addNewBountyPool(address(usdc), project, "yeehaw");
        vm.startPrank(project);
        usdc.approve(address(saloon), 1000 ether);
        saloon.makeProjectDeposit(pid, 10 ether);
        saloon.scheduleProjectDepositWithdrawal(pid, 10 ether);
        vm.warp(block.timestamp + 8 days);
        // Test if withdrawal is successfull during withdrawal window
        bool completed = saloon.projectDepositWithdrawal(pid, 10 ether);
        assert(true == completed);

        // Test if withdrawal fails outside withdrawal window
        saloon.makeProjectDeposit(pid, 10 ether);
        saloon.scheduleProjectDepositWithdrawal(pid, 10 ether);
        vm.warp(block.timestamp + 6 days);
        vm.expectRevert("Timelock not set or not completed in time");
        saloon.projectDepositWithdrawal(pid, 10 ether);

        saloon.makeProjectDeposit(pid, 10 ether);
        saloon.scheduleProjectDepositWithdrawal(pid, 10 ether);
        vm.warp(block.timestamp + 11 days);
        vm.expectRevert("Timelock not set or not completed in time");
        saloon.projectDepositWithdrawal(pid, 10 ether);
    }

    // ============================
    // Test stake
    // ============================
    function testStake() external {
        pid = saloon.addNewBountyPool(address(usdc), project, "yeehaw");
        vm.startPrank(project);
        usdc.approve(address(saloon), 1000 ether);
        saloon.setAPYandPoolCapAndDeposit(pid, 100 ether, 1000, 1 ether);
        vm.stopPrank();

        vm.startPrank(staker);
        usdc.approve(address(saloon), 1000 ether);
        saloon.stake(pid, staker, 1 ether);
        (uint256 stake,) = saloon.viewUserInfo(pid, staker);
        assertEq(stake, 1 ether);
    }

    // ============================
    // Test pendingToken
    // ============================
    function testpendingToken() external {
        pid = saloon.addNewBountyPool(address(usdc), project, "yeehaw");
        vm.startPrank(project);
        usdc.approve(address(saloon), 1000 ether);
        uint256 poolCap = 100 * (1e18);
        saloon.setAPYandPoolCapAndDeposit(pid, poolCap, 1000, 1 ether);
        vm.stopPrank();

        vm.startPrank(staker);
        usdc.approve(address(saloon), 1000 ether);
        uint256 stakeAmount = 10 * (1e18);
        saloon.stake(pid, staker, stakeAmount);
        (uint256 stake,) = saloon.viewUserInfo(pid, staker);
        assertEq(stake, stakeAmount);

        vm.warp(block.timestamp + 365 days);
        (uint256 pending ,, ) = saloon.pendingToken(pid, staker);
        assertEq(pending, 1 ether); // 0.1 usdc

        // todo test with 6 decimals
    }

    // ============================
    // Test scheduleUnstake
    // ============================
    function testScheduleUnstake() external {
        pid = saloon.addNewBountyPool(address(usdc), project, "yeehaw");
        vm.startPrank(project);
        usdc.approve(address(saloon), 1000 ether);
        saloon.setAPYandPoolCapAndDeposit(pid, 100 ether, 1000, 1 ether);
        vm.stopPrank();
        //stake
        vm.startPrank(staker);
        usdc.approve(address(saloon), 1000 ether);
        saloon.stake(pid, staker, 1 ether);
        (uint256 stake,) = saloon.viewUserInfo(pid, staker);
        assertEq(stake, 1 ether);

        //schedule unstake
        bool scheduled = saloon.scheduleUnstake(pid, 1 ether);
        assert(scheduled == true);
    }

    // ============================
    // Test unstake
    // ============================
    function testUnstake() external {
        pid = saloon.addNewBountyPool(address(usdc), project, "yeehaw");
        vm.startPrank(project);
        usdc.approve(address(saloon), 1000 ether);
        saloon.setAPYandPoolCapAndDeposit(pid, 100 ether, 1000, 1 ether);
        vm.stopPrank();
        //stake
        vm.startPrank(staker);
        usdc.approve(address(saloon), 1000 ether);
        saloon.stake(pid, staker, 1 ether);
        (uint256 stake,) = saloon.viewUserInfo(pid, staker);
        assertEq(stake, 1 ether);

        //schedule unstake
        bool scheduled = saloon.scheduleUnstake(pid, 1 ether);
        assert(scheduled == true);

        // unstake
        vm.warp(block.timestamp + 8 days);
        bool unstaked = saloon.unstake(pid, 1 ether, true);
        (uint256 stakeAfter,) = saloon.viewUserInfo(pid, staker);
        assertEq(stakeAfter, 0);

        //test unstake fails before schedule window opens
        saloon.stake(pid, staker, 1 ether);
        (uint256 stake2,) = saloon.viewUserInfo(pid, staker);
        assertEq(stake2, 1 ether);
        bool scheduled2 = saloon.scheduleUnstake(pid, 1 ether);
        assert(scheduled2 == true);

        // unstake before window opens
        vm.warp(block.timestamp + 6 days);
        vm.expectRevert("Timelock not set or not completed in time");
        saloon.unstake(pid, 1 ether, true);
        (uint256 stakeAfter2,) = saloon.viewUserInfo(pid, staker);

        //test unstake fails after schedule window closes
        bool scheduled3 = saloon.scheduleUnstake(pid, 1 ether);
        assert(scheduled3 == true);
        vm.warp(block.timestamp + 11 days);
        vm.expectRevert("Timelock not set or not completed in time");
        saloon.unstake(pid, 1 ether, true);
    }

    // ============================
    // Test unstake with unclaimed
    // ============================
    function testUnstakeWithUnclaimed() external {
        pid = saloon.addNewBountyPool(address(usdc), project, "yeehaw");
        vm.startPrank(project);
        usdc.approve(address(saloon), 1000 ether);
        saloon.setAPYandPoolCapAndDeposit(pid, 100 ether, 1000, 1 ether);
        usdc.approve(address(saloon), 0);
        vm.stopPrank();
        //stake
        vm.startPrank(staker);
        usdc.approve(address(saloon), 1000 ether);
        saloon.stake(pid, staker, 100 ether);
        (uint256 stake,) = saloon.viewUserInfo(pid, staker);
        assertEq(stake, 100 ether);

        vm.warp(block.timestamp + 6 days);
        (uint256 totalPending, uint256 actualPending, uint256 newPending) = saloon.pendingToken(pid, staker);
        saloon.claimPremium(pid);
        (uint256 requiredPremiumBalancePerPeriod, uint256 premiumBalance, uint256 premiumAvailable) = saloon
            .viewPoolPremiumInfo(pid);
        assertEq(premiumBalance, requiredPremiumBalancePerPeriod - totalPending);

        //schedule unstake
        bool scheduled = saloon.scheduleUnstake(pid, 100 ether);
        assert(scheduled == true);

        // unstake
        vm.warp(block.timestamp + 8 days);
        (totalPending, actualPending, newPending) = saloon.pendingToken(pid, staker);
        assertEq(totalPending, requiredPremiumBalancePerPeriod * 8 / 7); // Staked full cap for 8 days, divide by PERIOD (7 days)
        assertEq(newPending, totalPending);
        vm.expectRevert("ERC20: insufficient allowance"); //Project revoked allowance so user can't claim while unstaking
        bool unstaked = saloon.unstake(pid, 100 ether, true);

        // Unstake again but set _shouldHarvest to false. Stored pending in user.unclaimed.
        unstaked = saloon.unstake(pid, 100 ether, false);
        (uint256 stakeAfter, uint256 pendingAfter) = saloon.viewUserInfo(pid, staker);
        assertEq(stakeAfter, 0);
        assertEq(pendingAfter, actualPending);
        vm.stopPrank();

        // Project resets approvals
        vm.startPrank(project);
        usdc.approve(address(saloon), 1000 ether);
        vm.stopPrank();

        // Staker can claim their premium now
        vm.startPrank(staker);
        saloon.claimPremium(pid);
        (stakeAfter, pendingAfter) = saloon.viewUserInfo(pid, staker);
        assertEq(stakeAfter, 0);
        assertEq(pendingAfter, 0);
        vm.stopPrank();

        // Ensure that pool has been topped up
        (requiredPremiumBalancePerPeriod, premiumBalance, premiumAvailable) = saloon.viewPoolPremiumInfo(pid);
        assertEq(premiumBalance, requiredPremiumBalancePerPeriod);
        assertEq(premiumAvailable, premiumBalance * 9000 / 10000 + 3); // +3 due precision loss

        
    }

    // ============================
    // Test claimPremium
    // ============================
    function testClaimPremium() external {
        pid = saloon.addNewBountyPool(address(usdc), project, "yeehaw");
        vm.startPrank(project);
        usdc.approve(address(saloon), 1000 ether);
        saloon.setAPYandPoolCapAndDeposit(pid, 100 ether, 1000, 1 ether);
        vm.stopPrank();
        //stake
        vm.startPrank(staker);
        usdc.approve(address(saloon), 1000 ether);
        saloon.stake(pid, staker, 10 ether);
        (uint256 stake,) = saloon.viewUserInfo(pid, staker);
        assertEq(stake, 10 ether);

        vm.warp(block.timestamp + 365 days);
        (uint256 totalPending, uint256 actualPending, uint256 newPending) = saloon.pendingToken(pid, staker);
        assertEq(totalPending, 1000000000000000000);
        assertEq(actualPending, 900000000000000000);
        assertEq(newPending, 1000000000000000000);

        saloon.claimPremium(pid);
        // mint - stake + premium -> 500 - 10 + (10 * (10% * 90%)) = 409 ether
        uint256 stakerBalance = usdc.balanceOf(staker);
        assertEq(stakerBalance, 490900000000000000000);


        // test staking and claiming with pre-existing stake
        saloon.stake(pid, staker, 10 ether);
        (uint256 stake2,) = saloon.viewUserInfo(pid, staker);
        assertEq(stake2, 20 ether);

        vm.warp(block.timestamp + 182 days); // 6 months
        saloon.claimPremium(pid);
        // previous balance - stake + premium -> 490.9 - 10 + (20 * (182/365 * 10% * 90%)) = 317.975342466
        uint256 stakerBalance2 = usdc.balanceOf(staker);
        assertEq(stakerBalance2, 481797534246575342465);

        // test unstake and claim
        saloon.scheduleUnstake(pid, 20 ether);
        vm.warp(block.timestamp + 1 weeks + 1 days);
        saloon.unstake(pid, 20 ether, true);
        // previous balance - stake + premium -> 481.797534246575342466 + 20 + (20 * (8/365 * 10% * 90%)) = 501.836986301
        uint256 stakerBalance3 = usdc.balanceOf(staker);
        assertEq(stakerBalance3, 501836986301369863012);
    }

    // ============================
    // Test billPremium
    // ============================
    function testbillPremium() external {
        pid = saloon.addNewBountyPool(address(usdc), project, "yeehaw");
        vm.startPrank(project);
        usdc.approve(address(saloon), 1000 ether);
        saloon.setAPYandPoolCapAndDeposit(pid, 100 ether, 1000, 1 ether);
        vm.stopPrank();

        vm.startPrank(staker);
        usdc.approve(address(saloon), 1000 ether);
        saloon.stake(pid, staker, 1 ether);
        (uint256 stake,) = saloon.viewUserInfo(pid, staker);
        assertEq(stake, 1 ether);
        vm.stopPrank();

        (uint256 requiredPremiumBalancePerPeriod, uint256 premiumBalance, uint256 premiumAvailable) = saloon
            .viewPoolPremiumInfo(pid);
        assertEq(requiredPremiumBalancePerPeriod, 191780821917808219);

        // requiredPremiumBalancePerPeriod should be equal premiumBalance
        assertEq(premiumBalance, requiredPremiumBalancePerPeriod);
        assertEq(premiumAvailable, premiumBalance * 9000 / 10000 + 1); // +1 due to precision loss

        uint256 balanceBefore = usdc.balanceOf(address(saloon));
        uint256 topUpBalance = 2 ether + requiredPremiumBalancePerPeriod;
        assertEq(balanceBefore, topUpBalance);

        vm.warp(block.timestamp + 365 days);
        (uint256 totalPending, uint256 actualPending, ) = saloon.pendingToken(pid, staker);
        uint256 totalPendingExpected = 10 * 1e16; // 0.1 ether
        assertEq(totalPending, totalPendingExpected);
        uint256 actualPendingExpected = 9 * 1e16; // 0.1 ether
        assertEq(actualPending, actualPendingExpected);

        saloon.billPremium(pid);
        // should be the same as no one has claimed premium and requiredPremiumBalancePerPeriod = premiumBalance
        uint256 balanceAfterBilling = usdc.balanceOf(address(saloon));
        assertEq(balanceAfterBilling, balanceBefore);

        // requiredPremiumBalancePerPeriod should be equal premiumBalance
        (, uint256 premiumBalance2, ) = saloon.viewPoolPremiumInfo(pid);
        assertEq(premiumBalance2, requiredPremiumBalancePerPeriod);

        vm.startPrank(staker);
        //test if after claiming balance decreases by the amount of pending
        saloon.claimPremium(pid);
        // 2 ether + requiredPremiumBalancePerPeriod
        uint256 balanceExpected = 2 ether + requiredPremiumBalancePerPeriod - actualPending;
        uint256 balanceAfterClaim = usdc.balanceOf(address(saloon));
        assertEq(balanceAfterClaim, balanceExpected);

        // test if requiredPremiumBalancePerPeriod is topped up when premiumAvailable is not enough
        vm.warp(block.timestamp + 730 days);
        (totalPending, actualPending, ) = saloon.pendingToken(pid, staker);
        totalPendingExpected = 1 ether * 1000 / 10000 * 2;
        assertEq(totalPending, totalPendingExpected);

        saloon.claimPremium(pid);
        // stake balance + requiredBalancePerPeriod + Saloon Fee for 3 years (user's pending / 2 years * 3 years * 10%)
        uint256 newBalanceExpected = 2 ether + requiredPremiumBalancePerPeriod + (totalPending / 2 * 3 * 1000 / 10000);
        uint256 balanceAfterClaim2 = usdc.balanceOf(address(saloon));
        assertEq(balanceAfterClaim2, newBalanceExpected);
        (uint256 requiredPremiumBalancePerPeriod3, uint256 premiumBalance3, uint256 premiumAvailable3) = saloon
            .viewPoolPremiumInfo(pid);
        assertEq(premiumBalance3, requiredPremiumBalancePerPeriod3);
        uint256 newAvailableExpected = premiumBalance3 * 9000 / 10000 + 1; // +1 due to precision loss
        assertEq(premiumAvailable3, newAvailableExpected);
        vm.stopPrank();

        // todo test saloonCommission?
    }

    // ============================
    // Test payBounty
    // ============================
    function testpayBounty() external {
        pid = saloon.addNewBountyPool(address(usdc), project, "yeehaw");
        vm.startPrank(project);
        usdc.approve(address(saloon), 1000 ether);
        saloon.setAPYandPoolCapAndDeposit(pid, 100 ether, 1000, 3 ether);
        vm.stopPrank();

        vm.startPrank(staker);
        usdc.approve(address(saloon), 1000 ether);
        saloon.stake(pid, staker, 1 ether);
        (uint256 stake,) = saloon.viewUserInfo(pid, staker);
        assertEq(stake, 1 ether);
        vm.stopPrank();

        vm.startPrank(staker2);
        usdc.approve(address(saloon), 1000 ether);
        saloon.stake(pid, staker2, 1 ether);
        (uint256 stake2,) = saloon.viewUserInfo(pid, staker);
        assertEq(stake2, 1 ether);
        vm.stopPrank();

        vm.prank(newOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        saloon.payBounty(pid, newOwner, 1 ether);

        saloon.payBounty(pid, hunter, 1 ether);

        // test hunters balance got the right amount
        uint256 hunterBalance = usdc.balanceOf(hunter);
        assertEq(hunterBalance, 900000000000000000); // 0.9 usdc

        // test saloonBountyProfit got the right amount
        (
            uint256 totalProfit,
            uint256 bountyProfit,
            uint256 premiumProfit
        ) = saloon.viewSaloonProfitBalance(address(usdc));
        assertEq(bountyProfit, 100000000000000000); // 0.1 usdc

        // test stakers balance was reduced properly
        (uint256 stakerAmount,) = saloon.viewUserInfo(pid, staker);
        (uint256 stakerAmount2,) = saloon.viewUserInfo(pid, staker2);
        assertEq(stakerAmount2, stakerAmount); // balances should be 0.5 usdc both

        // total staked should be 1 total now. total Pool value = 4 usdc
        uint256 bountyBalance = saloon.viewBountyBalance(pid);
        assertEq(bountyBalance, 4 ether);

        saloon.payBounty(pid, hunter, 4 ether);
        // test stakers balance was reduced properly
        (uint256 stakerAmountt,) = saloon.viewUserInfo(pid, staker);
        (uint256 stakerAmountt2,) = saloon.viewUserInfo(pid, staker2);
        assertEq(stakerAmountt2, stakerAmountt); // should be zero

        // test saloon bountyprofit
        (
            uint256 totalProfit2,
            uint256 bountyProfit2,
            uint256 premiumProfit2
        ) = saloon.viewSaloonProfitBalance(address(usdc));
        assertEq(bountyProfit2, 500000000000000000);
    }

    // ============================
    // Test collectSaloonProfits
    // ============================
    function testcollectSaloonProfits() external {
        pid = saloon.addNewBountyPool(address(usdc), project, "yeehaw");
        vm.startPrank(project);
        usdc.approve(address(saloon), 1000 ether);
        saloon.setAPYandPoolCapAndDeposit(pid, 100 ether, 1000, 3 ether);
        vm.stopPrank();

        vm.startPrank(staker);
        usdc.approve(address(saloon), 1000 ether);
        saloon.stake(pid, staker, 1 ether);
        (uint256 stake,) = saloon.viewUserInfo(pid, staker);
        assertEq(stake, 1 ether);
        vm.stopPrank();

        vm.startPrank(staker2);
        usdc.approve(address(saloon), 1000 ether);
        saloon.stake(pid, staker2, 1 ether);
        (uint256 stake2,) = saloon.viewUserInfo(pid, staker);
        assertEq(stake2, 1 ether);
        vm.stopPrank();

        saloon.payBounty(pid, hunter, 5 ether);

        saloon.collectSaloonProfits(address(usdc), saloonWallet);

        // test wallet has received amount
        uint256 walletBalance = usdc.balanceOf(saloonWallet);
        assertEq(walletBalance, 500000000000000000);

        // test variables have been reset
        (
            uint256 totalProfit,
            uint256 bountyProfit,
            uint256 premiumProfit
        ) = saloon.viewSaloonProfitBalance(address(usdc));
        assertEq(totalProfit, 0);
    }

    // ============================
    // Test collectAllSaloonProfits
    // ============================
    function testcollectAllSaloonProfits() external {
        pid = saloon.addNewBountyPool(address(usdc), project, "yeehaw");
        vm.startPrank(project);
        usdc.approve(address(saloon), 1000 ether);
        saloon.setAPYandPoolCapAndDeposit(pid, 100 ether, 1000, 3 ether);
        vm.stopPrank();

        vm.startPrank(staker);
        usdc.approve(address(saloon), 1000 ether);
        saloon.stake(pid, staker, 1 ether);
        (uint256 stake,) = saloon.viewUserInfo(pid, staker);
        assertEq(stake, 1 ether);
        vm.stopPrank();

        vm.startPrank(staker2);
        usdc.approve(address(saloon), 1000 ether);
        saloon.stake(pid, staker2, 1 ether);
        (uint256 stake2,) = saloon.viewUserInfo(pid, staker);
        assertEq(stake2, 1 ether);
        vm.stopPrank();

        saloon.payBounty(pid, hunter, 5 ether);

        // Repeat with pool with token DAI

        saloon.updateTokenWhitelist(address(dai), true);
        uint256 pid2 = saloon.addNewBountyPool(address(dai), project, "yeehaw");
        vm.startPrank(project);
        dai.approve(address(saloon), 1000 ether);
        saloon.setAPYandPoolCapAndDeposit(pid2, 100 ether, 1000, 3 ether);
        vm.stopPrank();

        vm.startPrank(staker);
        dai.approve(address(saloon), 1000 ether);
        saloon.stake(pid2, staker, 1 ether);
        (uint256 stake3,) = saloon.viewUserInfo(pid2, staker);
        assertEq(stake3, 1 ether);
        vm.stopPrank();

        vm.startPrank(staker2);
        dai.approve(address(saloon), 1000 ether);
        saloon.stake(pid2, staker2, 1 ether);
        (uint256 stake4,) = saloon.viewUserInfo(pid2, staker);
        assertEq(stake4, 1 ether);
        vm.stopPrank();

        saloon.payBounty(pid2, hunter, 5 ether);

        saloon.collectAllSaloonProfits(saloonWallet);

        // test wallet has received amount
        uint256 walletBalanceUSDC = usdc.balanceOf(saloonWallet);
        assertEq(walletBalanceUSDC, 500000000000000000);
        uint256 walletBalanceDAI = dai.balanceOf(saloonWallet);
        assertEq(walletBalanceDAI, 500000000000000000);

        // test variables have been reset
        (
            uint256 totalProfit,
            uint256 bountyProfit,
            uint256 premiumProfit
        ) = saloon.viewSaloonProfitBalance(address(usdc));
        assertEq(totalProfit, 0);

        (
            uint256 totalProfit2,
            uint256 bountyProfit2,
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
}
