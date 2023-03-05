// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.7.0) (proxy/ERC1967/ERC1967Proxy.sol)

pragma solidity ^0.8.17;
import "./SaloonStorage.sol";

contract SaloonView is SaloonStorage {
    //===========================================================================||
    //                             VIEW FUNCTIONS                                ||
    //===========================================================================||

    function pendingPremium(uint256 _tokenId)
        public
        view
        returns (
            uint256 totalPending,
            uint256 actualPending,
            uint256 newPending
        )
    {
        NFTInfo memory token = nftInfo[_tokenId];
        uint256 pid = token.pid;
        PoolInfo memory pool = poolInfo[pid];

        (
            uint256 totalPending,
            uint256 actualPending,
            uint256 newPending
        ) = SaloonLib.pendingPremium(
                pool.freezeTime,
                token.lastClaimedTime,
                token.amount,
                token.apy,
                token.unclaimed
            );
    }

    function viewSaloonProfitBalance(address _token)
        public
        view
        returns (
            uint256 totalProfit,
            uint256 bountyProfit,
            uint256 strategyProfit,
            uint256 premiumProfit
        )
    {
        bountyProfit = saloonBountyProfit[_token];
        strategyProfit = saloonStrategyProfit[_token];
        premiumProfit = saloonPremiumProfit[_token];
        totalProfit = premiumProfit + bountyProfit + strategyProfit;
    }

    function viewReferralBalance(address _referrer, address _token)
        public
        view
        returns (uint256 referralBalance)
    {
        referralBalance = referralBalances[_referrer][_token];
    }

    function viewBountyBalance(uint256 _pid) public view returns (uint256) {
        PoolInfo memory pool = poolInfo[_pid];
        return (pool.generalInfo.totalStaked +
            (pool.depositInfo.projectDepositHeld +
                pool.depositInfo.projectDepositInStrategy));
    }

    function viewMinProjectDeposit(uint256 _pid) public view returns (uint256) {
        PoolInfo memory pool = poolInfo[_pid];
        return (pool.depositInfo.projectDepositHeld +
            pool.depositInfo.projectDepositInStrategy);
    }

    function viewTotalStaked(uint256 _pid) public view returns (uint256) {
        PoolInfo memory pool = poolInfo[_pid];
        return pool.generalInfo.totalStaked;
    }

    function viewPoolCap(uint256 _pid) public view returns (uint256) {
        PoolInfo memory pool = poolInfo[_pid];
        return pool.generalInfo.poolCap;
    }

    function viewPoolAPY(uint256 _pid) public view returns (uint256) {
        PoolInfo memory pool = poolInfo[_pid];
        return pool.generalInfo.apy;
    }

    function viewTokenInfo(uint256 _tokenId)
        public
        view
        returns (
            uint256 amount,
            uint256 apy,
            uint256 actualPending,
            uint256 unclaimed,
            uint256 timelock
        )
    {
        NFTInfo memory token = nftInfo[_tokenId];
        amount = token.amount;
        apy = token.apy;
        (, actualPending, ) = pendingPremium(_tokenId);
        unclaimed = token.unclaimed;
        timelock = token.timelock;
    }

    function viewPoolPremiumInfo(uint256 _pid)
        public
        view
        returns (
            uint256 requiredPremiumBalancePerPeriod,
            uint256 premiumBalance,
            uint256 premiumAvailable
        )
    {
        PoolInfo memory pool = poolInfo[_pid];

        requiredPremiumBalancePerPeriod = calcRequiredPremiumBalancePerPeriod(
            pool.generalInfo.poolCap,
            pool.generalInfo.apy
        );
        premiumBalance = pool.premiumInfo.premiumBalance;
        premiumAvailable = pool.premiumInfo.premiumAvailable;
    }

    function calcRequiredPremiumBalancePerPeriod(uint256 _poolCap, uint256 _apy)
        internal
        pure
        returns (uint256 requiredPremiumBalance)
    {
        requiredPremiumBalance = (((_poolCap * _apy * PERIOD) / BPS) / YEAR);
    }

    function viewPoolTimelockInfo(uint256 _pid)
        public
        view
        returns (
            uint256 timelock,
            uint256 timeLimit,
            uint256 withdrawalScheduledAmount
        )
    {
        PoolInfo memory pool = poolInfo[_pid];
        timelock = pool.poolTimelock.timelock;
        timeLimit = pool.poolTimelock.timeLimit;
        withdrawalScheduledAmount = pool.poolTimelock.withdrawalScheduledAmount;
    }

    function viewHackerPayout(uint256 _pid) public view returns (uint256) {
        return (viewBountyBalance(_pid) * (BPS - saloonFee)) / BPS;
    }

    function viewBountyInfo(uint256 _pid)
        public
        view
        returns (
            uint256 payout,
            uint256 apy,
            uint256 staked,
            uint256 poolCap
        )
    {
        payout = viewHackerPayout(_pid);
        staked = viewTotalStaked(_pid);
        apy = viewPoolAPY(_pid);
        poolCap = viewPoolCap(_pid);
    }

    function receiveStrategyYield(address _token, uint256 _amount)
        public
        virtual
    {}

    function viewTokenWhitelistStatus(address _token)
        public
        view
        returns (bool)
    {
        return tokenWhitelist[_token];
    }
}
