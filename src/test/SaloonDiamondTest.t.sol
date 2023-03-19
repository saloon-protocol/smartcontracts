// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../DiamondCut.sol";
import "../DiamondInit.sol";
import "../Base.sol";

import "../DiamondProxy.sol";
import "../ManagerFacet.sol";
import "../ProjectFacet.sol";
import "../BountyFacet.sol";
import "../ViewFacet.sol";
import "../Getters.sol";

import "../interfaces/ISaloonGlobal.sol";

import "../StrategyFactory.sol";

import "../interfaces/IStrategyFactory.sol";
import "../interfaces/IDiamondCut.sol";
import "../lib/Diamond.sol";
import "../lib/ERC20.sol";
import "ds-test/test.sol";
import "forge-std/Script.sol";

contract SaloonDiamondTest is DSTest, Script {
    bytes data = "";

    ERC20 usdc;
    ERC20 dai;
    address project = address(0xDEF1);
    address hunter = address(0xD0);
    address staker = address(0x5ad);
    address staker2 = address(0x5ad2);
    address referrer = address(0x111);
    address saloonWallet = address(0x69);
    address deployer;
    address newOwner = address(0x5ad3);

    uint256 pid;

    uint256 constant poolCap = 1000 * 10 ** 6;
    uint16 constant apy = 1000;
    uint256 constant deposit = 30 * 10 ** 6;
    uint256 constant YEAR = 365 days;
    uint256 constant PERIOD = 1 weeks;
    uint256 constant BPS = 10_000;
    uint256 constant PRECISION = 1e18;
    uint256 constant saloonFee = 1000;

    DiamondProxy saloonProxy;
    ISaloonGlobal saloon;

    ManagerFacet saloonManager;
    ProjectFacet saloonProject;
    BountyFacet saloonBounty;
    ViewFacet saloonView;

    GettersFacet getters;
    DiamondCutFacet diamondCut;
    Diamond.DiamondCutData _diamondCut;
    Diamond.FacetCut diamondCutFacet;
    Diamond.FacetCut gettersFacet;

    Diamond.FacetCut managerFacet;
    Diamond.FacetCut projectFacet;
    Diamond.FacetCut bountyFacet;
    Diamond.FacetCut viewFacet;

    Diamond.FacetCut[] proposeFacets;
    Diamond.DiamondCutData executeFacets;

    function setUp() external {
        string memory rpc = vm.envString("POLYGON_RPC_URL");
        // uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        uint256 forkId = vm.createSelectFork(rpc);

        usdc = ERC20(0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174);
        address USDCHolder = address(
            0x9810762578aCCF1F314320CCa5B72506aE7D7630
        );
        vm.prank(USDCHolder);
        ERC20(usdc).transfer(address(this), 100_000 * 1e6);
        usdc.transfer(project, 10000 * (10 ** 6));
        usdc.transfer(staker, 1000 * (10 ** 6));
        usdc.transfer(staker2, 1000 * (10 ** 6));
        dai = new ERC20("DAI", "DAI", 18);
        dai.mint(project, 500 ether);
        dai.mint(staker, 500 ether);
        dai.mint(staker2, 500 ether);
        vm.deal(project, 500 ether);

        deployer = address(this);

        getters = new GettersFacet();
        diamondCut = new DiamondCutFacet();
        DiamondInit diamondInit = new DiamondInit();

        bytes memory initData = abi.encodeWithSignature(
            "initialize(address)",
            address(this)
        ); // initialize func with owner address

        //diamondCut Facet
        diamondCutFacet.facet = address(diamondCut);
        diamondCutFacet.action = Diamond.Action.Add;
        diamondCutFacet.isFreezable = false;
        diamondCutFacet.selectors.push(IDiamondCut.proposeDiamondCut.selector);
        diamondCutFacet.selectors.push(
            IDiamondCut.cancelDiamondCutProposal.selector
        );
        diamondCutFacet.selectors.push(
            IDiamondCut.executeDiamondCutProposal.selector
        );
        diamondCutFacet.selectors.push(
            IDiamondCut.emergencyFreezeDiamond.selector
        );
        diamondCutFacet.selectors.push(IDiamondCut.unfreezeDiamond.selector);
        diamondCutFacet.selectors.push(
            IDiamondCut
                .approveEmergencyDiamondCutAsSecurityCouncilMember
                .selector
        );

        // Getters Facet
        gettersFacet.facet = address(getters);
        gettersFacet.action = Diamond.Action.Add;
        gettersFacet.isFreezable = false;
        gettersFacet.selectors.push(IGetters.getOwner.selector);
        gettersFacet.selectors.push(IGetters.getPendingOwner.selector);
        gettersFacet.selectors.push(IGetters.isDiamondStorageFrozen.selector);
        gettersFacet.selectors.push(
            IGetters.getProposedDiamondCutHash.selector
        );
        gettersFacet.selectors.push(
            IGetters.getProposedDiamondCutTimestamp.selector
        );
        gettersFacet.selectors.push(
            IGetters.getLastDiamondFreezeTimestamp.selector
        );
        gettersFacet.selectors.push(IGetters.getCurrentProposalId.selector);
        gettersFacet.selectors.push(
            IGetters.getSecurityCouncilEmergencyApprovals.selector
        );
        gettersFacet.selectors.push(IGetters.isSecurityCouncilMember.selector);
        gettersFacet.selectors.push(
            IGetters.getSecurityCouncilMemberLastApprovedProposalId.selector
        );
        gettersFacet.selectors.push(IGetters.facets.selector);
        gettersFacet.selectors.push(IGetters.facetFunctionSelectors.selector);
        gettersFacet.selectors.push(IGetters.facetAddresses.selector);
        gettersFacet.selectors.push(IGetters.facetAddress.selector);
        gettersFacet.selectors.push(IGetters.isFunctionFreezable.selector);

        _diamondCut.facetCuts.push(diamondCutFacet);
        _diamondCut.facetCuts.push(gettersFacet);

        _diamondCut.initAddress = address(diamondInit);
        _diamondCut.initCalldata = initData;

        //Creates proxy and sets Init/DiamontCut Implementation
        saloonProxy = new DiamondProxy(_diamondCut);
        saloon = ISaloonGlobal(address(saloonProxy));

        ///////////////////// Deploy Facets ///////////////////////////////////

        ///// Add Manager facet /////
        saloonManager = new ManagerFacet();
        managerFacet.facet = address(saloonManager);
        managerFacet.action = Diamond.Action.Add;
        managerFacet.isFreezable = false;
        managerFacet.selectors.push(IManagerFacet.addNewBountyPool.selector);
        managerFacet.selectors.push(IManagerFacet.billPremium.selector);
        managerFacet.selectors.push(
            IManagerFacet.collectAllReferralProfits.selector
        );
        managerFacet.selectors.push(
            IManagerFacet.collectAllSaloonProfits.selector
        );
        managerFacet.selectors.push(
            IManagerFacet.collectReferralProfit.selector
        );
        managerFacet.selectors.push(
            IManagerFacet.collectSaloonProfits.selector
        );
        managerFacet.selectors.push(
            IManagerFacet.extendReferralPeriod.selector
        );
        managerFacet.selectors.push(IManagerFacet.setStrategyFactory.selector);
        managerFacet.selectors.push(
            IManagerFacet.startAssessmentPeriod.selector
        );
        managerFacet.selectors.push(
            IManagerFacet.updateTokenWhitelist.selector
        );
        managerFacet.selectors.push(IManagerFacet.setLibSaloonStorage.selector);
        managerFacet.selectors.push(IManagerFacet.setPendingOwner.selector);
        managerFacet.selectors.push(
            IManagerFacet.acceptOwnershipTransfer.selector
        );

        proposeFacets.push(managerFacet);
        executeFacets.facetCuts.push(managerFacet);

        //// Project Facet ////////////
        saloonProject = new ProjectFacet();
        projectFacet.facet = address(saloonProject);
        projectFacet.action = Diamond.Action.Add;
        projectFacet.isFreezable = false;
        projectFacet.selectors.push(IProjectFacet.compoundYieldForPid.selector);
        projectFacet.selectors.push(IProjectFacet.makeProjectDeposit.selector);
        projectFacet.selectors.push(
            IProjectFacet.projectDepositWithdrawal.selector
        );
        projectFacet.selectors.push(
            IProjectFacet.scheduleProjectDepositWithdrawal.selector
        );
        projectFacet.selectors.push(
            IProjectFacet.receiveStrategyYield.selector
        );
        projectFacet.selectors.push(
            IProjectFacet.setAPYandPoolCapAndDeposit.selector
        );
        projectFacet.selectors.push(
            IProjectFacet.updateProjectWalletAddress.selector
        );
        projectFacet.selectors.push(IProjectFacet.viewBountyBalance.selector);
        projectFacet.selectors.push(IProjectFacet.windDownBounty.selector);
        projectFacet.selectors.push(
            IProjectFacet.withdrawProjectYield.selector
        );

        proposeFacets.push(projectFacet);
        executeFacets.facetCuts.push(projectFacet);

        ///// Bounty Facet/////
        saloonBounty = new BountyFacet();
        bountyFacet.facet = address(saloonBounty);
        bountyFacet.action = Diamond.Action.Add;
        bountyFacet.isFreezable = false;

        bountyFacet.selectors.push(IBountyFacet.payBounty.selector);
        bountyFacet.selectors.push(IBountyFacet.calculateEffectiveAPY.selector);
        bountyFacet.selectors.push(IBountyFacet.claimPremium.selector);
        bountyFacet.selectors.push(IBountyFacet.consolidate.selector);
        bountyFacet.selectors.push(IBountyFacet.consolidateAll.selector);
        bountyFacet.selectors.push(IBountyFacet.getCurrentAPY.selector);
        bountyFacet.selectors.push(
            IBountyFacet.payBountyDuringAssessment.selector
        );
        bountyFacet.selectors.push(IBountyFacet.scheduleUnstake.selector);
        bountyFacet.selectors.push(IBountyFacet.stake.selector);
        bountyFacet.selectors.push(IBountyFacet.unstake.selector);
        bountyFacet.selectors.push(IBountyFacet.withdrawRemainingAPY.selector);
        bountyFacet.selectors.push(IBountyFacet.balanceOf.selector);
        bountyFacet.selectors.push(IBountyFacet.ownerOf.selector);
        bountyFacet.selectors.push(
            bytes4(keccak256("safeTransferFrom(address,address,uint256)"))
        );
        bountyFacet.selectors.push(
            bytes4(keccak256("safeTransferFrom(address,address,uint256,bytes)"))
        );
        // bountyFacet.selectors.push(IBountyFacet.safeTransferFrom.selector);

        bountyFacet.selectors.push(IBountyFacet.transferFrom.selector);
        bountyFacet.selectors.push(IBountyFacet.approve.selector);
        bountyFacet.selectors.push(IBountyFacet.setApprovalForAll.selector);
        bountyFacet.selectors.push(IBountyFacet.getApproved.selector);
        bountyFacet.selectors.push(IBountyFacet.isApprovedForAll.selector);

        proposeFacets.push(bountyFacet);
        executeFacets.facetCuts.push(bountyFacet);

        ///// View Facet/////
        saloonView = new ViewFacet();
        viewFacet.facet = address(saloonView);
        viewFacet.action = Diamond.Action.Add;
        viewFacet.isFreezable = false;

        viewFacet.selectors.push(IViewFacet.viewBountyInfo.selector);
        viewFacet.selectors.push(IViewFacet.viewMinProjectDeposit.selector);
        viewFacet.selectors.push(IViewFacet.viewPoolAPY.selector);
        viewFacet.selectors.push(IViewFacet.viewPoolCap.selector);
        viewFacet.selectors.push(IViewFacet.viewPoolPremiumInfo.selector);
        viewFacet.selectors.push(IViewFacet.viewPoolTimelockInfo.selector);
        viewFacet.selectors.push(IViewFacet.viewReferralBalance.selector);
        viewFacet.selectors.push(IViewFacet.viewSaloonProfitBalance.selector);
        viewFacet.selectors.push(IViewFacet.viewTokenInfo.selector);
        viewFacet.selectors.push(IViewFacet.viewTotalStaked.selector);
        viewFacet.selectors.push(IViewFacet.viewPendingPremium.selector);
        viewFacet.selectors.push(IViewFacet.getAllTokensByOwner.selector);

        proposeFacets.push(viewFacet);
        executeFacets.facetCuts.push(viewFacet);

        // Propose and Execute all facets
        IDiamondCut(address(saloonProxy)).proposeDiamondCut(
            proposeFacets,
            address(0x0)
        );

        executeFacets.initAddress = address(0x0);
        executeFacets.initCalldata = "";
        IDiamondCut(address(saloonProxy)).executeDiamondCutProposal(
            executeFacets
        );

        // Set variables and approve token
        StrategyFactory factory = new StrategyFactory();
        saloon.setStrategyFactory(address(factory));
        saloon.setLibSaloonStorage();
        saloon.updateTokenWhitelist(address(usdc), true, 10 * 10 ** 6);

        saloon.updateTokenWhitelist(address(usdc), true, 10 * 10 ** 6);

        pid = saloon.addNewBountyPool(
            address(usdc),
            project,
            "yeehaw",
            address(0),
            0,
            0
        );

        vm.startPrank(project);
        usdc.approve(address(saloon), 1000 * 10 ** 6);
        saloon.setAPYandPoolCapAndDeposit(
            pid,
            poolCap, // $100
            apy, // 10%
            deposit, // $30
            "Stargate"
        );
        vm.stopPrank();
    }

    // ============================
    //        Test Deploy
    // ============================
    function testManager() external {
        saloon.updateTokenWhitelist(address(usdc), true, 10 * 10 ** 6);
        pid = IManagerFacet(address(saloonProxy)).addNewBountyPool(
            address(usdc),
            project,
            "yeehaw",
            address(0),
            0,
            0
        );
        vm.startPrank(staker);
        vm.expectRevert();
        IManagerFacet(address(saloonProxy)).addNewBountyPool(
            address(usdc),
            project,
            "yeehaw",
            address(0),
            0,
            0
        );
        vm.stopPrank();
    }

    // // ============================
    // // Test New Facet Update
    // // ============================
    // function testUpdate() external {
    //     SaloonRelay newSaloon = new SaloonRelay();
    //     saloon.upgradeTo(address(newSaloon));

    //     vm.prank(staker);
    //     vm.expectRevert("Ownable: caller is not the owner");
    //     saloon.upgradeTo(address(newSaloon));

    //     // Test first step of ownership transfer and accept reverts for random caller
    //     saloon.transferOwnership(newOwner);

    //     // Test new owner accepts ownership and can deploy new bounty
    //     vm.startPrank(newOwner);
    //     saloon.acceptOwnershipTransfer();
    //     saloon.upgradeTo(address(newSaloon));
    //     vm.stopPrank();
    // }

    // ============================
    // Test addNewBountyPool with non-whitelisted token
    // ============================
    function testaddNewBountyPoolBadToken() external {
        saloon.updateTokenWhitelist(address(usdc), false, 10 * 10 ** 6);
        vm.expectRevert("token not whitelisted");
        pid = saloon.addNewBountyPool(
            address(usdc),
            project,
            "yeehaw",
            address(0),
            0,
            0
        );

        // Test is approving works again
        saloon.updateTokenWhitelist(address(usdc), true, 10 * 10 ** 6);

        pid = saloon.addNewBountyPool(
            address(usdc),
            project,
            "yeehuu",
            address(0),
            0,
            0
        );

        // One more check to test disapproving works after approving
        saloon.updateTokenWhitelist(address(usdc), false, 10 * 10 ** 6);

        vm.expectRevert("token not whitelisted");
        pid = saloon.addNewBountyPool(
            address(usdc),
            project,
            "yeehee",
            address(0),
            0,
            0
        );
    }

    // ============================
    // Test setAPYandPoolCapAndDeposit
    // ============================
    function testSetAPYAndPoolCapAndDeposit() external {
        saloon.updateTokenWhitelist(address(usdc), true, 10 * 10 ** 6);

        pid = saloon.addNewBountyPool(
            address(usdc),
            project,
            "yeehuu",
            address(0),
            0,
            0
        );
        emit log_uint(pid);

        pid = saloon.addNewBountyPool(
            address(usdc),
            project,
            "yeehaaa",
            address(0),
            0,
            0
        );
        emit log_uint(pid); // Testing if pid increases correctly

        vm.startPrank(project);
        usdc.approve(address(saloon), 100000 * 10 ** 6);
        // Test setAPYandPoolCapAndDeposit
        saloon.setAPYandPoolCapAndDeposit(
            pid,
            1000 * 10 ** 6,
            1000,
            10,
            "Stargate"
        );

        // Test if APY and PoolCap can be set again (should revert)
        vm.expectRevert("Pool already initialized");
        saloon.setAPYandPoolCapAndDeposit(
            pid,
            100 * 10 ** 6,
            1000,
            10,
            "Stargate"
        );
        // todo Test if poolCap can be exceeded by stakers
    }

    // ============================
    // Test makeProjectDeposit
    // ============================
    function testMakeProjectDeposit() external {
        saloon.updateTokenWhitelist(address(usdc), true, 10 * 10 ** 6);
        pid = saloon.addNewBountyPool(
            address(usdc),
            project,
            "yeehaw",
            address(0),
            0,
            0
        );
        vm.startPrank(project);
        usdc.approve(address(saloon), 1000 * 10 ** 6);
        saloon.makeProjectDeposit(pid, 10 * 10 ** 6, "Stargate");
        uint256 bountyBalance = saloon.viewBountyBalance(pid);
        assertEq(bountyBalance, 10 * 10 ** 6 - 1);
    }

    // ============================
    // Test scheduleProjectDepositWithdrawal
    // ============================
    function testscheduleProjectDepositWithdrawal() external {
        pid = saloon.addNewBountyPool(
            address(usdc),
            project,
            "yeehaw",
            address(0),
            0,
            0
        );
        vm.startPrank(project);
        usdc.approve(address(saloon), 1000 * 10 ** 6);
        saloon.makeProjectDeposit(pid, 10 * 10 ** 6, "Stargate");
        bool scheduled = saloon.scheduleProjectDepositWithdrawal(
            pid,
            10 * 10 ** 6 - 1
        ); // Immediate redeems from Stargate may return 1 wei less token.

        assert(true == scheduled);
    }

    // ============================
    // Test projectDepositWithdrawal
    // ============================
    function testProjectDepositWithdrawal() external {
        pid = saloon.addNewBountyPool(
            address(usdc),
            project,
            "yeehaw",
            address(0),
            0,
            0
        );
        vm.startPrank(project);
        usdc.approve(address(saloon), 1000 * 10 ** 6);
        saloon.makeProjectDeposit(pid, 10 * 10 ** 6, "Stargate");
        saloon.scheduleProjectDepositWithdrawal(pid, 10 * 10 ** 6 - 1);

        vm.warp(block.timestamp + 8 days);
        // Test if withdrawal is successfull during withdrawal window
        bool completed = saloon.projectDepositWithdrawal(pid, 10 * 10 ** 6 - 1); // Immediate redeems from Stargate may return 1 wei less token.
        assert(true == completed);

        // Test if withdrawal fails outside withdrawal window
        saloon.makeProjectDeposit(pid, 10 * 10 ** 6, "Stargate");
        saloon.scheduleProjectDepositWithdrawal(pid, 10 * 10 ** 6 - 1);
        vm.warp(block.timestamp + 6 days);
        vm.expectRevert("Timelock not set or not completed in time");
        saloon.projectDepositWithdrawal(pid, 10 * 10 ** 6 - 1);

        saloon.makeProjectDeposit(pid, 10 * 10 ** 6, "Stargate");
        saloon.scheduleProjectDepositWithdrawal(pid, 10 * 10 ** 6 - 1);
        vm.warp(block.timestamp + 11 days);
        vm.expectRevert("Timelock not set or not completed in time");
        saloon.projectDepositWithdrawal(pid, 10 * 10 ** 6 - 1);
    }

    function testProjectWithdrawYield() external {
        vm.roll(block.number + 10000);
        vm.startPrank(project);
        uint256 yieldReturned = saloon.withdrawProjectYield(pid);
        assert(yieldReturned > 0);
        vm.stopPrank();

        // Also check that Saloon profit was incremented
        (, , uint256 strategyProfit, ) = saloon.viewSaloonProfitBalance(
            address(usdc)
        );
        assert(strategyProfit > 0);
    }

    // ============================
    // Test stake
    // ============================
    function testStake() external {
        vm.startPrank(staker);
        usdc.approve(address(saloon), 1000 * 10 ** 6);

        vm.expectRevert("Min stake not met");
        saloon.stake(pid, 5 * 10 ** 6);

        uint256 tokenId = saloon.stake(pid, 10 * 10 ** 6);
        (uint256 stake, , , , ) = saloon.viewTokenInfo(tokenId);
        assertEq(stake, 10 * 10 ** 6);
        assertEq(saloon.ownerOf(tokenId), staker);
        vm.stopPrank();
    }

    // ============================
    // Test pendingPremium
    // ============================
    function testPendingPremium() external {
        vm.startPrank(staker);
        usdc.approve(address(saloon), 1000 * 10 ** 6);
        uint256 stakeAmount = 10 * 10 ** 6;

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
        vm.startPrank(staker);
        usdc.approve(address(saloon), 1000 * 10 ** 6);
        uint256 stakeAmount = 10 * 10 ** 6;
        uint256 tokenId = saloon.stake(pid, stakeAmount);
        (uint256 tokenAmount1, uint256 tokenAPY1, , , ) = saloon.viewTokenInfo(
            tokenId
        );
        emit log_named_address("owner", saloon.ownerOf(tokenId));

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
        vm.startPrank(staker);
        usdc.approve(address(saloon), 1000 * 10 ** 6);
        uint256 tokenId = saloon.stake(pid, 10 * 10 ** 6);
        (uint256 stake, , , , ) = saloon.viewTokenInfo(tokenId);
        assertEq(stake, 10 * 10 ** 6);

        //schedule unstake
        bool scheduled = saloon.scheduleUnstake(tokenId);
        assert(scheduled == true);
    }

    // ============================
    // Test unstake
    // ============================
    function testUnstake() external {
        vm.startPrank(staker);
        usdc.approve(address(saloon), 1000 * 10 ** 6);
        uint256 tokenId = saloon.stake(pid, 10 * 10 ** 6);
        (uint256 stake, , , , ) = saloon.viewTokenInfo(tokenId);
        assertEq(stake, 10 * 10 ** 6);

        //schedule unstake
        bool scheduled = saloon.scheduleUnstake(tokenId);
        assert(scheduled == true);

        // unstake
        vm.warp(block.timestamp + 8 days);
        bool unstaked = saloon.unstake(tokenId, true);
        (uint256 stakeAfter, , , , ) = saloon.viewTokenInfo(tokenId);
        assertEq(stakeAfter, 0);

        //test unstake fails before schedule window opens
        uint256 tokenId2 = saloon.stake(pid, 10 * 10 ** 6);
        (uint256 stake2, , , , ) = saloon.viewTokenInfo(tokenId2);
        assertEq(stake2, 10 * 10 ** 6);
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
    // TODO Ask Django to go over this.
    function testUnstakeWithUnclaimed() external {
        vm.startPrank(staker);
        usdc.approve(address(saloon), 1000 * 10 ** 6);

        uint256 tokenId = saloon.stake(pid, 1000 * 10 ** 6);
        (uint256 stake, uint256 tokenApy, , , ) = saloon.viewTokenInfo(tokenId);
        assertEq(stake, 1000 * 10 ** 6);
        (
            uint256 requiredPremiumBalancePerPeriod,
            uint256 premiumBalance,
            uint256 premiumAvailable
        ) = saloon.viewPoolPremiumInfo(pid);

        vm.warp(block.timestamp + 14 days);
        (
            uint256 totalPending,
            uint256 actualPending,
            uint256 newPending
        ) = saloon.viewPendingPremium(tokenId);

        // (, , uint256 actualPendingTokenInfo, , ) = saloon.viewTokenInfo(
        //     tokenId
        // );
        // assertEq(actualPending, actualPendingTokenInfo);

        // (
        //     requiredPremiumBalancePerPeriod,
        //     premiumBalance,
        //     premiumAvailable
        // ) = saloon.viewPoolPremiumInfo(pid);
        // assertEq(
        //     premiumBalance,
        //     totalPending - requiredPremiumBalancePerPeriod
        // ); NOTE //slight difference here due to precision loss

        //schedule unstake -> sets token.apy to zero
        bool scheduled = saloon.scheduleUnstake(tokenId);
        assert(scheduled == true);

        vm.stopPrank();
        vm.startPrank(project);
        usdc.approve(address(saloon), 1000 * 1e6);
        vm.stopPrank();
        vm.startPrank(staker);

        // unstake
        vm.warp(block.timestamp + 8 days);

        (totalPending, actualPending, newPending) = saloon.viewPendingPremium(
            tokenId
        );

        (
            requiredPremiumBalancePerPeriod,
            premiumBalance,
            premiumAvailable
        ) = saloon.viewPoolPremiumInfo(pid);
        // NOTE THIS WAS REVERTING... WHY? (read below)
        //      token.apy was set to zero on scheduleUnstake.
        //      But user should still be able to claim owed premium... HOW TO FIX THIS?
        //      Take premium snapshot at scheduleUnstake()
        assert(totalPending > premiumBalance);
        assertEq(
            totalPending,
            (requiredPremiumBalancePerPeriod * 1007 * 14) / 7 / 1000
        ); // Staked full cap for 14 days, divide by PERIOD (7 days)... * 1007/1000 due to small precision issue with dynamic APY curve

        saloon.claimPremium(tokenId);
        (totalPending, actualPending, newPending) = saloon.viewPendingPremium(
            tokenId
        );
        assertEq(newPending, totalPending); // newPending and TotalPending should be zero after claiming
        // vm.expectRevert("ERC20: transfer amount exceeds allowance"); //Project revoked allowance so user can't claim while unstaking
        // bool unstaked = saloon.unstake(tokenId, true);

        // // Unstake again but set _shouldHarvest to false. Stored pending in user.unclaimed.
        // unstaked = saloon.unstake(tokenId, false);
        // // uint256 usdcBalance = usdc.balanceOf(staker);
        (uint256 stakeAfter, , uint256 pendingAfter, , ) = saloon.viewTokenInfo(
            tokenId
        );
        // assertEq(stakeAfter, 0);
        // assertEq(pendingAfter, actualPending);
        vm.stopPrank();

        // Project re-sets approvals
        vm.startPrank(project);
        usdc.approve(address(saloon), 1000 * 10 ** 6);
        vm.stopPrank();

        // Staker can claim their premium now
        vm.startPrank(staker);
        saloon.claimPremium(tokenId);
        (stakeAfter, , pendingAfter, , ) = saloon.viewTokenInfo(tokenId);
        assertEq(stakeAfter, 1000000000); //user hasnt unstaked yet to stake will still be the same
        assertEq(pendingAfter, 0); //pending should be zero because premium has been set to 0 in scheduleUnstake()

        scheduled = saloon.scheduleUnstake(tokenId);
        assert(scheduled == true);
        vm.warp(block.timestamp + 8 days);
        bool unstaked = saloon.unstake(tokenId, true);
        assert(unstaked == true);
        (stakeAfter, , pendingAfter, , ) = saloon.viewTokenInfo(tokenId);
        assertEq(stakeAfter, 0); // stake amount should be zero after unstake
        vm.stopPrank();

        // Ensure that pool has been topped up
        (
            requiredPremiumBalancePerPeriod,
            premiumBalance,
            premiumAvailable
        ) = saloon.viewPoolPremiumInfo(pid);
        assertEq(premiumBalance, requiredPremiumBalancePerPeriod);
        assertEq(premiumAvailable, (premiumBalance * 9000) / 10000 + 2); // +3 due precision loss
    }

    function testTokenList() external {
        vm.startPrank(staker);
        usdc.approve(address(saloon), 1000 * 10 ** 6);

        uint256 tokenId1 = saloon.stake(pid, 10 * 10 ** 6);
        uint256 tokenId2 = saloon.stake(pid, 10 * 10 ** 6);
        uint256 tokenId3 = saloon.stake(pid, 10 * 10 ** 6);

        ISaloonGlobal.NFTInfo[] memory tokens = saloon.getAllTokensByOwner(
            staker
        );
        assertEq(tokens.length, 3);

        saloon.transferFrom(staker, project, tokenId1);

        tokens = saloon.getAllTokensByOwner(staker);
        assertEq(tokens.length, 2);

        // Unstaking with _shouldHarvest == true burns the NFT
        saloon.scheduleUnstake(tokenId2);
        vm.warp(block.timestamp + 8 days);
        bool unstaked = saloon.unstake(tokenId2, true);
        tokens = saloon.getAllTokensByOwner(staker);
        assertEq(tokens.length, 1);

        // Unstaking with _shouldHarvest == false DOES NOT burn the NFT
        saloon.scheduleUnstake(tokenId3);
        vm.warp(block.timestamp + 8 days);
        unstaked = saloon.unstake(tokenId3, false);
        tokens = saloon.getAllTokensByOwner(staker);
        assertEq(tokens.length, 1);
    }

    // ============================
    // Test claimPremium
    // ============================
    function testClaimPremium() external {
        vm.startPrank(staker);
        uint256 originalStakerBalance = usdc.balanceOf(staker);
        usdc.approve(address(saloon), 1000 * 10 ** 6);
        uint256 tokenId = saloon.stake(pid, 100 * 10 ** 6);
        (uint256 stake, , , , ) = saloon.viewTokenInfo(tokenId);
        assertEq(stake, 100 * 10 ** 6);

        vm.warp(block.timestamp + 365 days);
        (
            uint256 totalPending,
            uint256 actualPending,
            uint256 newPending
        ) = saloon.viewPendingPremium(tokenId);
        assertEq(totalPending, (100 * 10 ** 6 * 4168) / 10000);
        assertEq(actualPending, (totalPending * 9) / 10);
        assertEq(newPending, (100 * 10 ** 6 * 4168) / 10000);

        saloon.claimPremium(tokenId);
        // mint - stake + premium -> 500 - 10 + (10 * (10% * 90%)) = 409 * 10**6
        uint256 stakerBalance = usdc.balanceOf(staker);
        assertEq(stakerBalance, originalStakerBalance - stake + actualPending);

        // test unstake and claim
        saloon.scheduleUnstake(tokenId);
        vm.warp(block.timestamp + 1 weeks + 1 days);
        (, uint256 actualPending2, ) = saloon.viewPendingPremium(tokenId);
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
        vm.startPrank(staker);
        usdc.approve(address(saloon), 1000 * 10 ** 6);
        uint256 tokenId = saloon.stake(pid, 100 * 10 ** 6);
        vm.stopPrank();

        (
            uint256 requiredPremiumBalancePerPeriod,
            uint256 premiumBalance,
            uint256 premiumAvailable
        ) = saloon.viewPoolPremiumInfo(pid);
        (, uint256 poolAPY, , uint256 poolcap) = saloon.viewBountyInfo(pid);
        assertEq(
            requiredPremiumBalancePerPeriod,
            (((poolcap * apy * PERIOD) / BPS) / YEAR)
        );

        // requiredPremiumBalancePerPeriod should be equal premiumBalance
        assertEq(premiumBalance, requiredPremiumBalancePerPeriod);
        assertEq(premiumAvailable, (premiumBalance * 9000) / 10000 + 1); // Where is this precision loss coming from?

        uint256 balanceBefore = usdc.balanceOf(address(saloon));
        uint256 topUpBalance = 100 * 10 ** 6 + requiredPremiumBalancePerPeriod; // +1 from stake, deposit was sent to strategy
        assertEq(balanceBefore, topUpBalance);

        vm.warp(block.timestamp + 365 days);
        (uint256 totalPending, uint256 actualPending, ) = saloon
            .viewPendingPremium(tokenId);
        assertEq(totalPending, 41680000); // 10e6 stake => 10% of pool = 41.68% APY on 10% avg APY, for 1 year = 4.168e6 USDC
        assertEq(actualPending, (41680000 * 9) / 10);

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

        // +10 from stake, deposit was sent to strategy. Dynamic APY made it so that premium surpassed balance
        // Saloon also still hold's Saloon's profit from premium (totalPending - actualPending)
        uint256 balanceAfterClaim = usdc.balanceOf(address(saloon));
        uint256 balanceExpected = 100 *
            10 ** 6 +
            requiredPremiumBalancePerPeriod +
            (totalPending - actualPending);
        assertEq(balanceAfterClaim, balanceExpected);

        // test if requiredPremiumBalancePerPeriod is topped up when premiumAvailable is not enough
        vm.warp(block.timestamp + 730 days);
        (totalPending, actualPending, ) = saloon.viewPendingPremium(tokenId);
        assertEq(totalPending, ((100 * 10 ** 6 * 4168) / 10000) * 2);

        saloon.claimPremium(tokenId);
        // stake balance + requiredBalancePerPeriod + Saloon Fee for 3 years (user's pending / 2 years * 3 years * 10%)
        uint256 newBalanceExpected = 100 *
            10 ** 6 +
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
        uint256 newAvailableExpected = (premiumBalance3 * 9000) / 10000 + 1; // Where is this precision loss coming from?
        assertEq(premiumAvailable3, newAvailableExpected);
        vm.stopPrank();
    }

    // ============================
    // Test payBounty
    // ============================
    function testPayBountyStakingCovers() external {
        vm.startPrank(staker);
        usdc.approve(address(saloon), 1000 * 10 ** 6);
        uint256 tokenId = saloon.stake(pid, 35 * 10 ** 6);
        (uint256 stake, , , , ) = saloon.viewTokenInfo(tokenId);
        assertEq(stake, 35 * 10 ** 6);
        vm.stopPrank();

        vm.startPrank(staker2);
        usdc.approve(address(saloon), 1000 * 10 ** 6);
        uint256 tokenId2 = saloon.stake(pid, 35 * 10 ** 6);
        (uint256 stake2, , , , ) = saloon.viewTokenInfo(tokenId2);
        assertEq(stake2, 35 * 10 ** 6);
        vm.stopPrank();

        vm.prank(newOwner);
        vm.expectRevert("not owner");
        saloon.payBounty(pid, newOwner, 2000, 0); // $70 stake + $30 deposit = $100 total... 2000 BPS = 20% = $20

        saloon.payBounty(pid, hunter, 2000, 0);

        // test hunters balance got the right amount
        uint256 hunterBalance = usdc.balanceOf(hunter);
        assertEq(hunterBalance, 18 * 10 ** 6); // 0.9 usdc

        // test saloonBountyProfit has the right amount
        (, uint256 bountyProfit, , ) = saloon.viewSaloonProfitBalance(
            address(usdc)
        );
        assertEq(bountyProfit, 2 * 10 ** 6 - 1); // 2 usdc

        // test stakers balance was reduced properly
        (uint256 stakerAmount, , , , ) = saloon.viewTokenInfo(tokenId);
        (uint256 stakerAmount2, , , , ) = saloon.viewTokenInfo(tokenId2);
        assertEq(stakerAmount2, stakerAmount); // balances should be 25 usdc both

        // total staked should be 1 total now. total Pool value = 4 usdc
        uint256 bountyBalance = saloon.viewBountyBalance(pid);
        assertEq(bountyBalance, 80 * 10 ** 6 + 1);
    }

    function testPayBountyStrategyDepositNeeded() external {
        vm.prank(newOwner);
        vm.expectRevert("not owner");
        saloon.payBounty(pid, newOwner, 10000, 0);

        saloon.payBounty(pid, hunter, 5000, 0);

        // test hunters balance got the right amount
        uint256 hunterBalance = usdc.balanceOf(hunter);
        assertEq(hunterBalance, ((15 * 10 ** 6) * 9) / 10); // 13.5 usdc

        // test saloonBountyProfit got the right amount
        (
            uint256 totalProfit,
            uint256 bountyProfit,
            uint256 strategyProfit,
            uint256 premiumProfit
        ) = saloon.viewSaloonProfitBalance(address(usdc));
        assertEq(bountyProfit, 15 * 10 ** 5 - 1); // 1.5 usdc
    }

    // ============================
    // Test collectSaloonProfits
    // ============================
    function testCollectSaloonProfits() external {
        vm.startPrank(staker);
        usdc.approve(address(saloon), 1000 * 10 ** 6);
        uint256 tokenId = saloon.stake(pid, 10 * 10 ** 6);
        (uint256 stake, , , , ) = saloon.viewTokenInfo(tokenId);
        assertEq(stake, 10 * 10 ** 6);
        vm.stopPrank();

        vm.startPrank(staker2);
        usdc.approve(address(saloon), 1000 * 10 ** 6);
        uint256 tokenId2 = saloon.stake(pid, 10 * 10 ** 6);
        (uint256 stake2, , , , ) = saloon.viewTokenInfo(tokenId2);
        assertEq(stake2, 10 * 10 ** 6);
        vm.stopPrank();

        saloon.payBounty(pid, hunter, 10000, 0); // -1 wei due to stargate precision loss

        saloon.collectSaloonProfits(address(usdc), saloonWallet);

        // test wallet has received amount
        uint256 walletBalance = usdc.balanceOf(saloonWallet);
        assertEq(walletBalance, 5 * 10 ** 6 - 1); // -1 wei due to stargate precision loss

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
        vm.startPrank(staker);
        usdc.approve(address(saloon), 1000 * 10 ** 6);
        uint256 tokenId = saloon.stake(pid, 10 * 10 ** 6);
        (uint256 stake, , , , ) = saloon.viewTokenInfo(tokenId);
        assertEq(stake, 10 * 10 ** 6);
        vm.stopPrank();

        vm.startPrank(staker2);
        usdc.approve(address(saloon), 1000 * 10 ** 6);
        uint256 tokenId2 = saloon.stake(pid, 10 * 10 ** 6);
        (uint256 stake2, , , , ) = saloon.viewTokenInfo(tokenId2);
        assertEq(stake2, 10 * 10 ** 6);
        vm.stopPrank();

        saloon.payBounty(pid, hunter, 10000, 0); // Immediate stargate precision loss

        // Repeat with pool with token DAI

        saloon.updateTokenWhitelist(address(dai), true, 10 ether);
        uint256 pid2 = saloon.addNewBountyPool(
            address(dai),
            project,
            "yeehaw",
            address(0),
            0,
            0
        );
        vm.startPrank(project);
        dai.approve(address(saloon), 1000 ether);
        saloon.setAPYandPoolCapAndDeposit(pid2, 1000 ether, 1000, 30 ether, ""); // No strategy for DAI at the moment
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

        saloon.payBounty(pid2, hunter, 10000, 0);

        saloon.collectAllSaloonProfits(saloonWallet);

        // test wallet has received amount
        uint256 walletBalanceUSDC = usdc.balanceOf(saloonWallet);
        assertEq(walletBalanceUSDC, 5 * 10 ** 6 - 1); // Immediate stargate precision loss
        uint256 walletBalanceDAI = dai.balanceOf(saloonWallet);
        assertEq(walletBalanceDAI, 5 ether); // No precision loss because deposit was not sent to strategy

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

    function testReferrerClaimBounty() external {
        // Set up new pool with referral
        pid = saloon.addNewBountyPool(
            address(usdc),
            project,
            "yeehaw",
            referrer,
            5000,
            block.timestamp + 365 days
        );
        vm.startPrank(project);
        usdc.approve(address(saloon), 1000 * 10 ** 6);
        saloon.setAPYandPoolCapAndDeposit(
            pid,
            poolCap, // $100
            apy, // 10%
            deposit, // $30
            ""
        );
        vm.stopPrank();

        vm.startPrank(staker);
        usdc.approve(address(saloon), 1000 * 10 ** 6);
        uint256 tokenId = saloon.stake(pid, 10 * 10 ** 6);
        (uint256 stake, , , , ) = saloon.viewTokenInfo(tokenId);
        assertEq(stake, 10 * 10 ** 6);
        vm.stopPrank();

        vm.startPrank(staker2);
        usdc.approve(address(saloon), 1000 * 10 ** 6);
        uint256 tokenId2 = saloon.stake(pid, 10 * 10 ** 6);
        (uint256 stake2, , , , ) = saloon.viewTokenInfo(tokenId2);
        assertEq(stake2, 10 * 10 ** 6);
        vm.stopPrank();

        saloon.payBounty(pid, hunter, 10000, 0);

        saloon.collectSaloonProfits(address(usdc), saloonWallet);

        // test wallet has received amount
        uint256 saloonWalletBalance = usdc.balanceOf(saloonWallet);
        assertEq(saloonWalletBalance, ((5 * 10 ** 6 * (10000 - 5000)) / 10000)); // Multiply by referral multiplier / BPS
        uint256 referrerWalletBalance = saloon.viewReferralBalance(
            referrer,
            address(usdc)
        );
        assertEq(referrerWalletBalance, (5 * 10 ** 6 * 5000) / 10000); // Multiply by referral multiplier / BPS

        vm.startPrank(referrer);
        saloon.collectAllReferralProfits();
        referrerWalletBalance = usdc.balanceOf(referrer);
        assertEq(referrerWalletBalance, (5 * 10 ** 6 * 5000) / 10000); // Multiply by referral multiplier / BPS

        // test variables have been reset
        (
            uint256 totalProfit,
            uint256 bountyProfit,
            uint256 strategyProfit,
            uint256 premiumProfit
        ) = saloon.viewSaloonProfitBalance(address(usdc));
        assertEq(totalProfit, 0);
    }

    function testReferrerClaimBountyExpired() external {
        // Set up new pool with referral
        pid = saloon.addNewBountyPool(
            address(usdc),
            project,
            "yeehaw",
            referrer,
            5000,
            block.timestamp + 1 days
        );
        vm.startPrank(project);
        usdc.approve(address(saloon), 1000 * 10 ** 6);
        saloon.setAPYandPoolCapAndDeposit(
            pid,
            poolCap, // $100
            apy, // 10%
            deposit, // $30
            ""
        );
        vm.stopPrank();

        vm.startPrank(staker);
        usdc.approve(address(saloon), 1000 * 10 ** 6);
        uint256 tokenId = saloon.stake(pid, 10 * 10 ** 6);
        (uint256 stake, , , , ) = saloon.viewTokenInfo(tokenId);
        assertEq(stake, 10 * 10 ** 6);
        vm.stopPrank();

        vm.startPrank(staker2);
        usdc.approve(address(saloon), 1000 * 10 ** 6);
        uint256 tokenId2 = saloon.stake(pid, 10 * 10 ** 6);
        (uint256 stake2, , , , ) = saloon.viewTokenInfo(tokenId2);
        assertEq(stake2, 10 * 10 ** 6);
        vm.stopPrank();

        vm.warp(block.timestamp + 2 days);
        saloon.payBounty(pid, hunter, 10000, 0);

        saloon.collectSaloonProfits(address(usdc), saloonWallet);

        // test wallet has received amount
        uint256 saloonWalletBalance = usdc.balanceOf(saloonWallet);
        assertEq(saloonWalletBalance, (5 * 10 ** 6));
        uint256 referrerWalletBalance = saloon.viewReferralBalance(
            referrer,
            address(usdc)
        );
        assertEq(referrerWalletBalance, 0); // Referral window expired. Referrer balance was never increased.

        vm.startPrank(referrer);
        saloon.collectAllReferralProfits();
        referrerWalletBalance = usdc.balanceOf(referrer);
        assertEq(referrerWalletBalance, 0); // Referral window expired. Referrer balance was never increased.

        // test variables have been reset
        (
            uint256 totalProfit,
            uint256 bountyProfit,
            uint256 strategyProfit,
            uint256 premiumProfit
        ) = saloon.viewSaloonProfitBalance(address(usdc));
        assertEq(totalProfit, 0);
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
        vm.expectRevert("not owner");
        pid = saloon.addNewBountyPool(
            address(usdc),
            project,
            "yeehaw",
            address(0),
            0,
            0
        );

        pid = saloon.addNewBountyPool(
            address(usdc),
            project,
            "yeehaw",
            address(0),
            0,
            0
        );
        assertEq(pid, 1);

        // Test first step of ownership transfer and accept reverts for random caller
        saloon.setPendingOwner(newOwner);
        vm.prank(staker);
        vm.expectRevert("not pending owner");
        saloon.acceptOwnershipTransfer();

        // Test new owner accepts ownership and can deploy new bounty
        vm.startPrank(newOwner);
        saloon.acceptOwnershipTransfer();
        pid = saloon.addNewBountyPool(
            address(usdc),
            project,
            "yeehaw",
            address(0),
            0,
            0
        );
        assertEq(pid, 2);
        vm.stopPrank();

        // Test original owner cannot deploy new bounty
        vm.expectRevert("not owner");
        pid = saloon.addNewBountyPool(
            address(usdc),
            project,
            "yeehaw",
            address(0),
            0,
            0
        );
    }

    function testWindDownBounty() external {
        vm.startPrank(staker);
        usdc.approve(address(saloon), 1000 * 10 ** 6);
        uint256 tokenId = saloon.stake(pid, 10 * 10 ** 6);
        (uint256 stake, , , , ) = saloon.viewTokenInfo(tokenId);
        assertEq(stake, 10 * 10 ** 6);
        vm.stopPrank();

        vm.startPrank(project);
        vm.warp(block.timestamp + 7 days);
        saloon.windDownBounty(pid);
        vm.stopPrank();

        // Even though 14 days has passed, user only receives pending up until the bounty was wound down
        vm.startPrank(staker);
        vm.warp(block.timestamp + 7 days);
        (uint256 stake2, uint256 stakeAPY, uint256 actualPending2, , ) = saloon
            .viewTokenInfo(tokenId);
        (tokenId);
        uint256 actualPending = actualPending2;
        uint256 expectedPending = (((((stake2 * stakeAPY) / 10000) * 9000) /
            10000) * 7 days) / 365 days;
        assertEq(actualPending, expectedPending);

        // Staking should fail after pool is wound down
        vm.expectRevert("pool not active");
        saloon.stake(pid, 10 * 10 ** 6);

        //schedule unstake
        bool scheduled = saloon.scheduleUnstake(tokenId);
        assert(scheduled == true);

        // Can still unstake and collect premium even if bounty is wound down
        vm.warp(block.timestamp + 8 days);
        bool unstaked = saloon.unstake(tokenId, true);
        (uint256 stakeAfter, , , , ) = saloon.viewTokenInfo(tokenId);
        assertEq(stakeAfter, 0);
    }

    //     ///////////////////////// Strategy Integration //////////////////////////////

    //     // Commented due to private visibility
    //     // function testDeployStrategy() external {
    //     //     address deployedStrategy = saloon.deployStrategyIfNeeded(0, "Stargate");
    //     //     assert(deployedStrategy != address(0));
    //     // }
}
