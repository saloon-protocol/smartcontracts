// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

interface ISaloon {
    // Info of each pool.
    struct PoolInfo {
        GeneralInfo generalInfo;
        DepositInfo depositInfo;
        PremiumInfo premiumInfo;
        TimelockInfo poolTimelock;
        TokenInfo tokenInfo;
        address[] stakerList;
        uint256 freezeTime;
        bool isActive;
    }

    struct GeneralInfo {
        IERC20 token; // Address of LP token contract.
        uint8 tokenDecimals;
        uint16 apy;
        address projectWallet;
        string projectName;
        uint256 poolCap;
        uint256 totalStaked;
        uint256 multiplier;
    }

    struct DepositInfo {
        uint256 projectDepositHeld;
        uint256 projectDepositInStrategy;
    }

    struct PremiumInfo {
        uint256 premiumBalance;
        uint256 premiumAvailable;
    }

    struct TimelockInfo {
        uint256 timelock;
        uint256 timeLimit;
        uint256 withdrawalScheduledAmount;
        bool withdrawalExecuted;
    }

    // Change this to "CurveInfo"
    struct TokenInfo {
        // amount staked in curve X-value
        uint256 currentX;
        // current APY
        uint256 currentY;
        // token totalSupply for each pool
        uint256 totalSupply;
        uint256[] unstakedTokens;
        // user balance
        // mapping(address => uint256) balances;
    }
}
