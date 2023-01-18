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
        // 3(ln(20(s+k)+3) - ln(20s + 3))  / 2
        // ln(20(s+k)+3)
        // current x = s
        uint256 s = 2.5 ether;
        // k = new staked amount
        uint256 k = 2 ether;
        uint256 l1 = 20 ether * (s + k) + 3 ether;
        UD60x18 ll1 = toUD60x18(l1);
        uint256 lll1 = fromUD60x18(ln(ll1));

        // ln(20s + 3)
        uint256 l2 = 20 ether * s + 3 ether;
        UD60x18 ll2 = toUD60x18(l2);
        uint256 lll2 = fromUD60x18(ln(ll2));
        uint256 lll3 = (lll1 - lll2) * 1e18;
        // ln(20(s+k)+3) - ln(20s + 3)
        // UD60x18 Ln = ln(ll1)(ln(ll2));
        uint256 result = (3 ether * lll3) / 2 ether;
        assertEq(result, 1.5 ether);

        // // current x = s
        // uint256 sb = 2500;
        // // k = new staked amount
        // uint256 kb = 2000;
        // uint256 l1b = 20_000 * (sb + kb) + 3000;
        // UD60x18 ll1b = toUD60x18(l1b);
        // uint256 lll1b = fromUD60x18(ln(ll1b));

        // // ln(20s + 3)
        // uint256 l2b = 20_000 * s + 3000;
        // UD60x18 ll2b = toUD60x18(l2b);
        // uint256 lll2b = fromUD60x18(ln(ll2) * 1e18);

        // // ln(20(s+k)+3) - ln(20s + 3)
        // // UD60x18 Ln = ln(ll1)(ln(ll2));
        // uint256 resultb = ((3000 * (lll1b - lll2b)) * 1000) / 2000;
        // assertEq(resultb, 1.5 ether);

        // // uint256 integral = (3 ether * result) / 2 ether;
        // // assertEq(integral, 1);
    }

    // //
    //     UD60x18 ud = toUD60x18(200_000 * 50_000 + 30_000);
    //     UD60x18 udd = toUD60x18(200_000 * 45_000 + 30_000);
    //     int128 ud2 = 200_000 * 50_000 + 30_000;
    //     // int128 z2 = ln(ud2);
    //     UD60x18 ln = ln(udd).add(ln(ud));
    //     // UD60x18 lala = ln(ud);
    //     // UD60x18 lj = ln(ud);
    //     // UD60x18 ll = (30_000 * (ln - ln2)) / 20_000;
    //     uint256 z6 = fromUD60x18(ln);
    //     // assertEq(z6, 1);
}
