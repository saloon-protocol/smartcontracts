// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

interface IBountyTokenNFT {
    // Info of each token.
    struct NFTInfo {
        uint256 pid;
        uint256 amount;
        uint256 xDelta;
        uint256 apy;
        uint256 unclaimed;
        uint256 lastClaimedTime;
        uint256 timelock;
        uint256 timelimit;
    }

    function pidNFTList(uint256 _pid) external returns (uint256[] memory);

    function nftInfo(uint256 _tokenId) external view returns (NFTInfo memory);

    function updateToken(uint256 _tokenId, NFTInfo memory _tokenData) external;

    function mint(
        uint256 _pid,
        address _staker,
        uint256 _stake
    ) external returns (uint256);

    function burn(uint256 _tokenId) external;

    function ownerOf(uint256 tokenId) external view returns (address);

    function isApprovedOrOwner(address sender, uint256 tokenId)
        external
        view
        returns (bool);

    function pendingPremium(uint256 _tokenId)
        external
        view
        returns (
            uint256,
            uint256,
            uint256
        );

    function calculateScalingMultiplier(uint256 _targetAPY)
        external
        view
        returns (uint256);

    function curveImplementation(uint256 _x) external view returns (uint256);
}
