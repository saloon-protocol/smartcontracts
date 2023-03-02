pragma solidity ^0.8.10;
import "./ISaloon.sol";

interface ISaloonBounty {
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
    event Transfer(
        address indexed from,
        address indexed to,
        uint256 indexed tokenId
    );
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

    function approve(address to, uint256 tokenId) external;

    function balanceOf(address owner) external view returns (uint256);

    function calcRequiredPremiumBalancePerPeriod(uint256 _poolCap, uint256 _apy)
        external
        pure
        returns (uint256 requiredPremiumBalance);

    function calculateEffectiveAPY(
        uint256 _pid,
        uint256 _stake,
        uint256 _x
    ) external view returns (uint256 scaledAPY);

    function claimPremium(uint256 _tokenId) external;

    function consolidate(uint256 _pid) external;

    function consolidateAll() external;

    function getAllTokensByOwner(address _owner)
        external
        view
        returns (ISaloon.NFTInfo[] memory userTokens);

    function getApproved(uint256 tokenId) external view returns (address);

    function getCurrentAPY(uint256 _pid)
        external
        view
        returns (uint256 currentAPY);

    function index() external view returns (uint256);

    function initialize(address _strategyFactory) external;

    function isApprovedForAll(address owner, address operator)
        external
        view
        returns (bool);

    function minTokenStakeAmount(address) external view returns (uint256);

    function name() external view returns (string memory);

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

    function ownerOf(uint256 tokenId) external view returns (address);

    function payBounty(
        uint256 __pid,
        address _hunter,
        uint16 _payoutBPS,
        uint16 _hunterBonusBPS
    ) external;

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

    function receiveStrategyYield(address _token, uint256 _amount) external;

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

    function saloonBountyProfit(address) external view returns (uint256);

    function saloonPremiumProfit(address) external view returns (uint256);

    function saloonStrategyProfit(address) external view returns (uint256);

    function scheduleUnstake(uint256 _tokenId) external returns (bool);

    function setApprovalForAll(address operator, bool approved) external;

    function stake(uint256 _pid, uint256 _amount) external returns (uint256);

    function strategyAddressToPid(address) external view returns (uint256);

    function supportsInterface(bytes4 interfaceId) external view returns (bool);

    function symbol() external view returns (string memory);

    function tokenURI(uint256 tokenId) external view returns (string memory);

    function tokenWhitelist(address) external view returns (bool);

    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external;

    function transferOwnership(address newOwner) external;

    function unstake(uint256 _tokenId, bool _shouldHarvest)
        external
        returns (bool);

    function viewBountyBalance(uint256 _pid) external view returns (uint256);
}
