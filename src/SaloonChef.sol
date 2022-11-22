pragma solidity ^0.8.0;

import "openzeppelin-contracts/contracts/utils/math/SafeMath.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";
import "openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";

/// Make sure accounting references deposits and stakings separately and never uses address(this) as reference
/// Ensure there is enough access control

/// `add` -> addNewBBountyPool

/* Implement:
- Scheduled withdrawals
- Project deposits
- DONE Bounty payouts needing to decrement all stakers
- DONE - Billing premium when necessary.
- DONE (all deployments go through BPM) - add token whitelist and whitelist check in `addNewBounty`
- Make it upgradeable
- Add back Saloon fees
*/

///NOTE `tokensPerSecond` needs to be substituted by something `tokenReward`

contract SaloonChef is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint256 public constant YEAR = 365 days;
    uint256 public constant PERIOD = 1 weeks;

    uint256 public bountyCommission;
    uint256 public premiumCommission;

    uint256 public saloonBountyCommission;
    uint256 public saloonPremiumFees;
    uint256 public premiumBalance;

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 lastRewardTime; // Reward debt. See explanation below.
        uint256 unclaimed; // Unclaimed reward in Oasis.

        //
        // We do some fancy math here. Basically, any point in time, the amount of Tokens
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accTokenPerShare) - user.lastTokenPerShare
        //
        // Whenever a user deposits or withdraws Tokens to a pool. Here's what happens:
        //   1. The pool's `accTokenPerShare` (and `lastRewardTime`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `lastTokenPerShare` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 token; // Address of LP token contract.
        uint8 tokenDecimals;
        address projectWallet;
        uint256 allocPoint; // How many allocation points assigned to this pool. Tokens to distribute per block.
        uint256 projectDeposit;
        uint16 apy;
        uint256 poolCap;
        uint256 totalStaked;
        uint256 lastRewardTime; // Last block number that Tokens distribution occurs.
        uint256 lastBilledTime;
        uint256 accTokenPerShare; // Accumulated Tokens per share, times 1e18. See below.
        bool initialized;
    }

    // Dev address.
    address public devaddr;

    // Bonus muliplier for early cake makers.
    uint256 public denominator = 100 * (1e18);

    uint16 public BPS = 10000;

    address[] public stakerList;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    // The block number when CAKE mining starts.
    uint256 public startTime;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount
    );

    constructor(address _devaddr, uint256 _startTime) public {
        devaddr = _devaddr;
        startTime = _startTime;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new l to the pool. Can only be called by the owner.
    function initialize(
        address _token,
        uint8 _tokenDecimals,
        address _projectWallet
        // bool _withUpdate //note should be this defaulted to true or false?
    ) public onlyOwner {
        // if (_withUpdate) {
        //     massUpdatePools(); //note is this necessary?
        // }
        uint256 lastRewardTime = block.timestamp > startTime
            ? block.timestamp
            : startTime;

        // totalAllocPoint = totalAllocPoint.add(_allocPoint); // note this doesnt seem necessary
        poolInfo.push(
            PoolInfo({
                token: IERC20(_token),
                tokenDecimals: _tokenDecimals,
                projectWallet: _projectWallet,
                allocPoint: 0,
                projectDeposit: 0,
                apy: 0,
                poolCap: 0,
                totalStaked: 0,
                lastRewardTime: lastRewardTime,
                lastBilledTime: 0,
                accTokenPerShare: 0,
                initialized: false
            })
        );

    }

    function setAPYandPoolCap(
        // uint256 _pid,
        uint256 _poolCap,
        uint16 _apy
    ) public onlyOwner {
        PoolInfo storage pool = poolInfo[0];

        require(!pool.initialized, "Pool already initialized");
        require(_apy > 0 && _apy <= 10000, "APY out of range");
        require(_poolCap > 100 * (10**pool.tokenDecimals) && _poolCap <= 10000000 * (10**pool.tokenDecimals), "Pool cap out of range");
        // transferfrom token
        pool.poolCap = _poolCap;
        pool.apy = _apy;
        pool.initialized = true;
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to)
        public
        view
        returns (uint256)
    {
        return _to.sub(_from);
    }

    // make into function to view Pending yield to claim
    function pendingToken(address _user)
        public
        view
        returns (uint256)
    {
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[0][_user];
        uint256 accTokenPerShare = pool.accTokenPerShare;
        uint256 totalStaked = pool.totalStaked;
        uint256 tokenReward = 0;
        if (block.timestamp > user.lastRewardTime && totalStaked != 0) {
            uint256 multiplier = getMultiplier(
                user.lastRewardTime,
                block.timestamp
            );

            // note/todo should we calculate tokensPerSecond based on user.amount or totalStaked and APY?
            uint256 tokensPerSecond = ((user.amount * denominator * pool.apy) / BPS) / YEAR;
                                //     10*10**6 * 10000 / 10000 / 30000000
            tokenReward = multiplier.mul(tokensPerSecond) / denominator;
        }
        return tokenReward;
    }

    // Stake tokens in a Bounty pool to earn premium payments.
    function stake(address _user, uint256 _amount) external nonReentrant onlyOwner returns (bool) {
        require(_amount > 0);

        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[0][_user];

        _updateUserReward(_user, true);

        if (user.amount == 0) stakerList.push(_user);

        pool.token.safeTransferFrom(_user, address(this), _amount);
        user.amount = user.amount.add(_amount);
        pool.totalStaked = pool.totalStaked.add(_amount);

        require(
            pool.poolCap > 0 && pool.totalStaked <= pool.poolCap,
            "Exceeded pool limit"
        );



        // emit Deposit(msg.sender, _pid, _amount); //todo change to Staking event
        return true;
    }

    // Withdraw LP tokens from MasterChef.
    function unstake(address _user, uint256 _amount) external nonReentrant onlyOwner returns (bool) {
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[0][_user];
        require(user.amount >= _amount, "withdraw: not good");

        _updateUserReward(_user, true);

        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.totalStaked = pool.totalStaked.sub(_amount);
            pool.token.safeTransfer(_user, _amount);
        }

        if (user.amount == 0) {
            uint256 length = stakerList.length;
            for (uint256 i; i < length; ) {
                if (stakerList[i] == _user) {
                    address lastAddress = stakerList[length - 1];
                    stakerList[i] = lastAddress;
                    stakerList.pop();
                    break;
                }

                unchecked {
                    ++i;
                }
            }
        }
        
        // emit Withdraw(msg.sender, 0, _amount);
        return true;
    }

    // // Withdraw without caring about rewards. EMERGENCY ONLY.
    // function emergencyWithdraw(uint256 _pid) external nonReentrant onlyOwner {
    //     PoolInfo storage pool = poolInfo[_pid];
    //     UserInfo storage user = userInfo[_pid][msg.sender];
    //     pool.token.safeTransfer(address(msg.sender), user.amount);
    //     emit EmergencyWithdraw(msg.sender, _pid, user.amount);
    //     user.amount = 0;
    //     user.lastTokenPerShare = 0;
    // }

    // Update the rewards of caller, and harvests if needed
    function _updateUserReward(address _user, bool _shouldHarvest) internal {
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[0][_user];
        // updatePool(0);
        if (user.amount == 0) {
            user.lastRewardTime = block.timestamp;
            return;
        }
        uint256 pending = pendingToken(_user);
        if (pending > premiumBalance) billPremium();

        if (!_shouldHarvest) {
            user.unclaimed += pending;
            user.lastRewardTime = block.timestamp;
            return;
        }

        uint256 totalPending = pending + user.unclaimed;
        if (totalPending > 0) {
            pool.token.safeTransfer(_user, totalPending);
            user.unclaimed = 0;
        }
        user.lastRewardTime = block.timestamp;
    }

    // Harvest one pool
    function claimPremium(address _user) external nonReentrant onlyOwner {
        _updateUserReward(_user, true);
    }


    function billPremium()
        public
        onlyOwner
        returns (bool)
    {
        PoolInfo storage pool = poolInfo[0];
        uint256 totalStaked = pool.totalStaked;
        uint16 apy = pool.apy;
        uint256 poolCap = pool.poolCap;

        uint256 premiumOwed = (((poolCap * apy * PERIOD) / BPS) / YEAR);
        IERC20(pool.token).safeTransferFrom(
            pool.projectWallet,
            address(this),
            premiumOwed
        );

        // // Calculate saloon fee
        // uint256 saloonFee = (premiumOwed * premiumCommission) / denominator;

        // // update saloon claimable fee
        // saloonPremiumFees += saloonFee;

        // update premiumBalance
        premiumBalance += premiumOwed;

        pool.lastBilledTime = block.timestamp;

        return true;
    }

    function payBounty(
        // address _saloonWallet,
        address _hunter,
        uint256 _amount
    ) 
    public 
    onlyOwner
    returns (bool) {
        PoolInfo storage pool = poolInfo[0];
        uint256 totalStaked = pool.totalStaked;
        uint256 poolTotal = totalStaked + pool.projectDeposit;
        uint256 percentage = 0;
        
        if (_amount < poolTotal) {
            percentage = (_amount * BPS / poolTotal); // If precision is lost, amount was too low anyway.  
            pool.projectDeposit -= pool.projectDeposit * percentage / BPS;          
        } else if (_amount == poolTotal) {
            percentage = BPS;
            pool.projectDeposit = 0;  
        } else {
            revert("Amount too high");
        }

        uint256 length = stakerList.length;
        for (uint256 i; i < length; ) {
            address _user = stakerList[i];
            UserInfo storage user = userInfo[0][_user];
            _updateUserReward(_user, false);
            user.amount -= user.amount * percentage / BPS;
            unchecked {
                ++i;
            }
        }

        if (_amount == poolTotal) delete stakerList;
        pool.token.safeTransfer(_hunter, _amount);

        return true;


    }

    function collectSaloonPremiumFees(address _token, address _saloonWallet)
        external
        // onlyManager
        returns (uint256)
    {}

    function viewBountyBalance() external view returns (uint256) {
        PoolInfo memory pool = poolInfo[0];
        return pool.totalStaked;
    }

    function viewStakersDeposit() external view returns (uint256) {
        UserInfo storage user = userInfo[0][msg.sender];
        return user.amount;
    }

    function viewPoolCap() external view returns (uint256) {
        PoolInfo memory pool = poolInfo[0];
        return pool.poolCap;
    }

}