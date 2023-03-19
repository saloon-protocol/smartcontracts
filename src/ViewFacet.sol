pragma solidity ^0.8.17;
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "./Base.sol";
import "./interfaces/IViewFacet.sol";
import "./interfaces/IStrategyFactory.sol";
import "./lib/LibSaloon.sol";
import "./lib/LibERC721.sol";

contract ViewFacet is Base, IViewFacet {
    using SafeERC20 for IERC20;

    // viewPoolPremiumInfo
    function viewPoolPremiumInfo(
        uint256 _pid
    )
        external
        view
        returns (
            uint256 requiredPremiumBalancePerPeriod,
            uint256 premiumBalance,
            uint256 premiumAvailable
        )
    {
        PoolInfo memory pool = s.poolInfo[_pid];

        requiredPremiumBalancePerPeriod = LibSaloon
            .calcRequiredPremiumBalancePerPeriod(
                pool.generalInfo.poolCap,
                pool.generalInfo.apy
            );
        premiumBalance = pool.premiumInfo.premiumBalance;
        premiumAvailable = pool.premiumInfo.premiumAvailable;
    }

    // viewTokenInfo
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
        )
    {
        NFTInfo memory token = s.nftInfo[_tokenId];
        uint pid = token.pid;
        PoolInfo memory pool = s.poolInfo[pid];

        amount = token.amount;
        apy = token.apy;
        (, actualPending, ) = LibSaloon.pendingPremium(
            pool.freezeTime,
            token.lastClaimedTime,
            token.amount,
            token.apy,
            token.unclaimed
        );
        unclaimed = token.unclaimed;
        timelock = token.timelock;
    }

    function viewPendingPremium(
        uint _tokenId
    )
        external
        returns (
            uint256 totalPending,
            uint256 actualPending,
            uint256 newPending
        )
    {
        NFTInfo memory token = s.nftInfo[_tokenId];
        uint pid = token.pid;
        PoolInfo memory pool = s.poolInfo[pid];
        (totalPending, actualPending, newPending) = LibSaloon.pendingPremium(
            pool.freezeTime,
            token.lastClaimedTime,
            token.amount,
            token.apy,
            token.unclaimed
        );
    }

    // viewSaloonProfitBalance
    function viewSaloonProfitBalance(
        address _token
    )
        public
        view
        returns (
            uint256 totalProfit,
            uint256 bountyProfit,
            uint256 strategyProfit,
            uint256 premiumProfit
        )
    {
        bountyProfit = s.saloonBountyProfit[_token];
        strategyProfit = s.saloonStrategyProfit[_token];
        premiumProfit = s.saloonPremiumProfit[_token];
        totalProfit = premiumProfit + bountyProfit + strategyProfit;
    }

    // viewReferralBalance
    function viewReferralBalance(
        address _referrer,
        address _token
    ) public view returns (uint256 referralBalance) {
        referralBalance = s.referralBalances[_referrer][_token];
    }

    function viewMinProjectDeposit(uint256 _pid) public view returns (uint256) {
        PoolInfo memory pool = s.poolInfo[_pid];
        return (pool.depositInfo.projectDepositHeld +
            pool.depositInfo.projectDepositInStrategy);
    }

    function viewTotalStaked(uint256 _pid) public view returns (uint256) {
        PoolInfo memory pool = s.poolInfo[_pid];
        return pool.generalInfo.totalStaked;
    }

    function viewPoolCap(uint256 _pid) public view returns (uint256) {
        PoolInfo memory pool = s.poolInfo[_pid];
        return pool.generalInfo.poolCap;
    }

    function viewPoolAPY(uint256 _pid) public view returns (uint256) {
        PoolInfo memory pool = s.poolInfo[_pid];
        return pool.generalInfo.apy;
    }

    function viewPoolTimelockInfo(
        uint256 _pid
    )
        external
        view
        returns (
            uint256 timelock,
            uint256 timeLimit,
            uint256 withdrawalScheduledAmount
        )
    {
        PoolInfo memory pool = s.poolInfo[_pid];
        timelock = pool.poolTimelock.timelock;
        timeLimit = pool.poolTimelock.timeLimit;
        withdrawalScheduledAmount = pool.poolTimelock.withdrawalScheduledAmount;
    }

    // TODO This doesnt include scheduled unstakes and withdrawals
    // function viewHackerPayout(uint256 _pid) public view returns (uint256) {
    //     return (viewBountyBalance(_pid) * (BPS - saloonFee)) / BPS;
    // }

    function viewBountyInfo(
        uint256 _pid
    )
        external
        view
        returns (uint256 payout, uint256 apy, uint256 staked, uint256 poolCap)
    {
        // payout = viewHackerPayout(_pid);
        staked = viewTotalStaked(_pid);
        apy = viewPoolAPY(_pid);
        poolCap = viewPoolCap(_pid);
    }

    function getAllTokensByOwner(
        address _owner
    ) public view returns (NFTInfo[] memory userTokens) {
        LibERC721.TokenStorage storage ts = LibERC721.getTokenStorage();

        uint256[] memory tokens = ts._ownedTokens[_owner];
        uint256 tokenLength = tokens.length;
        userTokens = new NFTInfo[](tokenLength);

        for (uint256 i = 0; i < tokenLength; ++i) {
            userTokens[i] = s.nftInfo[tokens[i]];
        }
    }
}
