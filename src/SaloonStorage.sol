// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
// import "openzeppelin-contracts-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";
// import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
// import "./lib/OwnableUpgradeable.sol";
// import "./BountyTokenNFT.sol";
import "./interfaces/IStrategyFactory.sol";
import "./lib/SaloonLib.sol";
import "./interfaces/ISaloon.sol";
import "./interfaces/ISaloonManager.sol";
import "./interfaces/ISaloonProjectPortal.sol";
import "./interfaces/ISaloonBounty.sol";
import "./interfaces/ISaloonView.sol";

// import "./SaloonBounty.sol";
// import "./SaloonManager.sol";
// import "./SaloonProjectPortal.sol";

contract SaloonStorage is ISaloon {
    ISaloonManager public saloonManager;
    ISaloonProjectPortal public saloonProjectPortal;
    ISaloonBounty public saloonBounty;
    ISaloonView public saloonView;

    uint256 public constant YEAR = 365 days;
    uint256 constant PERIOD = 1 weeks;
    uint256 constant saloonFee = 1000; // 10%
    uint256 constant DEFAULT_APY = 1.06 ether; //NOTE is this ever used?
    uint256 constant BPS = 10_000;
    uint256 constant PRECISION = 1e18;

    // Info of each pool.
    PoolInfo[] public poolInfo;

    // tokenId => NFTInfo
    mapping(uint256 => NFTInfo) public nftInfo;
    // pid => tokenIds[]
    mapping(uint256 => uint256[]) public pidNFTList;

    // token => amount
    mapping(address => uint256) public saloonBountyProfit;
    mapping(address => uint256) public saloonPremiumProfit;
    mapping(address => uint256) public saloonStrategyProfit;
    mapping(address => mapping(address => uint256)) public referralBalances; // referrer => token => amount

    // Strategy factory to deploy unique strategies for each pid. No co-mingling.
    IStrategyFactory public strategyFactory;

    // Mapping of all strategies for pid
    // pid => keccak256(abi.encode(strategyName)) => strategy address
    mapping(uint256 => mapping(bytes32 => address)) public pidStrategies;

    // Mapping of active strategy for pid
    mapping(uint256 => bytes32) public activeStrategies;

    // Reverse mapping of strategy to pid for easy lookup
    mapping(address => uint256) public strategyAddressToPid;

    // Mapping of whitelisted tokens
    mapping(address => bool) public tokenWhitelist;

    // Mapping of whitelisted tokens
    address[] public activeTokens;

    // Minimum stake amounts per token.
    mapping(address => uint256) public minTokenStakeAmount;
}
