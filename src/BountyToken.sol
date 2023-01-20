// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import "prb-math/UD60x18.sol";
import "./ISaloon.sol";

// TODO Update table below with new values
/* 
OBS: Max APY to average APY ratio can still be tweaked so for now
I just put a ballpark 

BountyToken ERC20

================================================
    ** Default Variables **
================================================
Default Curve: 1/(0.66x+0.1) 
--------------------------------
defaultAPY "average" = 1.06
--------------------------------
standardMaxAPY = 10
--------------------------------
max-to-standard APY ratio:
ratio = ~4.56 = maxAPY/defaultAPY 
e.g 33/7.226490363249782 = 4.566532070370017
--------------------------------
Definite Integral:
================================================
    ** Scaled variables **
================================================
Scaled Curve (Not Used): M(32 * (0.6**((1/M)x)) + 1)
-----------------------------
targetAPY = defaultAPY * M
e.g targetAPY = 20 (%)
M = 20/7.2 = 2.767 (%)
-----------------------------
maxAPY = targetAPY * ratio
-----------------------------
current APY
-----------------------------
Scaled Definite Integral:
(definite integral result) * M^(2)
-----------------------------


Notes:
Standard Curve is used to calculate the staking reward.
Such reward is then multiplied by M to match the targetAPY offered by the project,
which my differ from the standard 7.2
----------------------------------------------
================================================
================================================
*/

contract BountyToken is ISaloon, ERC20Upgradeable {
    //Constants
    uint256 constant DEFAULT_APY = 1.06 ether;
    uint256 constant BPS = 10_000;
    uint256 constant PRECISION = 1e18;

    // Info of each pool.
    PoolInfo[] public poolInfo;

    constructor() initializer {
        __ERC20_init("BountyToken", "BTT");
    }

    // Functions:

    // * function that calculates M given targetAPY
    //  maybe make it internal
    /// @param _targetAPY the advertised average APY of a bounty
    /// @param _poolID poolID that the multiplier will be assigned to
    function updateMultiplier(uint256 _targetAPY, uint256 _poolID) internal {
        uint256 m = (_targetAPY * PRECISION) / DEFAULT_APY;
        poolInfo[_poolID].generalInfo.multiplier = m;
    }

    // * Standard curve function implementation
    //      1/(0.66x+0.1)
    // Max Pool Size 10M
    function curveImplementation(uint256 _x) internal pure returns (uint256 y) {
        uint256 denominator = ((0.66 ether * _x) / 1e18) + 0.1 ether;
        uint256 y = (1 ether * 1e18) / denominator;
    }

    //  Get Current APY of pool (y-value)
    function getCurrentAPY() public returns (uint256 result) {
        // get current x-value
        uint256 x;
        result = curveImplementation(x);
    }

    function convertStakeToPoolMeasurements(uint256 _stake, uint256 _poolID)
        public
        returns (uint256 x, uint256 poolPercentage)
    {
        poolPercentage =
            (_stake * PRECISION) /
            poolInfo[_poolID].generalInfo.poolCap;
        x = 5 * poolPercentage;
    }

    function seeEffectiveStakingAPY(uint256 _stake, uint256 _poolID)
        public
        view
    {
        // - check how much APY you would get reward for investing Z amount of USD
    }

    /// @dev formula for calculating effective price:
    /// (50000000000000 * ((ln(33 * (sk)) + 5_000_000) - ln((33 * s) + 5_000_000))) / 33
    function calculateEffectivePrice(uint256 _stake, uint256 _poolID)
        public
        returns (uint256 toBeMinted)
    {
        // get current x
        uint256 s = poolInfo[_poolID].tokenInfo.currentX;
        uint256 sk = _stake + _poolID;

        uint256 l1 = ((33 * (sk)) + 5 ether);
        uint256 l2 = ((33 * s) + 5 ether);

        // lns
        UD60x18 ln1 = ln(toUD60x18(l1));
        UD60x18 ln2 = ln(toUD60x18(l2));
        UD60x18 res = toUD60x18(50_000_000 ether).mul(ln1.sub(ln2)).div(
            toUD60x18(33)
        );

        toBeMinted = unwrap(res) / 1e24;
    }
    // * Calculate effective price
    //     - (definite integral result) / precision)
    // /

    // * Calculate APY for staking
    //     - stake amount in % = USD/poolsize
    //     - calculate % in x-value equivalent = xStakeAmount
    //     - get current x + xStakeAmount
    //     - get scaled definite integral
    //     - update new x = current x + xStakeAmount
    //     - update new y = standardCurve(newX)
    // /

    // * Register when a token is transferred between accounts so seller
    //   gets the rewards he is entitled to even after sale.
    // /

    // * Get current APY value (y value)
    // /
    // * Get current pool size (x value)
    // /

    // * mint function override - make sure to include pool ID when minting

    // * balanceOf function override - make sure to check for pool ID
}
