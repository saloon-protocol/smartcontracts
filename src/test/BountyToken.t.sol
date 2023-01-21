// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../Saloon.sol";
import "../SaloonProxy.sol";
import "../lib/ERC20.sol";
import "ds-test/test.sol";
import "forge-std/Script.sol";
import "../BountyToken.sol";
import "prb-math/UD60x18.sol";

contract BountyTokenTest is BountyToken, DSTest, Script {
    using SafeMath for *;

    BountyToken btt;

    function setUp() external {
        // // string memory bsc = vm.envString("BSC_RPC_URL");
        // string memory mumbai = vm.envString("MUMBAI_RPC_URL");
        // // uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        // uint256 forkId = vm.createFork(mumbai);
        // vm.selectFork(forkId);

        btt = new BountyToken();
        PoolInfo memory pool;
        pool.generalInfo.token = IERC20(address(0xadd));
        pool.generalInfo.tokenDecimals = 18;
        pool.generalInfo.projectWallet = address(0xadddd);
        pool.generalInfo.projectName = "lele";
        pool.generalInfo.projectDeposit = 0;
        pool.generalInfo.apy = 0;
        pool.generalInfo.poolCap = 1000 ether;
        pool.generalInfo.multiplier = 0;
        pool.generalInfo.totalStaked = 0;
        pool.poolTimelock.timelock = 0;
        pool.poolTimelock.timeLimit = 0;
        pool.poolTimelock.withdrawalScheduledAmount = 0;
        pool.poolTimelock.withdrawalExecuted = false;
        pool.stakerList;
        pool.isActive = false;
        pool.freezeTime = 0;
        poolInfo.push(pool);

        PoolInfo memory pool1;
        pool1.generalInfo.token = IERC20(address(0xadd));
        pool1.generalInfo.tokenDecimals = 18;
        pool1.generalInfo.projectWallet = address(0xadddd);
        pool1.generalInfo.projectName = "lele";
        pool1.generalInfo.projectDeposit = 0;
        pool1.generalInfo.apy = 0;
        pool1.generalInfo.poolCap = 1000 ether;
        pool1.generalInfo.multiplier = 0;
        pool1.generalInfo.totalStaked = 0;
        pool1.poolTimelock.timelock = 0;
        pool1.poolTimelock.timeLimit = 0;
        pool1.poolTimelock.withdrawalScheduledAmount = 0;
        pool1.poolTimelock.withdrawalExecuted = false;
        pool1.stakerList;
        pool1.isActive = false;
        pool1.freezeTime = 0;
        poolInfo.push(pool1);
    }

    function testCalculateMultiplier() external {
        // Test for double APY
        uint256 doubleAPY = DEFAULT_APY * 2;
        updateMultiplier(doubleAPY, 0);

        assertEq(poolInfo[0].generalInfo.multiplier, 2 ether);

        // Test for half APY
        uint256 halfAPY = DEFAULT_APY / 2;
        updateMultiplier(halfAPY, 1);

        assertEq(poolInfo[1].generalInfo.multiplier, 0.5 ether);
    }

    function testCurveImplementation() external {
        // Test with  $10M poolSize
        // calculate pool X-axis base don USD deposit
        uint256 deposit = 5_000_000 ether;
        uint256 percentageOfPool = (deposit * 1e18) /
            poolInfo[1].generalInfo.poolCap; // 5M / 10M -> 50%
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
        uint256 percentageOfPool2 = (deposit * 1e18) /
            poolInfo[1].generalInfo.poolCap; // 500 / 1k-> 50%
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
        uint256 percentageOfPool = (deposit * 1e18) /
            poolInfo[1].generalInfo.poolCap; // 10 / 10M -> 0.000001%
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
        uint256 deposit = 0.1 ether;
        uint256 percentageOfPool = (deposit * 1e18) /
            poolInfo[1].generalInfo.poolCap; // 10 / 10M -> 0.000001%
        assertEq(percentageOfPool, 0.00000001 ether);

        // calcualte X based on percentage
        uint256 x = (5 * percentageOfPool);
        assertEq(x, 0.00000005 ether);
    }
}
