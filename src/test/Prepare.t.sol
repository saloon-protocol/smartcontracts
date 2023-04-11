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

import "forge-std/Test.sol";
import "forge-std/Script.sol";

import "../lib/ERC20.sol";

// import "../lib/LibSaloon.sol";

abstract contract Prepare_Test is Test, Script {
    bytes data = "";

    ERC20 internal usdc = new ERC20("USDC", "USDC", 6);
    ERC20 internal dai = new ERC20("Dai Stablecoin", "DAI", 6);

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
    uint constant DEFAULT_APY = 1.06 ether;
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

    function setUp() public virtual {
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

        //// Label Addresses /////// todo
        vm.label({account: address(this), newLabel: "Owner"});
        vm.label({account: address(usdc), newLabel: "USDC"});
        vm.label({account: address(dai), newLabel: "DAI"});
        vm.label({account: staker, newLabel: "Staker 1"});
        vm.label({account: staker, newLabel: "Staker 2"});
        vm.label({account: address(saloon), newLabel: "Saloon"});

        deployer = address(this);

        deployProtocol();
    }

    function deployProtocol() public {
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
    }
}
