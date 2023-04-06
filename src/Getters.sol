// SPDX-License-Identifier: MIT OR Apache-2.0

pragma solidity ^0.8.0;

import "./Base.sol";
import "./lib/Diamond.sol";
import "./lib/UncheckedMath.sol";
import "./interfaces/IGetters.sol";

/// @title Getters Contract implements functions for getting contract state from outside the blockchain.
/// @author Matter Labs
contract GettersFacet is Base, IGetters {
    using UncheckedMath for uint256;

    /*//////////////////////////////////////////////////////////////
                            CUSTOM GETTERS
    //////////////////////////////////////////////////////////////*/

    /// @return The address of the current governor
    function getOwner() external view returns (address) {
        return s.owner;
    }

    /// @return The address of the pending governor
    function getPendingOwner() external view returns (address) {
        return s.pendingOwner;
    }

    /// @return The hash of the diamond cut if there is an active upgrade and zero otherwise
    function getProposedDiamondCutHash() external view returns (bytes32) {
        return s.diamondCutStorage.proposedDiamondCutHash;
    }

    /// @return The timestamp when the diamond cut was proposed, zero if there are no active proposals
    function getProposedDiamondCutTimestamp() external view returns (uint256) {
        return s.diamondCutStorage.proposedDiamondCutTimestamp;
    }

    /// @return The timestamp when the diamond was frozen last time, zero if the diamond was never frozen
    function getLastDiamondFreezeTimestamp() external view returns (uint256) {
        return s.diamondCutStorage.lastDiamondFreezeTimestamp;
    }

    /// @return The serial number of proposed diamond cuts, increments when proposing a new diamond cut
    function getCurrentProposalId() external view returns (uint256) {
        return s.diamondCutStorage.currentProposalId;
    }

    /// @return The number of received upgrade approvals from the security council
    function getSecurityCouncilEmergencyApprovals()
        external
        view
        returns (uint256)
    {
        return s.diamondCutStorage.securityCouncilEmergencyApprovals;
    }

    /// @return Whether the address is a member of security council
    function isSecurityCouncilMember(
        address _address
    ) external view returns (bool) {
        return s.diamondCutStorage.securityCouncilMembers[_address];
    }

    /// @notice Returns zero for not security council members
    /// @return The index of the last diamond cut that security member approved
    function getSecurityCouncilMemberLastApprovedProposalId(
        address _address
    ) external view returns (uint256) {
        return
            s.diamondCutStorage.securityCouncilMemberLastApprovedProposalId[
                _address
            ];
    }

    /// @return Whether the diamond is frozen or not
    function isDiamondStorageFrozen() external view returns (bool) {
        Diamond.DiamondStorage storage ds = Diamond.getDiamondStorage();
        return ds.isFrozen;
    }

    /// @return isFreezable Whether the facet can be frozen by the governor or always accessible
    function isFacetFreezable(
        address _facet
    ) external view returns (bool isFreezable) {
        Diamond.DiamondStorage storage ds = Diamond.getDiamondStorage();

        // There is no direct way to get whether the facet address is freezable,
        // so we get it from one of the selectors that are associated with the facet.
        uint256 selectorsArrayLen = ds
            .facetToSelectors[_facet]
            .selectors
            .length;
        if (selectorsArrayLen != 0) {
            bytes4 selector0 = ds.facetToSelectors[_facet].selectors[0];
            isFreezable = ds.selectorToFacet[selector0].isFreezable;
        }
    }

    /// @return Whether the selector can be frozen by the governor or always accessible
    function isFunctionFreezable(
        bytes4 _selector
    ) external view returns (bool) {
        Diamond.DiamondStorage storage ds = Diamond.getDiamondStorage();
        require(ds.selectorToFacet[_selector].facetAddress != address(0), "g2");
        return ds.selectorToFacet[_selector].isFreezable;
    }

    /*//////////////////////////////////////////////////////////////
                            DIAMOND LOUPE
     //////////////////////////////////////////////////////////////*/

    /// @return result All facet addresses and their function selectors
    function facets() external view returns (Facet[] memory result) {
        Diamond.DiamondStorage storage ds = Diamond.getDiamondStorage();

        uint256 facetsLen = ds.facets.length;
        result = new Facet[](facetsLen);

        for (uint256 i = 0; i < facetsLen; i = i.uncheckedInc()) {
            address facetAddr = ds.facets[i];
            Diamond.FacetToSelectors memory facetToSelectors = ds
                .facetToSelectors[facetAddr];

            result[i] = Facet(facetAddr, facetToSelectors.selectors);
        }
    }

    /// @return NON-sorted array with function selectors supported by a specific facet
    function facetFunctionSelectors(
        address _facet
    ) external view returns (bytes4[] memory) {
        Diamond.DiamondStorage storage ds = Diamond.getDiamondStorage();
        return ds.facetToSelectors[_facet].selectors;
    }

    /// @return NON-sorted array of facet addresses supported on diamond
    function facetAddresses() external view returns (address[] memory) {
        Diamond.DiamondStorage storage ds = Diamond.getDiamondStorage();
        return ds.facets;
    }

    /// @return Facet address associated with a selector. Zero if the selector is not added to the diamond
    function facetAddress(bytes4 _selector) external view returns (address) {
        Diamond.DiamondStorage storage ds = Diamond.getDiamondStorage();
        return ds.selectorToFacet[_selector].facetAddress;
    }
}
