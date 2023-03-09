// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;
import "../interfaces/ISaloon.sol";
import "../StrategyFactory.sol";
import "prb-math/UD60x18.sol";

import "openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/*
- calculateEffectiveAPY : Use this for both functions in BountyNFT
- curveImplementation
- all view functions in Saloon and BountyTokenNFT
*/
library LibSaloon {
    struct LibSaloonStorage {
        //TODO IMPLEMENT FUNCTIONS TO SET THIS TO DIFFERENT VALUES
        uint256 defaultAPY; // 1.06
        uint256 bps; // 10_000
        uint256 precision; // 1e18
        uint256 year; // 365 days NOTE should this be made a constant?
        uint256 period; // 1 weeks
        uint256 saloonFee; // 1000
    }
    //     uint256  defaultAPY = 1.06 ether;
    // uint256  bps = 10_000;
    // uint256  precision = 1e18;
    // uint256  year = 365 days;
    // uint256  period = 1 weeks;
    // uint256  saloonFee = 1000;

    bytes32 constant LIB_STORAGE_POSITION =
        0xb3489dd2b6aceffcd73eb3bc338c0fb7cf41e877855ec204580612eca103a15d; // keccak256("lib.saloon.storage") - 1;

    /// @return saloonStorage The pointer to the storage where specific Saloon parameters stored
    function getLibSaloonStorage()
        internal
        pure
        returns (LibSaloonStorage storage saloonStorage)
    {
        bytes32 position = LIB_STORAGE_POSITION;
        assembly {
            saloonStorage.slot := position
        }
    }

    ////////////////////////////////////////////////////////////////////////////////
    //                           BountyTokenNFT                                  //
    //////////////////////////////////////////////////////////////////////////////

    /// @notice Calculates scalingMultiplier given targetAPY
    /// @param _targetAPY the advertised average APY of a bounty
    function _updateScalingMultiplier(
        uint256 _targetAPY
    ) public view returns (uint256 scalingMultiplier) {
        LibSaloonStorage storage ss = getLibSaloonStorage();

        scalingMultiplier = (_targetAPY * ss.precision) / ss.defaultAPY;
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
    function _convertStakeToPoolMeasurements(
        uint256 _stake,
        uint256 _poolCap
    ) public view returns (uint256 x, uint256 poolPercentage) {
        LibSaloonStorage storage ss = getLibSaloonStorage();

        poolPercentage = (_stake * ss.precision) / _poolCap;

        x = 5 * poolPercentage;
    }

    function getCurrentAPY(
        uint256 _x,
        uint256 _multiplier
    ) public view returns (uint256 currentAPY) {
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
        LibSaloonStorage storage ss = getLibSaloonStorage();

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
        scaledAPY = (effectiveAPY * _multiplier) / ss.precision;
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
    ) public view returns (uint256, uint256, address) {
        LibSaloonStorage storage ss = getLibSaloonStorage();

        if (_referrer == address(0) || _endTime < block.timestamp) {
            return (_totalAmount, 0, _referrer);
        } else {
            uint256 referralAmount = (_totalAmount * _referralFee) / ss.bps;
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
        LibSaloonStorage storage ss = getLibSaloonStorage();

        uint256 endTime = _freezeTime != 0 ? _freezeTime : block.timestamp;

        // secondsPassed = number of seconds between lastClaimedTime and endTime
        uint256 secondsPassed = endTime - _lastClaimedTime;
        newPending = ((_amount * _apy * secondsPassed) / ss.bps) / ss.year; //L5 FIXME multiplication before division fixed
        totalPending = newPending + _unclaimed;
        actualPending = (totalPending * (ss.bps - ss.saloonFee)) / ss.bps;

        return (totalPending, actualPending, newPending);
    }

    function calcRequiredPremiumBalancePerPeriod(
        uint256 _poolCap,
        uint256 _apy
    ) public view returns (uint256 requiredPremiumBalance) {
        LibSaloonStorage storage ss = getLibSaloonStorage();

        requiredPremiumBalance = (((_poolCap * _apy * ss.period) / ss.bps) /
            ss.year);
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
