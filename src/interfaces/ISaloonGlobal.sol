// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "./ISaloonManager.sol";
import "./ISaloonProjectPortal.sol";
import "./ISaloonBounty.sol";
import "./ISaloonView.sol";

interface ISaloonGlobal {
    // Info of each pool.
    struct PoolInfo {
        GeneralInfo generalInfo;
        DepositInfo depositInfo;
        PremiumInfo premiumInfo;
        TimelockInfo poolTimelock;
        CurveInfo curveInfo;
        ReferralInfo referralInfo;
        uint256 assessmentPeriodEnd;
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
        bool hasUnstaked;
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
    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );
    event Initialized(uint8 version);
    event AdminChanged(address previousAdmin, address newAdmin);
    event BeaconUpgraded(address indexed beacon);
    event Approval(
        address indexed owner,
        address indexed approved,
        uint256 indexed tokenId
    );
    event ApprovalForAll(
        address indexed owner,
        address indexed operator,
        bool approved
    );
    event Transfer(
        address indexed from,
        address indexed to,
        uint256 indexed tokenId
    );

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

    function owner() external view returns (address);

    function pidNFTList(uint256, uint256) external view returns (uint256);

    function pidStrategies(uint256, bytes32) external view returns (address);

    function receiveStrategyYield(address _token, uint256 _amount) external;

    function acceptOwnershipTransfer() external;

    function activeStrategies(uint256) external view returns (bytes32);

    function activeTokens(uint256) external view returns (address);

    function initialize() external;

    function initialize(
        //SaloonRelay
        ISaloonManager _saloonManager,
        ISaloonProjectPortal _saloonProjectPortal,
        ISaloonBounty _saloonBounty,
        ISaloonView _saloonView
    ) external;

    function calcRequiredPremiumBalancePerPeriod(uint256 _poolCap, uint256 _apy)
        external
        pure
        returns (uint256 requiredPremiumBalance);

    function compoundYieldForPid(uint256 _pid) external;

    function minTokenStakeAmount(address) external view returns (uint256);

    function projectDepositWithdrawal(uint256 _pid, uint256 _amount)
        external
        returns (bool);

    function proxiableUUID() external view returns (bytes32);

    function saloonBountyProfit(address) external view returns (uint256);

    function saloonPremiumProfit(address) external view returns (uint256);

    function saloonStrategyProfit(address) external view returns (uint256);

    function scheduleProjectDepositWithdrawal(uint256 _pid, uint256 _amount)
        external
        returns (bool);

    function setAPYandPoolCapAndDeposit(
        uint256 _pid,
        uint256 _poolCap,
        uint16 _apy,
        uint256 _deposit,
        string memory _strategyName
    ) external;

    function strategyAddressToPid(address) external view returns (uint256);

    function tokenWhitelist(address) external view returns (bool);

    function transferOwnership(address newOwner) external;

    function updateProjectWalletAddress(uint256 _pid, address _projectWallet)
        external;

    function upgradeTo(address newImplementation) external;

    function upgradeToAndCall(address newImplementation, bytes memory data)
        external
        payable;

    function viewBountyBalance(uint256 _pid) external view returns (uint256);

    function windDownBounty(uint256 _pid) external returns (bool);

    function withdrawProjectYield(uint256 _pid)
        external
        returns (uint256 returnedAmount);

    function addNewBountyPool(
        address _token,
        address _projectWallet,
        string memory _projectName,
        address _referrer,
        uint256 _referralFee,
        uint256 _referralEndTime
    ) external returns (uint256);

    function billPremium(uint256 _pid) external returns (bool);

    function collectAllReferralProfits() external returns (bool);

    function collectAllSaloonProfits(address _saloonWallet)
        external
        returns (bool);

    function collectReferralProfit(address _token) external returns (bool);

    function collectSaloonProfits(address _token, address _saloonWallet)
        external
        returns (bool);

    function extendReferralPeriod(uint256 _pid, uint256 _endTime) external;

    function updateTokenWhitelist(
        address _token,
        bool _whitelisted,
        uint256 _minStakeAmount
    ) external returns (bool);

    function setStrategyFactory(address) external;

    function viewTokenWhitelistStatus(address _token)
        external
        view
        returns (bool);

    function approve(address to, uint256 tokenId) external;

    function balanceOf(address owner) external view returns (uint256);

    function claimPremium(uint256 _tokenId) external;

    function consolidate(uint256 _pid) external;

    function consolidateAll() external;

    function getAllTokensByOwner(address _owner)
        external
        view
        returns (ISaloon.NFTInfo[] memory userTokens);

    function getCurrentAPY(uint256 _pid)
        external
        view
        returns (uint256 currentAPY);

    function index() external view returns (uint256);

    function name() external view returns (string memory);

    function isApprovedForAll(address owner, address operator)
        external
        view
        returns (bool);

    function ownerOf(uint256 tokenId) external view returns (address);

    function payBounty(
        uint256 __pid,
        address _hunter,
        uint16 _payoutBPS,
        uint16 _hunterBonusBPS
    ) external;

    function referralBalances(address, address) external view returns (uint256);

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external;

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) external;

    function supportsInterface(bytes4 interfaceId) external view returns (bool);

    function symbol() external view returns (string memory);

    function tokenURI(uint256 tokenId) external view returns (string memory);

    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external;

    function setApprovalForAll(address operator, bool approved) external;

    function stake(uint256 _pid, uint256 _amount) external returns (uint256);

    function scheduleUnstake(uint256 _tokenId) external returns (bool);

    function unstake(uint256 _tokenId, bool _shouldHarvest)
        external
        returns (bool);

    function YEAR() external view returns (uint256);

    function strategyFactory() external view returns (address);

    function viewBountyInfo(uint256 _pid)
        external
        view
        returns (
            uint256 payout,
            uint256 apy,
            uint256 staked,
            uint256 poolCap
        );

    function viewHackerPayout(uint256 _pid) external view returns (uint256);

    function viewMinProjectDeposit(uint256 _pid)
        external
        view
        returns (uint256);

    function viewPoolAPY(uint256 _pid) external view returns (uint256);

    function viewPoolCap(uint256 _pid) external view returns (uint256);

    function viewPoolPremiumInfo(uint256 _pid)
        external
        view
        returns (
            uint256 requiredPremiumBalancePerPeriod,
            uint256 premiumBalance,
            uint256 premiumAvailable
        );

    function viewPoolTimelockInfo(uint256 _pid)
        external
        view
        returns (
            uint256 timelock,
            uint256 timeLimit,
            uint256 withdrawalScheduledAmount
        );

    function viewReferralBalance(address _referrer, address _token)
        external
        view
        returns (uint256 referralBalance);

    function viewSaloonProfitBalance(address _token)
        external
        view
        returns (
            uint256 totalProfit,
            uint256 bountyProfit,
            uint256 strategyProfit,
            uint256 premiumProfit
        );

    function viewTokenInfo(uint256 _tokenId)
        external
        view
        returns (
            uint256 amount,
            uint256 apy,
            uint256 actualPending,
            uint256 unclaimed,
            uint256 timelock
        );

    function viewTotalStaked(uint256 _pid) external view returns (uint256);

    function setImplementations(
        ISaloonManager _saloonManager,
        ISaloonProjectPortal _saloonProjectPortal,
        ISaloonBounty _saloonBounty,
        ISaloonView _saloonView
    ) external;

    function initManager(ISaloonManager _saloonManager) external;

    function initProjectPortal(ISaloonProjectPortal _saloonProjectPortal)
        external;

    function initSaloonBounty(ISaloonBounty _saloonBounty) external;
}
