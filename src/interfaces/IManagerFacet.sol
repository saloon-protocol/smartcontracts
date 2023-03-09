pragma solidity ^0.8.10;

interface IManagerFacet {
    function addNewBountyPool(
        address _token,
        address _projectWallet,
        string memory _projectName,
        address _referrer,
        uint256 _referralFee,
        uint256 _referralEndTime
    ) external returns (uint256);

    function viewBountyBalance(uint256 _pid) external view returns (uint256);
}
