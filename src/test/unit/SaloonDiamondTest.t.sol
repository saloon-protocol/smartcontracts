// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../Prepare.t.sol";

contract SaloonDiamondTest is Prepare_Test {
    function setUp() public virtual override {
        Prepare_Test.setUp();

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
