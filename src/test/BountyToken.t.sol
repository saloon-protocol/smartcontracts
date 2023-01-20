// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../Saloon.sol";
import "../SaloonProxy.sol";
import "../lib/ERC20.sol";
import "ds-test/test.sol";
import "forge-std/Script.sol";
import "../BountyToken.sol";
import "solmate/utils/SignedWadMath.sol";
import "solmate/utils/FixedPointMathLib.sol";
import "prb-math/UD60x18.sol";
import "../lib/ABDKMath64x64.sol";

contract BountyTokenTest is BountyToken, DSTest, Script {
    using ABDKMath64x64 for int256;
    using FixedPointMathLib for *;
    using SafeMath for *;
    // using SignedWadMath for *;

    BountyToken btt;

    function setUp() external {
        // // string memory bsc = vm.envString("BSC_RPC_URL");
        // string memory mumbai = vm.envString("MUMBAI_RPC_URL");
        // // uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        // uint256 forkId = vm.createFork(mumbai);
        // vm.selectFork(forkId);

        btt = new BountyToken();
        poolSize[0] = 1000 ether;
        poolSize[1] = 10_000_000 ether;
    }

    function testCalculateMultiplier() external {
        // Test for double APY
        uint256 doubleAPY = DEFAULT_APY * 2;
        calculateMultiplier(doubleAPY, 0);

        assertEq(M[0], 2 ether);

        // Test for half APY
        uint256 halfAPY = DEFAULT_APY / 2;
        calculateMultiplier(halfAPY, 1);

        assertEq(M[1], 0.5 ether);
    }

    function testCurveImplementation() external {
        // Test with  $10M poolSize
        // calculate pool X-axis base don USD deposit
        uint256 deposit = 5_000_000 ether;
        uint256 percentageOfPool = (deposit * 1e18) / poolSize[1]; // 5M / 10M -> 50%
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
        uint256 percentageOfPool2 = (deposit * 1e18) / poolSize[1]; // 500 / 1k-> 50%
        assertEq(percentageOfPool2, 0.5 ether);
        // calcualte X based on percentage
        uint256 x2 = (5 * percentageOfPool2);
        assertEq(x2, 2.5 ether);
        uint256 denominator2 = ((0.66 ether * (x2)) / 1e18) + 0.1 ether;
        assertEq(denominator2, 1.75 ether);
        uint256 y2 = (1 ether * 1e18) / denominator2;
        assertEq(y2, 0.571428571428571428 ether);
    }

    function testCurveImplementationSmall() external {
        // Test with  smaller X-Values
        // calculate pool X-axis base don USD deposit
        uint256 deposit = 10 ether;
        uint256 percentageOfPool = (deposit * 1e18) / poolSize[1]; // 10 / 10M -> 0.000001%
        assertEq(percentageOfPool, 0.000001 ether);

        // calcualte X based on percentage
        uint256 x = (5 * percentageOfPool);
        assertEq(x, 0.000005 ether);

        uint256 denominator = ((0.66 ether * (x)) / 1e18) + 0.1 ether;
        assertEq(denominator, 0.1000033 ether);
        uint256 y = (1 ether * 1e18) / denominator;
        assertEq(y, 9.999670010889640641 ether);
    }

    function testDefiniteIntegral() external {
        // (50000000000000 * ((ln(33 * (sk)) + 5_000_000) - ln((33 * s) + 5_000_000))) / 33

        // s = current pool size (x-value)
        uint256 s = 0 ether; // 2 ether; ignore

        // k = new staking amount in pool size (x-value)
        uint256 k = 1 ether; // 2.5 ether ignore

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

        uint256 result = unwrap(res);
        uint256 expected = 3072951889836796053030303030303; // 1168213166645358218181818181818; ignore
        assertEq(result, expected);
    }
}
