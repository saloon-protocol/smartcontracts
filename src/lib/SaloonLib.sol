// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;
import "../interfaces/ISaloon.sol";
import "../StrategyFactory.sol";
import "prb-math/UD60x18.sol";

/*
- calculateEffectiveAPY : Use this for both functions in BountyNFT
- curveImplementation
- all view functions in Saloon and BountyTokenNFT
*/
library SaloonLib {
    //Constants
    uint256 constant DEFAULT_APY = 1.06 ether;
    uint256 constant BPS = 10_000;
    uint256 constant PRECISION = 1e18;

    uint256 constant YEAR = 365 days;
    uint256 constant PERIOD = 1 weeks;
    uint256 constant saloonFee = 1000;

    ////////////////////////////////////////////////////////////////////////////////
    //                           BountyTokenNFT                                  //
    //////////////////////////////////////////////////////////////////////////////

    /// @notice Calculates scalingMultiplier given targetAPY
    /// @param _targetAPY the advertised average APY of a bounty
    function _updateScalingMultiplier(uint256 _targetAPY)
        public
        view
        returns (uint256 scalingMultiplier)
    {
        scalingMultiplier = (_targetAPY * PRECISION) / DEFAULT_APY;
    }

    ///@notice Default curve function implementation
    /// @dev calculates Y given X
    ///     -    1/(0.66x+0.1)
    ///     - Y = APY
    ///     - X = total token amount in pool scaled to X variable
    /// @param _x X value
    function _curveImplementation(uint256 _x) public pure returns (uint256 y) {
        uint256 denominator = ((0.66 ether * _x) / 1e18) + 0.1 ether;
        y = (1 ether * 1e18) / denominator;
    }

    /// @notice Convert token amount to X value equivalent
    /// @dev max X value is 5
    /// @param _stake Amount to be converted
    function _convertStakeToPoolMeasurements(uint256 _stake, uint256 _poolCap)
        public
        view
        returns (uint256 x, uint256 poolPercentage)
    {
        poolPercentage = (_stake * PRECISION) / _poolCap;

        x = 5 * poolPercentage;
    }

    function getCurrentAPY(uint256 _x, uint256 _multiplier)
        public
        view
        returns (uint256 currentAPY)
    {
        // current unit APY =  y-value * scalingMultiplier
        currentAPY = _curveImplementation(_x) * _multiplier;
    }

    /// @notice Calculates effective APY staker will be entitled to in exchange for amount staked
    /// @dev formula for calculating effective price:
    ///      (50000000000000 * ((ln(33 * (sk)) + 5_000_000) - ln((33 * s) + 5_000_000))) / 33
    /// @param _stake amount to be staked
    /// @param _memX Arbitrary X value
    function calculateArbitraryEffectiveAPY(
        uint256 _stake,
        uint256 _memX,
        uint256 _poolCap,
        uint256 _multiplier
    ) public view returns (uint256 scaledAPY) {
        // get current x
        uint256 s = _memX;
        // convert stake to x-value
        (uint256 k, ) = _convertStakeToPoolMeasurements(_stake, _poolCap);
        uint256 sk = k + s;

        uint256 l1 = ((33 * (sk)) + 5 ether);
        uint256 l2 = ((33 * s) + 5 ether);

        // lns
        UD60x18 ln1 = ln(toUD60x18(l1));
        UD60x18 ln2 = ln(toUD60x18(l2));
        UD60x18 res = toUD60x18(50_000_000 ether).mul(ln1.sub(ln2)).div(
            toUD60x18(33)
        );
        // calculate effective APY
        uint256 effectiveAPY = unwrap(res) / (k * 1e6);

        // calculate effective APY according to APY offered
        scaledAPY = (effectiveAPY * _multiplier) / PRECISION;
    }

    //===========================================================================||
    //                               SALOON                                      ||
    //===========================================================================||

    // NOTE: for some reason using this increases bytcode size
    // function calcRequiredPremiumBalancePerPeriod(uint256 _poolCap, uint256 _apy)
    //     public
    //     pure
    //     returns (uint256 requiredPremiumBalance)
    // {
    //     requiredPremiumBalance = (((_poolCap * _apy * PERIOD) / BPS) / YEAR);
    // }

    function calcReferralSplit(
        uint256 _totalAmount,
        uint256 _endTime,
        uint256 _referralFee,
        address _referrer
    )
        public
        view
        returns (
            uint256,
            uint256,
            address
        )
    {
        if (_referrer == address(0) || _endTime < block.timestamp) {
            return (_totalAmount, 0, _referrer);
        } else {
            uint256 referralAmount = (_totalAmount * _referralFee) / BPS;
            uint256 saloonAmount = _totalAmount - referralAmount;
            return (saloonAmount, referralAmount, _referrer);
        }
    }

    // NOTE this also makes it more expensive for some reason
    function pendingPremium(
        uint256 _freezeTime,
        uint256 _lastClaimedTime,
        uint256 _amount,
        uint256 _apy,
        uint256 _unclaimed
    )
        public
        view
        returns (
            uint256 totalPending,
            uint256 actualPending,
            uint256 newPending
        )
    {
        uint256 endTime = _freezeTime != 0 ? _freezeTime : block.timestamp;

        // secondsPassed = number of seconds between lastClaimedTime and endTime
        uint256 secondsPassed = endTime - _lastClaimedTime;
        newPending = ((_amount * _apy * secondsPassed) / BPS) / YEAR; //L5 FIXME multiplication before division fixed
        totalPending = newPending + _unclaimed;
        actualPending = (totalPending * (BPS - saloonFee)) / BPS;

        return (totalPending, actualPending, newPending);
    }

    // NOTE this also makes it more expensive for some reason
    // function viewBountyBalance(
    //     uint256 _totalStaked,
    //     uint256 _projectDepositHeld,
    //     uint256 _projectDepositInStrategy
    // ) public view returns (uint256) {
    //     return (_totalStaked + _projectDepositHeld + _projectDepositInStrategy);
    // }
}
