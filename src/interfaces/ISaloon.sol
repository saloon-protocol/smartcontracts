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
        CurveInfo curveInfo;
        ReferralInfo referralInfo;
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
        uint256 scalingMultiplier;
    }

    struct NFTInfo {
        uint256 pid;
        uint256 amount;
        uint256 xDelta;
        uint256 apy;
        uint256 unclaimed;
        uint256 lastClaimedTime;
        uint256 timelock;
        uint256 timelimit;
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

    // TODO Change this from TokenInfo to "CurveInfo"
    struct CurveInfo {
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

    struct ReferralInfo {
        address referrer;
        uint256 referralFee; // in BPS (10000)
        uint256 endTime;
    }

    event NewBountyDeployed(
        uint256 indexed pid,
        address indexed token,
        uint256 tokenDecimals
    );

    event Staked(address indexed user, uint256 indexed pid, uint256 amount);
    event Unstaked(address indexed user, uint256 indexed pid, uint256 amount);

    event BountyBalanceChanged(
        uint256 indexed pid,
        uint256 oldAmount,
        uint256 newAmount
    );

    event PremiumBilled(uint256 indexed pid, uint256 amount);

    event BountyPaid(
        address indexed hunter,
        address indexed token,
        uint256 amount
    );

    event WithdrawalOrUnstakeScheduled(uint256 indexed pid, uint256 amount);

    event tokenWhitelistUpdated(
        address indexed token,
        bool indexed whitelisted
    );

    event referralPaid(address indexed referrer, uint256 amount);

    function receiveStrategyYield(address _token, uint256 _amount) external;
}
