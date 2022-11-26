// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

interface ISaloon {
    // Info of each pool.
    struct PoolInfo {
        IERC20 token; // Address of LP token contract.
        bool withdrawalExecuted;
        bool initialized;
        uint8 tokenDecimals;
        uint16 apy;
        address projectWallet;
        uint256 projectDeposit;
        uint256 poolCap;
        uint256 totalStaked;
        uint256 totalPending;
        uint256 requiredPremiumBalancePerPeriod;
        uint256 premiumBalance;
        TimelockInfo poolTimelock;
        address[] stakerList;
    }

    struct TimelockInfo {
        uint256 timelock;
        uint256 timeLimit;
        uint256 withdrawalScheduledAmount;
        bool withdrawalExecuted;
    }
}
