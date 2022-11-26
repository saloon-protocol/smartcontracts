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
    address project = address(0xDEF1);
    address hunter = address(0xD0);
    address staker = address(0x5ad);

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

        usdc.mint(project, 500 ether);
        usdc.mint(staker, 500 ether);

        vm.deal(project, 500 ether);
    }

    // ============================
    // Test Implementation Update
    // ============================
    function testUpdate() external {
        Saloon NewSaloon = new Saloon();
        saloon.upgradeTo(address(NewSaloon));
    }

    // ============================
    // Test addNewBountyPool
    // ============================
    function testaddNewBountyPool() external {
        pid = saloon.addNewBountyPool(address(usdc), 18, project);
    }

    // ============================
    // Test setAPYandPoolCapAndDeposit
    // ============================
    function testsetAPYandPoolCapAndDeposit() external {
        pid = saloon.addNewBountyPool(address(usdc), 18, project);
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
        pid = saloon.addNewBountyPool(address(usdc), 18, project);
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
        pid = saloon.addNewBountyPool(address(usdc), 18, project);
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
        pid = saloon.addNewBountyPool(address(usdc), 18, project);
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
        pid = saloon.addNewBountyPool(address(usdc), 18, project);
        vm.startPrank(project);
        usdc.approve(address(saloon), 1000 ether);
        saloon.setAPYandPoolCapAndDeposit(pid, 100 ether, 1000, 1 ether);
        vm.stopPrank();

        vm.startPrank(staker);
        usdc.approve(address(saloon), 1000 ether);
        saloon.stake(pid, staker, 1 ether);
        uint256 stake = saloon.viewStake(pid);
        assertEq(stake, 1 ether);
    }

    // ============================
    // Test pendingToken
    // ============================
    function testpendingToken() external {
        pid = saloon.addNewBountyPool(address(usdc), 6, project);
        vm.startPrank(project);
        usdc.approve(address(saloon), 1000 ether);
        uint256 poolCap = 100 * (1e6);
        saloon.setAPYandPoolCapAndDeposit(pid, poolCap, 1000, 1 ether);
        vm.stopPrank();

        vm.startPrank(staker);
        usdc.approve(address(saloon), 1000 ether);
        uint256 stakeAmount = 10 * (1e6);
        saloon.stake(pid, staker, stakeAmount);
        uint256 stake = saloon.viewStake(pid);
        assertEq(stake, stakeAmount);

        vm.warp(block.timestamp + 365 days);
        uint256 pending = saloon.pendingToken(pid, staker);
        assertEq(pending, 900000);
    }

    // ============================
    // Test scheduleUnstake
    // ============================
    function testScheduleUnstake() external {
        pid = saloon.addNewBountyPool(address(usdc), 18, project);
        vm.startPrank(project);
        usdc.approve(address(saloon), 1000 ether);
        saloon.setAPYandPoolCapAndDeposit(pid, 100 ether, 1000, 1 ether);
        vm.stopPrank();
        //stake
        vm.startPrank(staker);
        usdc.approve(address(saloon), 1000 ether);
        saloon.stake(pid, staker, 1 ether);
        uint256 stake = saloon.viewStake(pid);
        assertEq(stake, 1 ether);

        //schedule unstake
        bool scheduled = saloon.scheduleUnstake(pid, 1 ether);
        assert(scheduled == true);
    }

    // ============================
    // Test unstake
    // ============================
    function testUnstake() external {
        pid = saloon.addNewBountyPool(address(usdc), 18, project);
        vm.startPrank(project);
        usdc.approve(address(saloon), 1000 ether);
        saloon.setAPYandPoolCapAndDeposit(pid, 100 ether, 1000, 1 ether);
        vm.stopPrank();
        //stake
        vm.startPrank(staker);
        usdc.approve(address(saloon), 1000 ether);
        saloon.stake(pid, staker, 1 ether);
        uint256 stake = saloon.viewStake(pid);
        assertEq(stake, 1 ether);

        //schedule unstake
        bool scheduled = saloon.scheduleUnstake(pid, 1 ether);
        assert(scheduled == true);

        // unstake
        vm.warp(block.timestamp + 8 days);
        bool unstaked = saloon.unstake(pid, 1 ether);
        uint256 stakeAfter = saloon.viewStake(pid);
        assertEq(stakeAfter, 0);

        //test unstake fails before schedule window opens
        saloon.stake(pid, staker, 1 ether);
        uint256 stake2 = saloon.viewStake(pid);
        assertEq(stake2, 1 ether);
        bool scheduled2 = saloon.scheduleUnstake(pid, 1 ether);
        assert(scheduled2 == true);

        // unstake before window opens
        vm.warp(block.timestamp + 6 days);
        vm.expectRevert("Timelock not set or not completed in time");
        saloon.unstake(pid, 1 ether);
        uint256 stakeAfter2 = saloon.viewStake(pid);

        //test unstake fails after schedule window closes
        bool scheduled3 = saloon.scheduleUnstake(pid, 1 ether);
        assert(scheduled3 == true);
        vm.warp(block.timestamp + 11 days);
        vm.expectRevert("Timelock not set or not completed in time");
        saloon.unstake(pid, 1 ether);
    }

    // ============================
    // Test claimPremium
    // ============================
    function testclaimPremium() external {
        pid = saloon.addNewBountyPool(address(usdc), 18, project);
        vm.startPrank(project);
        usdc.approve(address(saloon), 1000 ether);
        saloon.setAPYandPoolCapAndDeposit(pid, 100 ether, 1000, 1 ether);
        vm.stopPrank();
        //stake
        vm.startPrank(staker);
        usdc.approve(address(saloon), 1000 ether);
        saloon.stake(pid, staker, 1 ether);
        uint256 stake = saloon.viewStake(pid);
        assertEq(stake, 1 ether);

        vm.warp(block.timestamp + 365 days);
        saloon.claimPremium(pid);
        // mint - stake + premium -> 500 - 1 + 0.09 = 499.09 ether
        uint256 stakerBalance = usdc.balanceOf(staker);
        assertEq(stakerBalance, 499090000000000000000);

        // test staking and claiming with pre-existing stake
        saloon.stake(pid, staker, 1 ether);
        uint256 stake2 = saloon.viewStake(pid);
        assertEq(stake2, 2 ether);

        vm.warp(block.timestamp + 182 days); // 6 months
        saloon.claimPremium(pid);
        // previous balance - stake + premium -> 499.09 - 1 + 0.09 = 498.18 ether
        // obs: little discrepancy because six months would be 182.5 days instead of only 182
        uint256 stakerBalance2 = usdc.balanceOf(staker);
        assertEq(stakerBalance2, 498179753424657534246);

        // todo test unstake and claim
    }

    // ============================
    // Test billPremium
    // ============================
    function testbillPremium() external {
        pid = saloon.addNewBountyPool(address(usdc), 18, project);
        vm.startPrank(project);
        usdc.approve(address(saloon), 1000 ether);
        saloon.setAPYandPoolCapAndDeposit(pid, 100 ether, 1000, 1 ether);
        vm.stopPrank();

        vm.startPrank(staker);
        usdc.approve(address(saloon), 1000 ether);
        saloon.stake(pid, staker, 1 ether);
        uint256 stake = saloon.viewStake(pid);
        assertEq(stake, 1 ether);
        vm.stopPrank();

        (, uint256 requiredPremiumBalancePerPeriod, ) = saloon
            .viewPoolPremiumInfo(pid);

        uint256 expectedRequiredPremium = ((1000 * 100 ether * 1 weeks) /
            10000);
        uint256 expectedRequiredPremiumPerWeek = expectedRequiredPremium /
            365 days;
        assertEq(
            requiredPremiumBalancePerPeriod,
            expectedRequiredPremiumPerWeek
        );

        uint256 balanceBefore = usdc.balanceOf(address(saloon));
        assertEq(balanceBefore, 2 ether + requiredPremiumBalancePerPeriod);

        vm.warp(block.timestamp + 365 days);
        uint256 pending = saloon.pendingToken(pid, staker);
        uint256 pendingExpected = 9 * 1e16; // .09 ether
        assertEq(pending, pendingExpected);

        saloon.billPremium(pid);
        // should be the same as no one has claimed premium and requiredPremiumBalancePerPeriod = premiumBalance
        uint256 balanceAfterBilling = usdc.balanceOf(address(saloon));
        assertEq(balanceAfterBilling, balanceBefore);

        vm.startPrank(staker);
        //test if after claiming balance decreases by the amount of pending
        saloon.claimPremium(pid);
        // 2 ether + requiredPremiumBalancePerPeriod - pendingExpected
        uint256 balanceExpected = balanceAfterBilling - pendingExpected;
        uint256 balanceAfterClaim = usdc.balanceOf(address(saloon));
        assertEq(balanceAfterClaim, balanceExpected);
        vm.stopPrank();

        // test if billing tops up requiredPremiumBalancePerPeriod
        saloon.billPremium(pid);
        uint256 balanceAfterBilling2 = usdc.balanceOf(address(saloon));
        assertEq(balanceAfterBilling2, balanceBefore);

        // test if billing occurs after calling claimPremium when current balance is not sufficient
        vm.startPrank(staker);
        vm.warp(block.timestamp + 100 * 365 days);
        uint256 premiumPaid = 100 * 9 * 1e16;
        saloon.claimPremium(pid);
        uint256 balanceAfterBilling3 = usdc.balanceOf(address(saloon));
        uint256 expectedBalanceAfterBilling = balanceBefore - premiumPaid;
        // expected balance is .09 bigger...
        assertEq(balanceAfterBilling3, expectedBalanceAfterBilling);
    }

    // ============================
    // Test payBounty
    // ============================

    // ============================
    // Test collectSaloonProfits
    // ============================
}
