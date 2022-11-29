// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "openzeppelin-contracts/contracts/utils/math/SafeMath.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "./ISaloon.sol";

/// Make sure accounting references deposits and stakings separately and never uses address(this) as reference
/// Ensure there is enough access control

/* Implement:
- DONE add token whitelisting
- TEST event emissions
- DONE Saloon collect all profits
- TEST Wind down (kill) bounties
- TEST Ownership transfer
- DONE Solve stack too deep
- DONE Add back Saloon fees and commissions
- DONE Withdraw saloon fee and commission to somewhere else
- DONE Make it upgradeable
- DONE Scheduled for withdrawals and unstaking
- DONE Project deposits
- DONE Bounty payouts needing to decrement all stakers
- DONE - Billing premium when necessary.
- DONE (all deployments go through BPM) - add token whitelist and whitelist check in `addNewBounty`
- DONE All necessary view functions

*/

contract Saloon is
    ISaloon,
    OwnableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuard
{
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    uint256 constant YEAR = 365 days;
    uint256 constant PERIOD = 1 weeks;
    uint16 constant bountyFee = 1000; // 10%
    uint16 constant premiumFee = 1000; // 10%
    uint16 constant BPS = 10000;
    uint256 constant PRECISION = 1e18;
    address pendingOwner;
    mapping(address => uint256) public saloonBountyProfit;
    mapping(address => uint256) public saloonPremiumProfit;
    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many tokens the user has staked.
        uint256 unclaimed; // Unclaimed premium.
        uint256 lastRewardTime; // Reward debt. See explanation below.
        uint256 timelock;
        uint256 timeLimit;
        uint256 unstakeScheduledAmount;
        bool unstakeExecuted;
    }

    // Info of each pool.
    PoolInfo[] public poolInfo;

    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    // Mapping of whitelisted tokens
    mapping(address => bool) public tokenWhitelist;
    // Mapping of whitelisted tokens
    address[] public activeTokens;

    event NewBountyDeployed(
        uint256 indexed pid,
        address indexed token,
        uint256 indexed tokenDecimals
    );

    event Staked(address indexed user, uint256 indexed pid, uint256 amount);
    event Unstaked(address indexed user, uint256 indexed pid, uint256 amount);

    event BountyBalanceChanged(
        uint256 indexed pid,
        uint256 indexed oldAmount,
        uint256 indexed newAmount
    );

    event PremiumBilled(uint256 indexed pid, uint256 indexed amount);

    event BountyPaid(
        uint256 indexed time,
        address indexed hunter,
        address indexed token,
        uint256 amount
    );

    event WithdrawalOrUnstakeScheduled(
        uint256 indexed pid,
        uint256 indexed amount
    );

    event tokenWhitelistUpdated(
        address indexed token,
        bool indexed whitelisted
    );

    modifier activePool(uint256 _pid) {
        PoolInfo memory pool = poolInfo[_pid];
        if (!pool.isActive) revert("pool not active");
        _;
    }

    function initialize() public initializer {
        __Ownable_init();
    }

    function _authorizeUpgrade(address _newImplementation)
        internal
        virtual
        override
        onlyOwner
    {}

    // function renounceOwnership() public view override onlyOwner {
    //     revert("not allowed");
    // }

    // function transferOwnership(address newOwner) public override onlyOwner {
    //     require(
    //         newOwner != address(0),
    //         "Ownable: new owner is the zero address"
    //     );
    //     pendingOwner = newOwner;
    // }

    // function acceptOwnershipTransfer() external {
    //     require(
    //         pendingOwner == msg.sender,
    //         "only pending owner can accept transfer"
    //     );
    //     _owner = pendingOwner;
    // }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    function updateTokenWhitelist(address _token, bool _whitelisted)
        external
        onlyOwner
        returns (bool)
    {
        require(
            tokenWhitelist[_token] == !_whitelisted,
            "whitelist already set"
        );
        tokenWhitelist[_token] = _whitelisted;
        emit tokenWhitelistUpdated(_token, _whitelisted);

        if (_whitelisted) {
            activeTokens.push(_token);
        } else {
            uint256 activeTokenLength = activeTokens.length;
            for (uint256 i; i < activeTokenLength; ++i) {
                address token = activeTokens[i];
                if (token == _token) {
                    activeTokens[i] = activeTokens[activeTokenLength - 1];
                    activeTokens.pop();
                    return true;
                }
            }
        }

        return true;
    }

    // Add a new bounty pool. Can only be called by the owner.
    function addNewBountyPool(
        address _token,
        address _projectWallet,
        string memory _projectName
    ) external onlyOwner returns (uint256) {
        require(tokenWhitelist[_token], "token not whitelisted");
        // uint8 _tokenDecimals = IERC20(_token).decimals();
        (,bytes memory _decimals) = _token.staticcall(abi.encodeWithSignature("decimals()"));
        uint8 decimals = abi.decode(_decimals, (uint8));

        PoolInfo memory newBounty;
        newBounty.token = IERC20(_token);

        // PLEASE FIX THIS HARDODE
        newBounty.tokenDecimals = decimals;
        // PRETTY PLEASE

        newBounty.projectWallet = _projectWallet;
        newBounty.projectName = _projectName;
        newBounty.projectDeposit = 0;
        newBounty.apy = 0;
        newBounty.poolCap = 0;
        newBounty.totalStaked = 0;
        newBounty.poolTimelock.timelock = 0;
        newBounty.poolTimelock.timeLimit = 0;
        newBounty.poolTimelock.withdrawalScheduledAmount = 0;
        newBounty.poolTimelock.withdrawalExecuted = false;
        newBounty.stakerList;
        newBounty.isActive = false;
        newBounty.freezeTime = 0;
        poolInfo.push(newBounty);
        // emit event
        return (poolInfo.length - 1);
    }

    function windDownBounty(uint256 _pid) external returns (bool) {
        PoolInfo storage pool = poolInfo[_pid];
        // require(
        //     msg.sender == pool.projectWallet || msg.sender == _owner,
        //     "Not authorized"
        // );
        pool.isActive = false;
        pool.freezeTime = block.timestamp;
        return true;
    }

    //todo change order of names to match inputs
    function setAPYandPoolCapAndDeposit(
        uint256 _pid,
        uint256 _poolCap,
        uint16 _apy,
        uint256 _deposit
    ) external {
        PoolInfo storage pool = poolInfo[_pid];
        require(!pool.isActive, "Pool already initialized");
        require(_apy > 0 && _apy <= 10000, "APY out of range");
        require(
            _poolCap >= 100 * (10**pool.tokenDecimals) &&
                _poolCap <= 10000000 * (10**pool.tokenDecimals),
            "Pool cap out of range"
        );
        require(msg.sender == pool.projectWallet, "Not authorized");
        // requiredPremiumBalancePerPeriod includes Saloons commission
        uint256 requiredPremiumBalancePerPeriod = (((_poolCap * _apy * PERIOD) /
            BPS) / YEAR);

        uint256 saloonCommission = (requiredPremiumBalancePerPeriod * //note could make this a pool.variable
            premiumFee) / BPS;

        IERC20(pool.token).safeTransferFrom(
            msg.sender,
            address(this),
            _deposit + requiredPremiumBalancePerPeriod
        );
        pool.projectDeposit += _deposit;
        pool.poolCap = _poolCap;
        pool.apy = _apy;
        pool.isActive = true;
        pool.premiumBalance = requiredPremiumBalancePerPeriod;
        pool.requiredPremiumBalancePerPeriod = requiredPremiumBalancePerPeriod;
        pool.premiumAvailable =
            requiredPremiumBalancePerPeriod -
            saloonCommission;
    }

    function makeProjectDeposit(uint256 _pid, uint256 _deposit) external {
        PoolInfo storage pool = poolInfo[_pid];
        require(msg.sender == pool.projectWallet, "Not authorized");

        uint256 balanceBefore = pool.totalStaked + pool.projectDeposit;
        IERC20(pool.token).safeTransferFrom(
            msg.sender,
            address(this),
            _deposit
        );
        pool.projectDeposit += _deposit;
        uint256 balanceAfter = pool.totalStaked + pool.projectDeposit;

        emit BountyBalanceChanged(_pid, balanceBefore, balanceAfter);
    }

    function scheduleProjectDepositWithdrawal(uint256 _pid, uint256 _amount)
        external
        returns (bool)
    {
        PoolInfo storage pool = poolInfo[_pid];
        require(pool.projectDeposit >= _amount, "Amount bigger than deposit");
        require(msg.sender == pool.projectWallet, "Not authorized");
        pool.poolTimelock.timelock = block.timestamp + PERIOD;
        pool.poolTimelock.timeLimit = block.timestamp + PERIOD + 3 days;
        pool.poolTimelock.withdrawalScheduledAmount = _amount;
        pool.poolTimelock.withdrawalExecuted = false;

        emit WithdrawalOrUnstakeScheduled(_pid, _amount);
        return true;
    }

    function projectDepositWithdrawal(uint256 _pid, uint256 _amount)
        external
        returns (bool)
    {
        PoolInfo storage pool = poolInfo[_pid];
        require(msg.sender == pool.projectWallet, "Not authorized");
        require(
            pool.poolTimelock.timelock < block.timestamp &&
                pool.poolTimelock.timeLimit > block.timestamp &&
                pool.poolTimelock.withdrawalExecuted == false &&
                pool.poolTimelock.withdrawalScheduledAmount >= _amount &&
                pool.poolTimelock.timelock != 0,
            "Timelock not set or not completed in time"
        );
        pool.poolTimelock.withdrawalExecuted = true;

        uint256 balanceBefore = pool.totalStaked + pool.projectDeposit;
        pool.projectDeposit -= _amount;
        IERC20(pool.token).safeTransfer(pool.projectWallet, _amount);
        uint256 balanceAfter = pool.totalStaked + pool.projectDeposit;

        emit BountyBalanceChanged(_pid, balanceBefore, balanceAfter);
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

        uint256 totalStaked = pool.totalStaked;
        uint256 pendingReward;
        uint256 endTime = pool.freezeTime != 0
            ? pool.freezeTime
            : block.timestamp;
        if (endTime > user.lastRewardTime && totalStaked != 0) {
            // multiplier = number of seconds
            uint256 multiplier = getMultiplier(user.lastRewardTime, endTime);
            uint256 tokenReward = (((user.amount * pool.apy) / BPS) *
                multiplier) / YEAR;

            // note saloonPremiumProfit variable is updated in billPremium()

            pendingReward = tokenReward;
        }
        return pendingReward;
    }

    // Stake tokens in a Bounty pool to earn premium payments.
    function stake(
        uint256 _pid,
        address _user,
        uint256 _amount
    ) external nonReentrant activePool(_pid) returns (bool) {
        require(_amount > 0);
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        // bool _shouldHarvest = _user == msg.sender ? true : false; note delete this line?
        uint256 balanceBefore = pool.totalStaked + pool.projectDeposit;

        _updateUserReward(_pid, _user);
        if (user.amount == 0) pool.stakerList.push(_user);
        pool.token.safeTransferFrom(msg.sender, address(this), _amount);
        user.amount += _amount;
        pool.totalStaked += _amount;
        require(
            pool.poolCap > 0 && pool.totalStaked <= pool.poolCap,
            "Exceeded pool limit"
        );
        emit Staked(_user, _pid, _amount);

        uint256 balanceAfter = pool.totalStaked + pool.projectDeposit;
        emit BountyBalanceChanged(_pid, balanceBefore, balanceAfter);

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
        user.unstakeExecuted = false;

        emit WithdrawalOrUnstakeScheduled(_pid, _amount);
        return true;
    }

    // Withdraw LP tokens from MasterChef.
    function unstake(uint256 _pid, uint256 _amount)
        external
        nonReentrant
        returns (bool)
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        require(
            user.timelock < block.timestamp &&
                user.timeLimit > block.timestamp &&
                user.unstakeExecuted == false &&
                user.unstakeScheduledAmount >= _amount &&
                user.timelock != 0,
            "Timelock not set or not completed in time"
        );
        user.unstakeExecuted = true;

        uint256 balanceBefore = pool.totalStaked + pool.projectDeposit;

        _updateUserReward(_pid, msg.sender);
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.totalStaked = pool.totalStaked.sub(_amount);
            pool.token.safeTransfer(msg.sender, _amount);
        }
        if (user.amount == 0) {
            uint256 length = pool.stakerList.length;
            for (uint256 i; i < length; ) {
                if (pool.stakerList[i] == msg.sender) {
                    address lastAddress = pool.stakerList[length - 1];
                    pool.stakerList[i] = lastAddress;
                    pool.stakerList.pop();
                    break;
                }
                unchecked {
                    ++i;
                }
            }
        }
        emit Unstaked(msg.sender, _pid, _amount);

        uint256 balanceAfter = pool.totalStaked + pool.projectDeposit;
        emit BountyBalanceChanged(_pid, balanceBefore, balanceAfter);

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
    function _updateUserReward(uint256 _pid, address _user) internal {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        // updatePool(0);
        if (user.amount == 0) {
            user.lastRewardTime = block.timestamp;
            return;
        }
        uint256 pending = pendingToken(_pid, _user);

        if (pending > pool.premiumAvailable) {
            // bill premium calcualtes commission
            uint256 pendingMinusCommission;
            (, pending, pendingMinusCommission) = _billPremium(_pid, pending);
            if (pending > 0) {
                pool.token.safeTransfer(_user, pendingMinusCommission);
                pool.premiumBalance -= pending;
                pool.premiumAvailable -= pendingMinusCommission;
                user.lastRewardTime = block.timestamp;
            }
        } else {
            // if billPremium is not called we need to calcualte commission here
            if (pending > 0) {
                // user.unclaimed = 0;
                pool.premiumBalance -= pending;
                uint256 saloonPremiumCommission = (pending * premiumFee) / BPS;
                pending -= saloonPremiumCommission;
                pool.token.safeTransfer(_user, pending);
                pool.premiumAvailable -= pending;
                user.lastRewardTime = block.timestamp;
            }
        }
    }

    // Harvest one pool
    function claimPremium(uint256 _pid) external nonReentrant {
        _updateUserReward(_pid, msg.sender);
    }

    function billPremium(uint256 _pid) public onlyOwner returns (bool) {
        _billPremium(_pid, 0);
    }

    function _billPremium(uint256 _pid, uint256 _pending)
        internal
        returns (
            bool,
            uint256,
            uint256
        )
    {
        PoolInfo storage pool = poolInfo[_pid];

        // Billing is capped at requiredPremiumBalancePerPeriod so not even admins can bill more than needed
        // This prevents anyone calling this 1000 times and draining the project wallet

        uint256 billAmount = pool.requiredPremiumBalancePerPeriod -
            pool.premiumBalance +
            _pending; // NOTE bill premium now doesnt bill includiing saloon commission...

        IERC20(pool.token).safeTransferFrom(
            pool.projectWallet,
            address(this),
            billAmount
        );
        // pool.totalPending = 0;
        // Calculate saloon fee
        uint256 saloonPremiumCommission = (billAmount * premiumFee) / BPS;

        pool.premiumBalance += billAmount;

        // update saloon claimable fee
        saloonPremiumProfit[address(pool.token)] += saloonPremiumCommission;

        uint256 pendingMinusCommission = billAmount - saloonPremiumCommission;

        // available to make premium payment ->
        pool.premiumAvailable += pendingMinusCommission;

        emit PremiumBilled(_pid, billAmount);

        return (true, billAmount, pendingMinusCommission);
    }

    function payBounty(
        uint256 _pid,
        address _hunter,
        uint256 _amount
    ) public onlyOwner returns (bool) {
        PoolInfo storage pool = poolInfo[_pid];
        uint256 totalStaked = pool.totalStaked;
        uint256 poolTotal = totalStaked + pool.projectDeposit;

        // if stakers can cover payout
        if (_amount <= totalStaked) {
            if (_amount == totalStaked) {
                // set all staker balances to zero
                uint256 length = pool.stakerList.length;
                for (uint256 i; i < length; ) {
                    address _user = pool.stakerList[i];
                    UserInfo storage user = userInfo[_pid][_user];
                    _updateUserReward(_pid, _user);
                    user.amount = 0;
                    unchecked {
                        ++i;
                    }
                }
                pool.totalStaked = 0;
                delete pool.stakerList;
            } else {
                uint256 percentage = ((_amount * bountyFee) / totalStaked);
                uint256 length = pool.stakerList.length;
                for (uint256 i; i < length; ) {
                    address _user = pool.stakerList[i];
                    UserInfo storage user = userInfo[_pid][_user];
                    _updateUserReward(_pid, _user);
                    uint256 userPay = (user.amount * percentage) / bountyFee;
                    user.amount -= userPay;
                    pool.totalStaked -= userPay;
                    unchecked {
                        ++i;
                    }
                }
            }
            // if stakers alone cannot cover payout
        } else if (_amount > totalStaked && _amount < pool.projectDeposit) {
            // set all staker balances to zero
            uint256 length = pool.stakerList.length;
            for (uint256 i; i < length; ) {
                address _user = pool.stakerList[i];
                UserInfo storage user = userInfo[_pid][_user];
                _updateUserReward(_pid, _user);
                user.amount = 0;
                unchecked {
                    ++i;
                }
            }
            pool.totalStaked = 0;
            delete pool.stakerList;
            // calculate remaining amount for project to pay
            uint256 projectPayout = poolTotal - totalStaked;
            pool.projectDeposit -= projectPayout;
        } else if (_amount == poolTotal) {
            // set all staker balances to zero
            uint256 length = pool.stakerList.length;
            for (uint256 i; i < length; ) {
                address _user = pool.stakerList[i];
                UserInfo storage user = userInfo[_pid][_user];
                _updateUserReward(_pid, _user);
                user.amount = 0;
                unchecked {
                    ++i;
                }
            }
            pool.totalStaked = 0;
            delete pool.stakerList;
            pool.projectDeposit = 0;
        } else {
            revert("Amount too high");
        }

        // calculate saloon commission
        uint256 saloonCommission = (_amount * bountyFee) / BPS;
        // subtract commission from payout
        uint256 hunterPayout = _amount - saloonCommission;
        // update saloon Commission variable
        saloonBountyProfit[address(pool.token)] += saloonCommission;
        // transfer payout to hunter
        pool.token.safeTransfer(_hunter, hunterPayout);

        emit BountyPaid(block.timestamp, _hunter, address(pool.token), _amount);
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

    function collectAllSaloonProfits(address _saloonWallet)
        external
        onlyOwner
        returns (bool)
    {
        uint256 activeTokenLength = activeTokens.length;
        for (uint256 i; i < activeTokenLength; ++i) {
            address _token = activeTokens[i];
            uint256 amount = saloonBountyProfit[_token] +
                saloonPremiumProfit[_token];

            if (amount == 0) continue;

            saloonBountyProfit[_token] = 0;
            saloonPremiumProfit[_token] = 0;
            IERC20(_token).safeTransfer(_saloonWallet, amount);
        }
        return true;
    }

    // ============================
    // View Functions
    // ============================

    function viewSaloonProfitBalance(address _token)
        external
        view
        returns (
            uint256 totalProfit,
            uint256 bountyProfit,
            uint256 premiumProfit
        )
    {
        bountyProfit = saloonBountyProfit[_token];
        premiumProfit = saloonPremiumProfit[_token];
        totalProfit = premiumProfit + bountyProfit;
    }

    function viewBountyBalance(uint256 _pid) external view returns (uint256) {
        PoolInfo memory pool = poolInfo[_pid];
        return (pool.totalStaked + pool.projectDeposit);
        // note does totalStaked/project deposit take into account saloon fee?
    }

    function viewStake(uint256 _pid, address _user)
        external
        view
        returns (uint256)
    {
        UserInfo storage user = userInfo[_pid][_user];
        return user.amount;
    }

    function viewTotalStaked(uint256 _pid) public view returns (uint256) {
        PoolInfo memory pool = poolInfo[_pid];
        return pool.totalStaked;
    }

    function viewPoolCap(uint256 _pid) public view returns (uint256) {
        PoolInfo memory pool = poolInfo[_pid];
        return pool.poolCap;
    }

    function viewPoolAPY(uint256 _pid) public view returns (uint256) {
        PoolInfo memory pool = poolInfo[_pid];
        return pool.apy;
    }

    function viewUserInfo(uint256 _pid, address _user)
        external
        view
        returns (uint256 amount, uint256 unclaimed)
    {
        UserInfo storage user = userInfo[_pid][_user];
        amount = user.amount;
        unclaimed = user.unclaimed;
    }

    function viewPoolPremiumInfo(uint256 _pid)
        external
        view
        returns (
            uint256 requiredPremiumBalancePerPeriod,
            uint256 premiumBalance
        )
    {
        PoolInfo memory pool = poolInfo[_pid];

        requiredPremiumBalancePerPeriod = pool.requiredPremiumBalancePerPeriod;
        premiumBalance = pool.premiumBalance;
    }

    function viewPoolTimelockInfo(uint256 _pid)
        external
        view
        returns (
            uint256 timelock,
            uint256 timeLimit,
            uint256 withdrawalScheduledAmount
        )
    {
        PoolInfo memory pool = poolInfo[_pid];
        timelock = pool.poolTimelock.timelock;
        timeLimit = pool.poolTimelock.timeLimit;
        withdrawalScheduledAmount = pool.poolTimelock.withdrawalScheduledAmount;
    }

    function viewHackerPayout(uint256 _pid) public view returns (uint256) {
        PoolInfo memory pool = poolInfo[_pid];
        return ((pool.totalStaked + pool.projectDeposit) * bountyFee) / BPS;
    }

    function viewBountyInfo(uint256 _pid)
        external
        view
        returns (
            uint256 payout,
            uint256 apy,
            uint256 staked,
            uint256 poolCap
        )
    {
        payout = viewHackerPayout(_pid);
        staked = viewTotalStaked(_pid);
        apy = viewPoolAPY(_pid);
        poolCap = viewPoolCap(_pid);
    }
}
