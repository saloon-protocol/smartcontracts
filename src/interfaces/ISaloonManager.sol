pragma solidity ^0.8.10;
import "./ISaloon.sol";
import "./ISaloonBounty.sol";
import "./ISaloonProjectPortal.sol";

interface ISaloonManager {
    event AdminChanged(address previousAdmin, address newAdmin);
    event BeaconUpgraded(address indexed beacon);
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
    event Initialized(uint8 version);
    event NewBountyDeployed(
        uint256 indexed pid,
        address indexed token,
        uint256 tokenDecimals
    );
    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );
    event PremiumBilled(uint256 indexed pid, uint256 amount);
    event Staked(address indexed user, uint256 indexed pid, uint256 amount);
    event Unstaked(address indexed user, uint256 indexed pid, uint256 amount);
    event Upgraded(address indexed implementation);
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

    function acceptOwnershipTransfer() external;

    function activeStrategies(uint256) external view returns (bytes32);

    function activeTokens(uint256) external view returns (address);

    function addNewBountyPool(
        address _token,
        address _projectWallet,
        string memory _projectName,
        address _referrer,
        uint256 _referralFee,
        uint256 _referralEndTime
    ) external returns (uint256);

    function billPremium(uint256 _pid) external returns (bool);

    function calcRequiredPremiumBalancePerPeriod(uint256 _poolCap, uint256 _apy)
        external
        pure
        returns (uint256 requiredPremiumBalance);

    function collectAllReferralProfits() external returns (bool);

    function collectAllSaloonProfits(address _saloonWallet)
        external
        returns (bool);

    function collectReferralProfit(address _token) external returns (bool);

    function collectSaloonProfits(address _token, address _saloonWallet)
        external
        returns (bool);

    function extendReferralPeriod(uint256 _pid, uint256 _endTime) external;

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
            uint256 timelimit
        );

    function owner() external view returns (address);

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
            uint256 freezeTime,
            bool isActive
        );

    function proxiableUUID() external view returns (bytes32);

    function receiveStrategyYield(address _token, uint256 _amount) external;

    function referralBalances(address, address) external view returns (uint256);

    function saloonBountyProfit(address) external view returns (uint256);

    function saloonPremiumProfit(address) external view returns (uint256);

    function saloonStrategyProfit(address) external view returns (uint256);

    function setImplementations(
        ISaloonManager,
        ISaloonProjectPortal,
        ISaloonBounty
    ) external;

    function setStrategyFactory(address) external;

    function strategyAddressToPid(address) external view returns (uint256);

    function tokenWhitelist(address) external view returns (bool);

    function transferOwnership(address newOwner) external;

    function updateTokenWhitelist(
        address _token,
        bool _whitelisted,
        uint256 _minStakeAmount
    ) external returns (bool);

    function upgradeTo(address newImplementation) external;

    function upgradeToAndCall(address newImplementation, bytes memory data)
        external
        payable;

    function viewBountyBalance(uint256 _pid) external view returns (uint256);
}
