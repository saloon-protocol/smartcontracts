// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;
import "./interfaces/IStrategyFactory.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
//NOTE CAN THIS Inherit constants?
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

/// @dev Logically separated part of the storage structure, which is responsible for everything related to proxy upgrades and diamond cuts
/// @param proposedDiamondCutHash The hash of diamond cut that was proposed in the current upgrade
/// @param proposedDiamondCutTimestamp The timestamp when the diamond cut was proposed, zero if there are no active proposals
/// @param lastDiamondFreezeTimestamp The timestamp when the diamond was frozen last time, zero if the diamond was never frozen
/// @param currentProposalId The serial number of proposed diamond cuts, increments when proposing a new diamond cut
/// @param securityCouncilMembers The set of the trusted addresses that can instantly finish upgrade (diamond cut)
/// @param securityCouncilMemberLastApprovedProposalId The mapping of the security council addresses and the last diamond cut that they approved
/// @param securityCouncilEmergencyApprovals The number of received upgrade approvals from the security council
struct DiamondCutStorage {
    //NOTE TODO FIXME probably erase many of these as they are probs no necessary
    bytes32 proposedDiamondCutHash;
    uint256 proposedDiamondCutTimestamp;
    uint256 lastDiamondFreezeTimestamp;
    uint256 currentProposalId;
    mapping(address => bool) securityCouncilMembers;
    mapping(address => uint256) securityCouncilMemberLastApprovedProposalId;
    uint256 securityCouncilEmergencyApprovals;
}

// NOTE Perhaps separating structs into Interfaces might be a good way to do things, but maybe not
/// @dev storing all storage variables for Saloon facets
/// NOTE: It is used in a proxy, so it is possible to add new variables to the end
/// NOTE: but NOT to modify already existing variables or change their order
struct AppStorage {
    DiamondCutStorage diamondCutStorage;
    uint256 upgradeNoticePeriod;
    uint256 approvalsForEmergencyUpgrade;
    address owner;
    address pendingOwner;
    // Info of each pool.
    PoolInfo[] poolInfo;
    // tokenId => NFTInfo
    mapping(uint256 => NFTInfo) nftInfo;
    // pid => tokenIds[]
    mapping(uint256 => uint256[]) pidNFTList;
    // token => amount
    mapping(address => uint256) saloonBountyProfit;
    mapping(address => uint256) saloonPremiumProfit;
    mapping(address => uint256) saloonStrategyProfit;
    mapping(address => mapping(address => uint256)) referralBalances; // referrer => token => amount
    // Strategy factory to deploy unique strategies for each pid. No co-mingling.
    IStrategyFactory strategyFactory;
    // Mapping of all strategies for pid
    // pid => keccak256(abi.encode(strategyName)) => strategy address
    mapping(uint256 => mapping(bytes32 => address)) pidStrategies;
    // Mapping of active strategy for pid
    mapping(uint256 => bytes32) activeStrategies;
    // Reverse mapping of strategy to pid for easy lookup
    mapping(address => uint256) strategyAddressToPid;
    // Mapping of whitelisted tokens
    mapping(address => bool) tokenWhitelist;
    // Mapping of whitelisted tokens
    address[] activeTokens;
    // Minimum stake amounts per token.
    mapping(address => uint256) minTokenStakeAmount;
}
