// SPDX-License-Identifier: MIT
pragma solidity ^0.8.1;

import "../src/DiamondCut.sol";
import "../src/DiamondInit.sol";
import "../src/Base.sol";

import "../src/DiamondProxy.sol";
import "../src/ManagerFacet.sol";
import "../src/ProjectFacet.sol";
import "../src/BountyFacet.sol";
import "../src/ViewFacet.sol";
import "../src/Getters.sol";

import "../src/interfaces/ISaloonGlobal.sol";

import "../src/StrategyFactory.sol";

import "../src/interfaces/IStrategyFactory.sol";
import "../src/interfaces/IDiamondCut.sol";
import "../src/lib/Diamond.sol";
// import "../src/lib/ERC20.sol";
import "ds-test/test.sol";
import "forge-std/Script.sol";
import "../src/StrategyFactory.sol";
import "openzeppelin-contracts/contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";

contract Deploy is Script {
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

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("TEST_PRIVATE_KEY"); // Testnet
        vm.startBroadcast(deployerPrivateKey);

        ERC20PresetFixedSupply USDC = ERC20PresetFixedSupply(
            0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d
        ); // Mainnet
        // address projectWallet = 0x84bB382457299Ed13E946529E010ee54Cfa047ab; // Mainnet
        address saloonWallet = 0x1D3a03a07F6993561c63A472Ca6FAd39cA218b78; // Testnet
        bytes memory data = "";

        getters = new GettersFacet();
        diamondCut = new DiamondCutFacet();
        DiamondInit diamondInit = new DiamondInit();

        bytes memory initData = abi.encodeWithSignature(
            "initialize(address)",
            saloonWallet
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
        vm.stopBroadcast();
    }
}
