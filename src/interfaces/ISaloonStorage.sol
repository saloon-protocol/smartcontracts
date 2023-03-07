pragma solidity ^0.8.10;
import "./ISaloon.sol";

interface Interface {
    event BountyBalanceChanged(
        uint256 indexed pid,
        uint256 oldAmount,
        uint256 newAmount
    );
    event BountyPaid(
        address indexed hunter,
        address indexed token,
        uint256 amount
    );
    event NewBountyDeployed(
        uint256 indexed pid,
        address indexed token,
        uint256 tokenDecimals
    );
    event PremiumBilled(uint256 indexed pid, uint256 amount);
    event Staked(address indexed user, uint256 indexed pid, uint256 amount);
    event Unstaked(address indexed user, uint256 indexed pid, uint256 amount);
    event WithdrawalOrUnstakeScheduled(uint256 indexed pid, uint256 amount);
    event referralPaid(address indexed referrer, uint256 amount);
    event tokenWhitelistUpdated(
        address indexed token,
        bool indexed whitelisted
    );

    struct CurveInfo {
        uint256 currentX;
        uint256 currentY;
        uint256 totalSupply;
        uint256[] unstakedTokens;
    }

    struct DepositInfo {
        uint256 projectDepositHeld;
        uint256 projectDepositInStrategy;
    }

    struct GeneralInfo {
        address token;
        uint8 tokenDecimals;
        uint16 apy;
        address projectWallet;
        string projectName;
        uint256 poolCap;
        uint256 totalStaked;
        uint256 scalingMultiplier;
    }

    struct PremiumInfo {
        uint256 premiumBalance;
        uint256 premiumAvailable;
    }

    struct ReferralInfo {
        address referrer;
        uint256 referralFee;
        uint256 endTime;
    }

    struct TimelockInfo {
        uint256 timelock;
        uint256 timeLimit;
        uint256 withdrawalScheduledAmount;
        bool withdrawalExecuted;
    }

    function YEAR() external view returns (uint256);

    function activeStrategies(uint256) external view returns (bytes32);

    function activeTokens(uint256) external view returns (address);

    function minTokenStakeAmount(address) external view returns (uint256);

    function nftInfo(uint256)
        external
        view
        returns (
            uint256 pid,
            uint256 amount,
            uint256 xDelta,
            uint256 apy,
            uint256 unclaimed,
            uint256 lastClaimedTime,
            uint256 timelock,
            uint256 timelimit,
            bool hasUnstaked
        );

    function pidNFTList(uint256, uint256) external view returns (uint256);

    function pidStrategies(uint256, bytes32) external view returns (address);

    function poolInfo(uint256)
        external
        view
        returns (
            ISaloon.GeneralInfo memory generalInfo,
            ISaloon.DepositInfo memory depositInfo,
            ISaloon.PremiumInfo memory premiumInfo,
            ISaloon.TimelockInfo memory poolTimelock,
            ISaloon.CurveInfo memory curveInfo,
            ISaloon.ReferralInfo memory referralInfo,
            uint256 assessmentPeriodEnd,
            uint256 freezeTime,
            bool isActive
        );

    function receiveStrategyYield(address _token, uint256 _amount) external;

    function referralBalances(address, address) external view returns (uint256);

    function saloonBounty() external view returns (address);

    function saloonBountyProfit(address) external view returns (uint256);

    function saloonManager() external view returns (address);

    function saloonPremiumProfit(address) external view returns (uint256);

    function saloonProjectPortal() external view returns (address);

    function saloonStrategyProfit(address) external view returns (uint256);

    function saloonView() external view returns (address);

    function strategyAddressToPid(address) external view returns (uint256);

    function strategyFactory() external view returns (address);

    function tokenWhitelist(address) external view returns (bool);
}
