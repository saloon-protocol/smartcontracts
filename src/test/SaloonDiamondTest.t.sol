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
import "forge-std/Test.sol";

contract SaloonDiamondTest is DSTest, Script, Test {
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
    address securityCouncilMember1 = address(0x5EC1);
    address securityCouncilMember2 = address(0x5EC2);

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

        // Check inital length of facets
        uint initialFacetsLength = IGetters(address(saloonProxy))
            .facetAddresses()
            .length;
        assertEq(initialFacetsLength, 2);

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
        managerFacet.selectors.push(
            IManagerFacet.setUpgradePeriodAndNumberOfApprovals.selector
        );
        managerFacet.selectors.push(
            IManagerFacet.setSecurityCouncilMembers.selector
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
        bountyFacet.isFreezable = true;

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

        // Propose facets
        IDiamondCut(address(saloonProxy)).proposeDiamondCut(
            proposeFacets,
            address(0x0)
        );

        executeFacets.initAddress = address(0x0);
        executeFacets.initCalldata = "";

        // Approve facets for instant execution
        vm.prank(securityCouncilMember1);
        IDiamondCut(address(saloonProxy))
            .approveEmergencyDiamondCutAsSecurityCouncilMember(
                keccak256(abi.encode(proposeFacets, address(0x0)))
            );
        vm.prank(securityCouncilMember2);
        IDiamondCut(address(saloonProxy))
            .approveEmergencyDiamondCutAsSecurityCouncilMember(
                keccak256(abi.encode(proposeFacets, address(0x0)))
            );

        // Execute addition of facets to diamond
        IDiamondCut(address(saloonProxy)).executeDiamondCutProposal(
            executeFacets
        );

        // Check new length of facets
        uint newFacetsLength = IGetters(address(saloonProxy))
            .facetAddresses()
            .length;
        uint diff = 4 + initialFacetsLength;
        assertEq(newFacetsLength, diff);

        // Set variables and approve token
        StrategyFactory factory = new StrategyFactory();
        saloon.setStrategyFactory(address(factory));
        saloon.setUpgradePeriodAndNumberOfApprovals();
        saloon.setLibSaloonStorage();

        // Reset variables to make tests more succint
        delete proposeFacets;
        delete executeFacets.facetCuts;
    }

    // ========================================================
    //        Test Setup
    // ========================================================
    function test_Setup() external {
        assertEq(address(saloon), address(saloonProxy));
    }

    // ========================================================
    //        Revert on adding existent selectors
    // ========================================================
    function test_RevertOnAddingExistentSelector() external {
        delete viewFacet.selectors;
        viewFacet.selectors.push(IViewFacet.getAllTokensByOwner.selector);

        proposeFacets.push(viewFacet);

        executeFacets.facetCuts.push(viewFacet);

        // Propose facets
        IDiamondCut(address(saloonProxy)).proposeDiamondCut(
            proposeFacets,
            address(0x0)
        );
        emit log_named_uint("before", block.timestamp);

        //warp
        skip(7 days);

        emit log_named_uint("after", block.timestamp);

        // Execute addition of facets to diamond
        vm.expectRevert(); // J
        IDiamondCut(address(saloonProxy)).executeDiamondCutProposal(
            executeFacets
        );
    }

    // ========================================================
    //        Revert on add zero address Facet
    // ========================================================
    Diamond.FacetCut emptyFacet;

    function test_RevertZeroAddressFacet() external {
        emptyFacet.facet = address(0x0);
        emptyFacet.action = Diamond.Action.Add;
        emptyFacet.isFreezable = false;
        emptyFacet.selectors.push(
            bytes4(keccak256("empty(address,address,uint256)"))
        );

        proposeFacets.push(emptyFacet);

        executeFacets.facetCuts.push(emptyFacet);

        // Propose facets
        IDiamondCut(address(saloonProxy)).proposeDiamondCut(
            proposeFacets,
            address(0x0)
        );
        emit log_named_uint("before", block.timestamp);

        //warp
        skip(7 days);

        emit log_named_uint("after", block.timestamp);

        // Execute addition of facets to diamond
        vm.expectRevert(); // G
        IDiamondCut(address(saloonProxy)).executeDiamondCutProposal(
            executeFacets
        );
    }

    // ========================================================
    //        Revert on replace facets with zero address
    // ========================================================
    function test_RevertOnReplaceFacetsZeroAddress() external {
        viewFacet.facet = address(0x0);

        viewFacet.action = Diamond.Action.Replace;

        proposeFacets.push(viewFacet);

        executeFacets.facetCuts.push(viewFacet);

        // Propose facets
        IDiamondCut(address(saloonProxy)).proposeDiamondCut(
            proposeFacets,
            address(0x0)
        );

        //warp
        skip(7 days);

        // Execute addition of facets to diamond
        vm.expectRevert(); // K
        IDiamondCut(address(saloonProxy)).executeDiamondCutProposal(
            executeFacets
        );
    }

    // ========================================================
    //        Revert on replace non-existent selector
    // ========================================================
    function test_RevertOnReplaceNonExistentSelector() external {
        viewFacet.action = Diamond.Action.Replace;
        viewFacet.selectors.push(
            bytes4(keccak256("madeUp(address,address,uint256)"))
        );

        proposeFacets.push(viewFacet);

        executeFacets.facetCuts.push(viewFacet);

        // Propose facets
        IDiamondCut(address(saloonProxy)).proposeDiamondCut(
            proposeFacets,
            address(0x0)
        );

        //warp
        skip(7 days);

        // Execute addition of facets to diamond
        vm.expectRevert(); // L
        IDiamondCut(address(saloonProxy)).executeDiamondCutProposal(
            executeFacets
        );
    }

    // ========================================================
    //        Revert on remove non-existent selector
    // ========================================================
    function test_RevertOnRemoveNonExistentSelector() external {
        viewFacet.action = Diamond.Action.Remove;
        viewFacet.selectors.push(
            bytes4(keccak256("madeUp(address,address,uint256)"))
        );

        proposeFacets.push(viewFacet);

        executeFacets.facetCuts.push(viewFacet);

        // Propose facets
        IDiamondCut(address(saloonProxy)).proposeDiamondCut(
            proposeFacets,
            address(0x0)
        );

        //warp
        skip(7 days);

        // Execute addition of facets to diamond
        vm.expectRevert(); // a1
        IDiamondCut(address(saloonProxy)).executeDiamondCutProposal(
            executeFacets
        );
    }

    // ========================================================
    //        Replace facet for existent selector
    // ========================================================
    function test_ReplaceFacetForExistentSelector() external {
        viewFacet.action = Diamond.Action.Replace;

        proposeFacets.push(viewFacet);

        executeFacets.facetCuts.push(viewFacet);

        // Propose facets
        IDiamondCut(address(saloonProxy)).proposeDiamondCut(
            proposeFacets,
            address(0x0)
        );

        //warp
        skip(7 days);

        // Execute addition of facets to diamond
        IDiamondCut(address(saloonProxy)).executeDiamondCutProposal(
            executeFacets
        );
    }

    // ========================================================
    //        Remove facet for existent selector
    // ========================================================
    function test_RemoveFacetForExistentSelector() external {
        viewFacet.action = Diamond.Action.Remove;
        viewFacet.facet = address(0x0);

        proposeFacets.push(viewFacet);
        executeFacets.facetCuts.push(viewFacet);

        // Propose facets
        IDiamondCut(address(saloonProxy)).proposeDiamondCut(
            proposeFacets,
            address(0x0)
        );

        //warp
        skip(7 days);

        // Execute addition of facets to diamond
        IDiamondCut(address(saloonProxy)).executeDiamondCutProposal(
            executeFacets
        );
    }

    // ========================================================
    //        Add facet after removing it
    // ========================================================
    function test_RemoveAndAddFacet() external {
        //// REMOVE /////
        viewFacet.action = Diamond.Action.Remove;
        viewFacet.facet = address(0x0);
        proposeFacets.push(viewFacet);
        executeFacets.facetCuts.push(viewFacet);
        // Propose facets
        IDiamondCut(address(saloonProxy)).proposeDiamondCut(
            proposeFacets,
            address(0x0)
        );
        skip(7 days);
        // Execute addition of facets to diamond
        IDiamondCut(address(saloonProxy)).executeDiamondCutProposal(
            executeFacets
        );

        //// ADD /////
        delete proposeFacets;
        delete executeFacets.facetCuts;
        viewFacet.facet = address(saloonView);
        viewFacet.action = Diamond.Action.Add;
        proposeFacets.push(viewFacet);
        executeFacets.facetCuts.push(viewFacet);
        // Propose facets
        IDiamondCut(address(saloonProxy)).proposeDiamondCut(
            proposeFacets,
            address(0x0)
        );
        skip(7 days);
        // Execute addition of facets to diamond
        IDiamondCut(address(saloonProxy)).executeDiamondCutProposal(
            executeFacets
        );
    }

    // ========================================================
    //        Revert adding facet with different freezability
    // ========================================================
    function test_RevertAddingFacetWithDifferentFeezability() external {
        viewFacet.action = Diamond.Action.Add;
        viewFacet.isFreezable = true;
        delete viewFacet.selectors;
        viewFacet.selectors.push(
            bytes4(keccak256("madeUp(address,address,uint256)"))
        );

        proposeFacets.push(viewFacet);
        executeFacets.facetCuts.push(viewFacet);

        // Propose facets
        IDiamondCut(address(saloonProxy)).proposeDiamondCut(
            proposeFacets,
            address(0x0)
        );

        //warp
        skip(7 days);

        // Execute addition of facets to diamond
        vm.expectRevert(); // J1
        IDiamondCut(address(saloonProxy)).executeDiamondCutProposal(
            executeFacets
        );
    }

    // ========================================================
    //        Revert replaceing facet with different freezability
    // ========================================================
    function test_RevertReplacingFacetWithDifferentFeezability() external {
        viewFacet.action = Diamond.Action.Replace;
        viewFacet.isFreezable = true;

        proposeFacets.push(viewFacet);
        executeFacets.facetCuts.push(viewFacet);

        // Propose facets
        IDiamondCut(address(saloonProxy)).proposeDiamondCut(
            proposeFacets,
            address(0x0)
        );
        skip(7 days);
        // Execute addition of facets to diamond
        vm.expectRevert(); // J1
        IDiamondCut(address(saloonProxy)).executeDiamondCutProposal(
            executeFacets
        );
    }

    // ========================================================
    //        Change freezability of facet
    // ========================================================
    function test_ChangeFacetFeezability() external {
        //// REMOVE /////
        viewFacet.action = Diamond.Action.Remove;
        viewFacet.facet = address(0x0);
        proposeFacets.push(viewFacet);
        executeFacets.facetCuts.push(viewFacet);
        // Propose facets
        IDiamondCut(address(saloonProxy)).proposeDiamondCut(
            proposeFacets,
            address(0x0)
        );
        skip(7 days);
        // Execute addition of facets to diamond
        IDiamondCut(address(saloonProxy)).executeDiamondCutProposal(
            executeFacets
        );

        //// ADD /////
        delete proposeFacets;
        delete executeFacets.facetCuts;
        viewFacet.facet = address(saloonView);
        viewFacet.action = Diamond.Action.Add;
        viewFacet.isFreezable = true;
        proposeFacets.push(viewFacet);
        executeFacets.facetCuts.push(viewFacet);
        // Propose facets
        IDiamondCut(address(saloonProxy)).proposeDiamondCut(
            proposeFacets,
            address(0x0)
        );
        skip(7 days);
        // Execute addition of facets to diamond
        IDiamondCut(address(saloonProxy)).executeDiamondCutProposal(
            executeFacets
        );
    }

    // ========================================================
    //        Revert emergency freeze when not owner
    // ========================================================
    function test_RevertEmergencyFreezeWhenNotOwner() external {
        vm.prank(project);
        vm.expectRevert(); // not owner
        IDiamondCut(address(saloonProxy)).emergencyFreezeDiamond();
    }

    // ========================================================
    //        Emergency freeze and unfreeze if owner
    // ========================================================
    function test_EmergencyFreezeAndUnfreeze() external {
        IDiamondCut(address(saloonProxy)).emergencyFreezeDiamond();
        IDiamondCut(address(saloonProxy)).unfreezeDiamond();
    }

    // ========================================================
    //      Call unfreezable facet after freezingDiamond
    // ========================================================
    function test_CallUnfreezableWhenFrozen() external {
        IDiamondCut(address(saloonProxy)).emergencyFreezeDiamond();
        saloon.updateTokenWhitelist(address(dai), false, 0);
    }

    // ========================================================
    // Revert on executing unapproved proposal when diamondStorage frozen
    // ========================================================
    function test_RevertOnUnapprovedProposalWhenFrozen() external {
        viewFacet.action = Diamond.Action.Add;
        viewFacet.isFreezable = true;
        delete viewFacet.selectors;
        viewFacet.selectors.push(
            bytes4(keccak256("madeUp(address,address,uint256)"))
        );

        proposeFacets.push(viewFacet);
        executeFacets.facetCuts.push(viewFacet);
        // Propose facets
        IDiamondCut(address(saloonProxy)).proposeDiamondCut(
            proposeFacets,
            address(0x0)
        );

        //// FREEZE /////
        IDiamondCut(address(saloonProxy)).emergencyFreezeDiamond();

        skip(7 days);

        vm.expectRevert(); //f3
        // Execute addition of facets to diamond
        IDiamondCut(address(saloonProxy)).executeDiamondCutProposal(
            executeFacets
        );
    }

    // ========================================================
    // Revert on executing proposal when proposalHash doesnt match
    // ========================================================
    function test_RevertWhenHashDoesntMatch() external {
        proposeFacets.push(viewFacet);
        executeFacets.facetCuts.push(viewFacet);
        executeFacets.initAddress = address(0x01);

        // Propose facets
        IDiamondCut(address(saloonProxy)).proposeDiamondCut(
            proposeFacets,
            address(0x0)
        );

        skip(7 days);

        vm.expectRevert(); //a4
        // Execute addition of facets to diamond
        IDiamondCut(address(saloonProxy)).executeDiamondCutProposal(
            executeFacets
        );

        delete executeFacets;
        executeFacets.facetCuts.push(bountyFacet);
        executeFacets.initAddress = address(0x0);

        skip(7 days);

        vm.expectRevert(); //a4
        // Execute addition of facets to diamond
        IDiamondCut(address(saloonProxy)).executeDiamondCutProposal(
            executeFacets
        );
    }

    // ========================================================
    //      Revert on cancelling empty proposal
    // ========================================================
    function test_RevertOnCancellingEmptyProposal() external {
        vm.expectRevert(); // g1
        IDiamondCut(address(saloonProxy)).cancelDiamondCutProposal();
    }

    // ========================================================
    //      Revert on exeucting proposal twice
    // ========================================================
    function test_RevertOnExecutingSameProposalTwice() external {
        viewFacet.action = Diamond.Action.Replace;

        proposeFacets.push(viewFacet);

        executeFacets.facetCuts.push(viewFacet);

        // Propose facets
        IDiamondCut(address(saloonProxy)).proposeDiamondCut(
            proposeFacets,
            address(0x0)
        );

        //warp
        skip(7 days);

        // Execute addition of facets to diamond
        IDiamondCut(address(saloonProxy)).executeDiamondCutProposal(
            executeFacets
        );

        vm.expectRevert(); // a4
        IDiamondCut(address(saloonProxy)).executeDiamondCutProposal(
            executeFacets
        );
    }
}
