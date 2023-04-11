// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../../lib/ERC20.sol";
// import "forge-std/Test.sol";
import "prb-math/UD60x18.sol";
import "../../lib/LibSaloon.sol";
import "../Prepare.t.sol";

contract StakingCurve_Math_Test is Prepare_Test {
    using SafeMath for *;

    function setUp() public virtual override {}

    function testCalculateMultiplier() external {
        // Test for double APY
        uint256 targetDoubleAPY = DEFAULT_APY * 2;
        uint doubleRes = (targetDoubleAPY * PRECISION) / DEFAULT_APY;
        assertEq(doubleRes, 2 ether);

        // Test for half APY
        uint256 targetHalfAPY = DEFAULT_APY / 2;
        uint halfRes = (targetHalfAPY * PRECISION) / DEFAULT_APY;

        assertEq(halfRes, 0.5 ether);
    }

    function testCurveImplementation() external {
        // Test with  $10M poolSize
        // calculate pool X-axis base don USD deposit
        uint256 depositt = 5_000_000 ether;
        uint256 percentageOfPool = (depositt * 1e18) / 10_000_000 ether; // 5M / 10M -> 50%
        assertEq(percentageOfPool, 0.5 ether);

        // calcualte X based on percentage
        uint256 x = (5 * percentageOfPool);
        assertEq(x, 2.5 ether);

        uint256 denominator = ((0.66 ether * x) / 1e18) + 0.1 ether;
        assertEq(denominator, 1.75 ether);
        uint256 y = (1 ether * 1e18) / denominator;
        assertEq(y, 0.571428571428571428 ether);

        // Test with small pool size $1k
        uint256 deposit2 = 500 ether;
        uint256 percentageOfPool2 = (deposit2 * 1e18) / 1000 ether; // 500 / 1k-> 50%
        assertEq(percentageOfPool2, 0.5 ether);
        // calcualte X based on percentage
        uint256 x2 = (5 * percentageOfPool2);
        assertEq(x2, 2.5 ether);
        uint256 denominator2 = ((0.66 ether * (x2)) / 1e18) + 0.1 ether;
        assertEq(denominator2, 1.75 ether);
        uint256 y2 = (1 ether * 1e18) / denominator2;
        assertEq(y2, 0.571428571428571428 ether);
    }

    function testSmallCurveImplementation() external {
        // Test with  smaller X-Values
        // calculate pool X-axis base don USD deposit
        uint256 depositt = 10 ether;
        uint256 percentageOfPool = (depositt * 1e18) / 1000 ether; // 10 / 1,000 -> 0.001%
        assertEq(percentageOfPool, 0.01 ether);

        // calcualte X based on percentage
        uint256 x = (5 * percentageOfPool);
        assertEq(x, 0.05 ether);

        uint256 denominator = ((0.66 ether * (x)) / 1e18) + 0.1 ether;
        assertEq(denominator, 0.133 ether);

        uint256 y = (1 ether * 1e18) / denominator;
        assertEq(y, 7.518796992481203007 ether);

        // Test for zero x
        uint256 x0 = 0.00 ether;

        denominator = ((0.66 ether * (x0)) / 1e18) + 0.1 ether * 1;
        y = (1 ether * 1e18) / denominator;

        assertEq(y, 10 ether);
    }

    function testDefiniteIntegral() external {
        // (50000000000000 * ((ln(33 * (sk)) + 5_000_000) - ln((33 * s) + 5_000_000))) / 33
        //note s (cuurent x-value) and k(stkae amount is x value) are always stored as standard, non-scaled x-values
        // s = current pool size (x-value)
        uint256 s = 2 ether; // 2 ether; ignore

        // k = new staking amount in pool size (x-value)
        uint256 k = 3 ether; // 2.5 ether ignore

        // total pool size
        uint256 sk = s + k;
        uint256 l1 = ((33 * (sk)) + 5 ether);
        uint256 l2 = ((33 * s) + 5 ether);

        // lns
        UD60x18 ln1 = ln(toUD60x18(l1));
        UD60x18 ln2 = ln(toUD60x18(l2));
        UD60x18 res = toUD60x18(50_000_000 ether).mul(ln1.sub(ln2)).div(
            toUD60x18(33)
        );

        // Test area of the curve
        // uint256 result = fromUD60x18(res) / 1e6;
        // uint256 expected = 1.322906909104464154 ether; //3.072951889836796051 ether; // 1168213166645358218181818181818; ignore
        // assertEq(result, expected);

        // area under the curve divided by delta X
        uint256 effAPY = unwrap(res) / (k * 1e6);
        uint256 expectedEffAPY = 0.440968969701488051 ether;
        assertEq(effAPY, expectedEffAPY);

        // Test effective apy scaled by arbitrary multiplier (0.1x)
        uint256 scaledAPY = (effAPY * (0.1 ether)) / PRECISION;
        uint256 expectedScaledAPY = 0.044096896970148805 ether;
        assertEq(scaledAPY, expectedScaledAPY);
    }

    function testConvertStakeToPoolMeasurements() external {
        // calculate pool X-axis base don USD deposit
        uint256 depositt = 10 ether;
        uint256 percentageOfPool = (depositt * 1e18) / 1000 ether; // 10 / 1,000 -> 0.01%
        assertEq(percentageOfPool, 0.01 ether);

        // calcualte X based on percentage
        uint256 x = (5 * percentageOfPool);
        assertEq(x, 0.05 ether);
    }
}
