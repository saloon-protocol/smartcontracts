// SPDX-License-Identifier: MIT OR Apache-2.0

pragma solidity ^0.8.0;

interface IGetters {
    /*//////////////////////////////////////////////////////////////
                            CUSTOM GETTERS
    //////////////////////////////////////////////////////////////*/

    function getOwner() external view returns (address);

    function getPendingOwner() external view returns (address);

    function isDiamondStorageFrozen() external view returns (bool);

    function getProposedDiamondCutHash() external view returns (bytes32);

    function getProposedDiamondCutTimestamp() external view returns (uint256);

    function getLastDiamondFreezeTimestamp() external view returns (uint256);

    function getCurrentProposalId() external view returns (uint256);

    function getSecurityCouncilEmergencyApprovals()
        external
        view
        returns (uint256);

    function isSecurityCouncilMember(
        address _address
    ) external view returns (bool);

    function getSecurityCouncilMemberLastApprovedProposalId(
        address _address
    ) external view returns (uint256);

    /*//////////////////////////////////////////////////////////////
                            DIAMOND LOUPE
    //////////////////////////////////////////////////////////////*/

    /// @notice Faсet structure compatible with the EIP-2535 diamond loupe
    /// @param addr The address of the facet contract
    /// @param selectors The NON-sorted array with selectors associated with facet
    struct Facet {
        address addr;
        bytes4[] selectors;
    }

    function facets() external view returns (Facet[] memory);

    function facetFunctionSelectors(
        address _facet
    ) external view returns (bytes4[] memory);

    function facetAddresses() external view returns (address[] memory facets);

    function facetAddress(
        bytes4 _selector
    ) external view returns (address facet);

    function isFunctionFreezable(bytes4 _selector) external view returns (bool);
}
