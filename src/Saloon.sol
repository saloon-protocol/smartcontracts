pragma solidity ^0.8.0;

import "openzeppelin-contracts/contracts/utils/math/SafeMath.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
// import "openzeppelin-contracts/contracts/access/Ownable.sol";
import "openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
// import "openzeppelin-contracts/contracts/proxy/utils/UUPSUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";

/// Make sure accounting references deposits and stakings separately and never uses address(this) as reference
/// Ensure there is enough access control

/// `add` -> addNewBBountyPool

/* Implement:
- TODO Solve stack too deep
- DONE Add back Saloon fees and commissions
- DONE Withdraw saloon fee and commission to somewhere else
- DONE Make it upgradeable
- DONE Scheduled for withdrawals and unstaking
- DONE Project deposits
- DONE Bounty payouts needing to decrement all stakers
- DONE - Billing premium when necessary.
- DONE (all deployments go through BPM) - add token whitelist and whitelist check in `addNewBounty`

*/

contract Saloon is OwnableUpgradeable, UUPSUpgradeable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint256 public constant YEAR = 365 days;
    uint256 public constant PERIOD = 1 weeks;

    uint256 constant bountyFee = 1000; // 10%
    uint256 constant premiumFee = 1000; // 10%

    mapping(address => uint256) public saloonBountyProfit;
    mapping(address => uint256) public saloonPremiumProfit;
    uint256 public premiumBalance;

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many tokens the user has staked.
        uint256 unclaimed; // Unclaimed premium.
        uint256 lastRewardTime; // Reward debt. See explanation below.
        uint256 timelock;
        uint256 timeLimit;
        uint256 unstakeScheduledAmount;
        bool UnstakeExecuted;
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
        uint256 timelock;
        uint256 timeLimit;
        uint256 withdrawalScheduledAmount;
        bool WithdrawalExecuted;
    }

    uint256 public denominator = 100 * (1e18);

    uint16 constant BPS = 10000;

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

    // constructor() public {}

    function _authorizeUpgrade(address _newImplementation)
        internal
        virtual
        override
        onlyOwner
    {}

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new bounty pool. Can only be called by the owner.
    function addNewBountyPool(
        address _token,
        uint8 _tokenDecimals,
        address _projectWallet
    ) public onlyOwner {
        uint256 lastRewardTime = block.timestamp > startTime
            ? block.timestamp
            : startTime;

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
                initialized: false,
                timelock: 0,
                timeLimit: 0,
                withdrawalScheduledAmount: 0,
                WithdrawalExecuted: false
            })
        );
    }

    function setAPYandPoolCapAndDeposit(
        uint256 _pid,
        uint256 _poolCap,
        uint16 _apy,
        uint256 _deposit
    ) public {
        PoolInfo storage pool = poolInfo[_pid];

        require(!pool.initialized, "Pool already initialized");
        require(_apy > 0 && _apy <= 10000, "APY out of range");
        require(
            _poolCap > 100 * (10**pool.tokenDecimals) &&
                _poolCap <= 10000000 * (10**pool.tokenDecimals),
            "Pool cap out of range"
        );
        require(msg.sender == pool.projectWallet, "Not authorized");

        IERC20(pool.token).safeTransferFrom(
            msg.sender,
            address(this),
            _deposit
        );

        pool.projectDeposit = _deposit;
        pool.poolCap = _poolCap;
        pool.apy = _apy;
        pool.initialized = true;
    }

    function makeProjectDeposit(uint256 _pid, uint256 _deposit) external {
        PoolInfo storage pool = poolInfo[_pid];
        require(msg.sender == pool.projectWallet, "Not authorized");

        IERC20(pool.token).safeTransferFrom(
            msg.sender,
            address(this),
            _deposit
        );

        pool.projectDeposit += _deposit;
    }

    function scheduleProjectDepositWithdrawal(uint256 _pid, uint256 _amount)
        external
        returns (bool)
    {
        PoolInfo storage pool = poolInfo[_pid];
        require(pool.projectDeposit >= _amount, "Amount bigger than deposit");
        require(msg.sender == pool.projectWallet, "Not authorized");

        pool.timelock = block.timestamp + PERIOD;
        pool.timeLimit = block.timestamp + PERIOD + 3 days;
        pool.withdrawalScheduledAmount = _amount;
        pool.WithdrawalExecuted = false;
        return true;
    }

    function projectDepositWithdrawal(uint256 _pid, uint256 _amount)
        external
        returns (bool)
    {
        PoolInfo storage pool = poolInfo[_pid];
        require(msg.sender == pool.projectWallet, "Not authorized");
        require(
            pool.timelock < block.timestamp &&
                pool.timeLimit > block.timestamp &&
                pool.WithdrawalExecuted == false &&
                pool.withdrawalScheduledAmount >= _amount &&
                pool.timelock != 0,
            "Timelock not set or not completed in time"
        );
        pool.WithdrawalExecuted = true;

        pool.projectDeposit -= _amount;
        IERC20(pool.token).safeTransfer(pool.projectWallet, _amount);
        return true;
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to)
        public
        pure
        returns (uint256)
    {
        return _to.sub(_from);
    }

    // make into function to view Pending yield to claim
    function pendingToken(uint256 _pid, address _user)
        public
        view
        returns (uint256)
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        // uint256 accTokenPerShare = pool.accTokenPerShare; //note delete ?
        uint256 totalStaked = pool.totalStaked;
        uint256 pendingReward;
        if (block.timestamp > user.lastRewardTime && totalStaked != 0) {
            uint256 multiplier = getMultiplier(
                user.lastRewardTime,
                block.timestamp
            );

            //   10*10**6 * 10000 / 10000 / 30000000
            uint256 tokensPerSecond = ((user.amount * denominator * pool.apy) /
                BPS) / YEAR;

            uint256 tokenReward = multiplier.mul(tokensPerSecond) / denominator;

            // Check if this calcualtion is done correctly
            uint256 saloonPremiumCommission = (tokenReward * premiumFee) / BPS;

            pendingReward = tokenReward - saloonPremiumCommission;
        }
        return pendingReward;
    }

    // Stake tokens in a Bounty pool to earn premium payments.
    function stake(
        uint256 _pid,
        address _user,
        uint256 _amount
    ) external nonReentrant onlyOwner returns (bool) {
        require(_amount > 0);

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];

        _updateUserReward(_pid, _user, true);

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

    /// Schedule unstake with specific amount
    function scheduleUnstake(uint256 _pid, uint256 _amount)
        external
        returns (bool)
    {
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "Amount bigger than deposit");

        user.timelock = block.timestamp + PERIOD;
        user.timeLimit = block.timestamp + PERIOD + 3 days;
        user.unstakeScheduledAmount = _amount;
        user.UnstakeExecuted = false;
        return true;
    }

    // Withdraw LP tokens from MasterChef.
    function unstake(
        uint256 _pid,
        address _user,
        uint256 _amount
    ) external nonReentrant onlyOwner returns (bool) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        require(user.amount >= _amount, "withdraw: not good");
        require(
            user.timelock < block.timestamp &&
                user.timeLimit > block.timestamp &&
                user.UnstakeExecuted == false &&
                user.unstakeScheduledAmount >= _amount &&
                user.timelock != 0,
            "Timelock not set or not completed in time"
        );
        user.UnstakeExecuted = true;

        _updateUserReward(_pid, _user, true);

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
    function _updateUserReward(
        uint256 _pid,
        address _user,
        bool _shouldHarvest
    ) internal {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        // updatePool(0);
        if (user.amount == 0) {
            user.lastRewardTime = block.timestamp;
            return;
        }
        uint256 pending = pendingToken(_pid, _user);
        if (pending > premiumBalance) billPremium(_pid);

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
    function claimPremium(uint256 _pid, address _user)
        external
        nonReentrant
        onlyOwner
    {
        _updateUserReward(_pid, _user, true);
    }

    function billPremium(uint256 _pid) public onlyOwner returns (bool) {
        PoolInfo storage pool = poolInfo[_pid];
        // uint256 totalStaked = pool.totalStaked;
        uint16 apy = pool.apy;
        uint256 poolCap = pool.poolCap;

        uint256 premiumOwed = (((poolCap * apy * PERIOD) / BPS) / YEAR);
        IERC20(pool.token).safeTransferFrom(
            pool.projectWallet,
            address(this),
            premiumOwed
        );

        // Calculate saloon fee // TODO check if commission is calculated properly
        uint256 saloonPremiumCommission = (premiumOwed * premiumFee) / BPS;

        // update saloon claimable fee
        saloonPremiumProfit[address(pool.token)] += saloonPremiumCommission;

        // update premiumBalance
        premiumBalance += premiumOwed;

        pool.lastBilledTime = block.timestamp;

        return true;
    }

    function payBounty(
        // address _saloonWallet,
        uint256 _pid,
        address _hunter,
        uint256 _amount
    ) public onlyOwner returns (bool) {
        PoolInfo storage pool = poolInfo[_pid];
        uint256 totalStaked = pool.totalStaked;
        uint256 poolTotal = totalStaked + pool.projectDeposit;
        uint256 percentage = 0;

        if (_amount < poolTotal) {
            percentage = ((_amount * BPS) / poolTotal); // If precision is lost, amount was too low anyway.
            pool.projectDeposit -= (pool.projectDeposit * percentage) / BPS;
        } else if (_amount == poolTotal) {
            percentage = BPS;
            pool.projectDeposit = 0;
        } else {
            revert("Amount too high");
        }

        uint256 length = stakerList.length;
        for (uint256 i; i < length; ) {
            address _user = stakerList[i];
            UserInfo storage user = userInfo[_pid][_user];
            _updateUserReward(_pid, _user, false);
            user.amount -= (user.amount * percentage) / BPS;
            unchecked {
                ++i;
            }
        }

        if (_amount == poolTotal) delete stakerList;

        // calculate saloon commission //TODO check if fee commission is calcualted correctly
        uint256 saloonCommission = (_amount * bountyFee) / BPS;
        // subtract commission from payout
        uint256 hunterPayout = _amount - saloonCommission;
        // update saloon Commission variable
        saloonBountyProfit[address(pool.token)] += saloonCommission;
        // transfer payout to hunter
        pool.token.safeTransfer(_hunter, hunterPayout);

        return true;
    }

    function collectSaloonProfits(address _token, address _saloonWallet)
        external
        onlyOwner
        returns (bool)
    {
        uint256 amount = saloonBountyProfit[_token] +
            saloonPremiumProfit[_token];

        saloonBountyProfit[_token] = 0;
        saloonPremiumProfit[_token] = 0;

        IERC20(_token).safeTransfer(_saloonWallet, amount);
        return true;
    }

    function viewBountyBalance(uint256 _pid) external view returns (uint256) {
        PoolInfo memory pool = poolInfo[_pid];
        return (pool.totalStaked + pool.projectDeposit);
    }

    function viewStake(uint256 _pid) external view returns (uint256) {
        UserInfo storage user = userInfo[_pid][msg.sender];
        return user.amount;
    }

    function viewTotalStaked(uint256 _pid) external view returns (uint256) {
        PoolInfo memory pool = poolInfo[_pid];
        return pool.totalStaked;
    }

    function viewPoolCap(uint256 _pid) external view returns (uint256) {
        PoolInfo memory pool = poolInfo[_pid];
        return pool.poolCap;
    }
}
