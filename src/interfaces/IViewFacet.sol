pragma solidity ^0.8.10;
import "../Storage.sol";

interface IViewFacet {
    function viewBountyInfo(
        uint256 _pid
    )
        external
        view
        returns (uint256 payout, uint256 apy, uint256 staked, uint256 poolCap);

    function viewMinProjectDeposit(
        uint256 _pid
    ) external view returns (uint256);

    function getAllTokensByOwner(
        address _owner
    ) external view returns (NFTInfo[] memory userTokens);

    function viewPoolAPY(uint256 _pid) external view returns (uint256);

    function viewPoolCap(uint256 _pid) external view returns (uint256);

    function viewPoolPremiumInfo(
        uint256 _pid
    )
        external
        view
        returns (
            uint256 requiredPremiumBalancePerPeriod,
            uint256 premiumBalance,
            uint256 premiumAvailable
        );

    function viewPoolTimelockInfo(
        uint256 _pid
    )
        external
        view
        returns (
            uint256 timelock,
            uint256 timeLimit,
            uint256 withdrawalScheduledAmount
        );

    function viewPendingPremium(
        uint256 _tokenId
    )
        external
        returns (
            uint256 totalPending,
            uint256 actualPending,
            uint256 newPending
        );

    function viewReferralBalance(
        address _referrer,
        address _token
    ) external view returns (uint256 referralBalance);

    function viewSaloonProfitBalance(
        address _token
    )
        external
        view
        returns (
            uint256 totalProfit,
            uint256 bountyProfit,
            uint256 strategyProfit,
            uint256 premiumProfit
        );

    function viewTokenInfo(
        uint256 _tokenId
    )
        external
        view
        returns (
            uint256 amount,
            uint256 apy,
            uint256 actualPending,
            uint256 unclaimed,
            uint256 timelock
        );

    function viewTotalStaked(uint256 _pid) external view returns (uint256);
}
