// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "openzeppelin-contracts/contracts/utils/math/SafeMath.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import "./lib/OwnableUpgradeable.sol";
import "./BountyToken.sol";

/* Implement:
- TODO Integrate keeping track of owed rewards when transferring BountyTokens between users
- TODO Integrate minting and burning of tokens in staking and unstaking
- TEST event emissions
*/

contract Saloon is
    OwnableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuard,
    BountyToken
{
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    uint256 constant YEAR = 365 days;
    uint256 constant PERIOD = 1 weeks;
    uint256 constant bountyFee = 1000; // 10%
    uint256 constant premiumFee = 1000; // 10%

    mapping(address => uint256) public saloonBountyProfit;
    mapping(address => uint256) public saloonPremiumProfit;
    // Info of each user.
    //NOTE This might need to be changed because stakerBalance has been introduced in BountyToken
    struct UserInfo {
        uint256 amount; // How many tokens the user has staked.
        uint256 unclaimed; // Unclaimed premium.
        uint256 lastRewardTime; // Reward debt. See explanation below.
        uint256 timelock;
        uint256 timeLimit;
        uint256 unstakeScheduledAmount;
    }

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
        (, bytes memory _decimals) = _token.staticcall(
            abi.encodeWithSignature("decimals()")
        );
        uint8 decimals = abi.decode(_decimals, (uint8));

        PoolInfo memory newBounty;
        newBounty.generalInfo.token = IERC20(_token);
        newBounty.generalInfo.tokenDecimals = decimals;
        newBounty.generalInfo.projectWallet = _projectWallet;
        newBounty.generalInfo.projectName = _projectName;
        newBounty.generalInfo.projectDeposit = 0;
        newBounty.generalInfo.apy = 0;
        newBounty.generalInfo.poolCap = 0;
        newBounty.generalInfo.multiplier = 0;
        newBounty.generalInfo.totalStaked = 0;
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
        require(
            msg.sender == pool.generalInfo.projectWallet ||
                msg.sender == _owner,
            "Not authorized"
        );
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
        require(
            !pool.isActive && pool.generalInfo.poolCap == 0,
            "Pool already initialized"
        );
        require(_apy > 0 && _apy <= 10000, "APY out of range");
        require(
            _poolCap >= 100 * (10**pool.generalInfo.tokenDecimals) &&
                _poolCap <= 10000000 * (10**pool.generalInfo.tokenDecimals),
            "Pool cap out of range"
        );
        require(msg.sender == pool.generalInfo.projectWallet, "Not authorized");
        // requiredPremiumBalancePerPeriod includes Saloons commission
        uint256 requiredPremiumBalancePerPeriod = (((_poolCap * _apy * PERIOD) /
            BPS) / YEAR);

        uint256 saloonCommission = (requiredPremiumBalancePerPeriod * //note could make this a pool.variable
            premiumFee) / BPS;

        IERC20(pool.generalInfo.token).safeTransferFrom(
            msg.sender,
            address(this),
            _deposit + requiredPremiumBalancePerPeriod
        );
        pool.generalInfo.projectDeposit += _deposit;
        pool.generalInfo.poolCap = _poolCap;
        pool.generalInfo.apy = _apy;
        pool.isActive = true;
        pool.premiumInfo.premiumBalance = requiredPremiumBalancePerPeriod;
        pool
            .premiumInfo
            .requiredPremiumBalancePerPeriod = requiredPremiumBalancePerPeriod;
        pool.premiumInfo.premiumAvailable =
            requiredPremiumBalancePerPeriod -
            saloonCommission;
    }

    function makeProjectDeposit(uint256 _pid, uint256 _deposit) external {
        PoolInfo storage pool = poolInfo[_pid];
        require(msg.sender == pool.generalInfo.projectWallet, "Not authorized");

        uint256 balanceBefore = pool.generalInfo.totalStaked +
            pool.generalInfo.projectDeposit;
        IERC20(pool.generalInfo.token).safeTransferFrom(
            msg.sender,
            address(this),
            _deposit
        );
        pool.generalInfo.projectDeposit += _deposit;
        uint256 balanceAfter = pool.generalInfo.totalStaked +
            pool.generalInfo.projectDeposit;

        emit BountyBalanceChanged(_pid, balanceBefore, balanceAfter);
    }

    function scheduleProjectDepositWithdrawal(uint256 _pid, uint256 _amount)
        external
        returns (bool)
    {
        PoolInfo storage pool = poolInfo[_pid];
        require(
            pool.generalInfo.projectDeposit >= _amount,
            "Amount bigger than deposit"
        );
        require(msg.sender == pool.generalInfo.projectWallet, "Not authorized");
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
        require(msg.sender == pool.generalInfo.projectWallet, "Not authorized");
        require(
            pool.poolTimelock.timelock < block.timestamp &&
                pool.poolTimelock.timeLimit > block.timestamp &&
                pool.poolTimelock.withdrawalExecuted == false &&
                pool.poolTimelock.withdrawalScheduledAmount >= _amount &&
                pool.poolTimelock.timelock != 0,
            "Timelock not set or not completed in time"
        );
        pool.poolTimelock.withdrawalExecuted = true;

        uint256 balanceBefore = pool.generalInfo.totalStaked +
            pool.generalInfo.projectDeposit;
        pool.generalInfo.projectDeposit -= _amount;
        IERC20(pool.generalInfo.token).safeTransfer(
            pool.generalInfo.projectWallet,
            _amount
        );
        uint256 balanceAfter = pool.generalInfo.totalStaked +
            pool.generalInfo.projectDeposit;

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
        returns (
            uint256 totalPending,
            uint256 actualPending,
            uint256 newPending
        )
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];

        uint256 totalStaked = pool.generalInfo.totalStaked;
        uint256 endTime = pool.freezeTime != 0
            ? pool.freezeTime
            : block.timestamp;

        // multiplier = number of seconds
        uint256 multiplier = getMultiplier(user.lastRewardTime, endTime);
        newPending =
            (((user.amount * pool.generalInfo.apy) / BPS) * multiplier) /
            YEAR;
        totalPending = newPending + user.unclaimed;
        // actualPending subtracts Saloon premium fee
        actualPending = (totalPending * (BPS - premiumFee)) / BPS;

        // note saloonPremiumProfit variable is updated in billPremium()

        return (totalPending, actualPending, newPending);
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
        uint256 balanceBefore = pool.generalInfo.totalStaked +
            pool.generalInfo.projectDeposit;

        _updateUserReward(_pid, _user, true);
        if (user.amount == 0) pool.stakerList.push(_user);
        pool.generalInfo.token.safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );
        user.amount += _amount;
        pool.generalInfo.totalStaked += _amount;
        require(
            pool.generalInfo.poolCap > 0 &&
                pool.generalInfo.totalStaked <= pool.generalInfo.poolCap,
            "Exceeded pool limit"
        );
        emit Staked(_user, _pid, _amount);

        uint256 balanceAfter = pool.generalInfo.totalStaked +
            pool.generalInfo.projectDeposit;
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

        emit WithdrawalOrUnstakeScheduled(_pid, _amount);
        return true;
    }

    // Withdraw LP tokens from MasterChef.
    function unstake(
        uint256 _pid,
        uint256 _amount,
        bool _shouldHarvest
    ) external nonReentrant returns (bool) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        require(
            user.timelock < block.timestamp &&
                user.timeLimit > block.timestamp &&
                user.unstakeScheduledAmount >= _amount &&
                user.timelock != 0,
            "Timelock not set or not completed in time"
        );
        user.timelock = 0;

        uint256 balanceBefore = pool.generalInfo.totalStaked +
            pool.generalInfo.projectDeposit;

        _updateUserReward(_pid, msg.sender, _shouldHarvest);
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.generalInfo.totalStaked = pool.generalInfo.totalStaked.sub(
                _amount
            );
            pool.generalInfo.token.safeTransfer(msg.sender, _amount);
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

        uint256 balanceAfter = pool.generalInfo.totalStaked +
            pool.generalInfo.projectDeposit;
        emit BountyBalanceChanged(_pid, balanceBefore, balanceAfter);

        return true;
    }

    function _updateUserReward(
        uint256 _pid,
        address _user,
        bool _shouldHarvest
    ) internal {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        // updatePool(0);
        if (user.amount == 0 && user.unclaimed == 0) {
            user.lastRewardTime = block.timestamp;
            return;
        }
        (
            uint256 totalPending,
            uint256 actualPending,
            uint256 newPending
        ) = pendingToken(_pid, _user);
        if (!_shouldHarvest) {
            user.unclaimed += newPending;
            user.lastRewardTime = pool.freezeTime != 0
                ? pool.freezeTime
                : block.timestamp;
            return;
        }

        if (totalPending > pool.premiumInfo.premiumBalance) {
            // bill premium calculates commission
            _billPremium(_pid, totalPending);
        }
        // if billPremium is not called we need to calcualte commission here
        if (totalPending > 0) {
            user.unclaimed = 0;
            user.lastRewardTime = pool.freezeTime != 0
                ? pool.freezeTime
                : block.timestamp;
            pool.premiumInfo.premiumBalance -= totalPending;
            pool.premiumInfo.premiumAvailable -= actualPending;
            pool.generalInfo.token.safeTransfer(_user, actualPending);
        }
    }

    // Harvest one pool
    function claimPremium(uint256 _pid) external nonReentrant {
        _updateUserReward(_pid, msg.sender, true);
    }

    function billPremium(uint256 _pid) public onlyOwner returns (bool) {
        _billPremium(_pid, 0);
    }

    function _billPremium(uint256 _pid, uint256 _pending) internal {
        PoolInfo storage pool = poolInfo[_pid];

        // Billing is capped at requiredPremiumBalancePerPeriod so not even admins can bill more than needed
        // This prevents anyone calling this 1000 times and draining the project wallet

        uint256 billAmount = pool.premiumInfo.requiredPremiumBalancePerPeriod -
            pool.premiumInfo.premiumBalance +
            _pending; // NOTE bill premium now doesnt bill includiing saloon commission...

        IERC20(pool.generalInfo.token).safeTransferFrom(
            pool.generalInfo.projectWallet,
            address(this),
            billAmount
        );

        // Calculate saloon fee
        uint256 saloonPremiumCommission = (billAmount * premiumFee) / BPS;
        pool.premiumInfo.premiumBalance += billAmount;
        // update saloon claimable fee
        saloonPremiumProfit[
            address(pool.generalInfo.token)
        ] += saloonPremiumCommission;

        uint256 billAmountMinusCommission = billAmount -
            saloonPremiumCommission;
        // available to make premium payment ->
        pool.premiumInfo.premiumAvailable += billAmountMinusCommission;

        emit PremiumBilled(_pid, billAmount);
    }

    function payBounty(
        uint256 _pid,
        address _hunter,
        uint256 _amount
    ) public onlyOwner returns (bool) {
        PoolInfo storage pool = poolInfo[_pid];
        uint256 totalStaked = pool.generalInfo.totalStaked;
        uint256 poolTotal = totalStaked + pool.generalInfo.projectDeposit;
        uint256 balanceBefore = poolTotal;

        // if stakers can cover payout
        if (_amount <= totalStaked) {
            if (_amount == totalStaked) {
                // set all staker balances to zero
                uint256 length = pool.stakerList.length;
                for (uint256 i; i < length; ) {
                    address _user = pool.stakerList[i];
                    UserInfo storage user = userInfo[_pid][_user];
                    _updateUserReward(_pid, _user, false);
                    user.amount = 0;
                    unchecked {
                        ++i;
                    }
                }
                pool.generalInfo.totalStaked = 0;
                delete pool.stakerList;
            } else {
                uint256 percentage = ((_amount * PRECISION) / totalStaked);
                uint256 length = pool.stakerList.length;
                for (uint256 i; i < length; ) {
                    address _user = pool.stakerList[i];
                    UserInfo storage user = userInfo[_pid][_user];
                    _updateUserReward(_pid, _user, false);
                    uint256 userPay = (user.amount * percentage) / PRECISION;
                    user.amount -= userPay;
                    pool.generalInfo.totalStaked -= userPay;
                    unchecked {
                        ++i;
                    }
                }
            }
            // if stakers alone cannot cover payout
        } else if (_amount > totalStaked && _amount < poolTotal) {
            // set all staker balances to zero
            uint256 length = pool.stakerList.length;
            for (uint256 i; i < length; ) {
                address _user = pool.stakerList[i];
                UserInfo storage user = userInfo[_pid][_user];
                _updateUserReward(_pid, _user, false);
                user.amount = 0;
                unchecked {
                    ++i;
                }
            }
            pool.generalInfo.totalStaked = 0;
            delete pool.stakerList;
            // calculate remaining amount for project to pay
            uint256 projectPayout = poolTotal - totalStaked;
            pool.generalInfo.projectDeposit -= projectPayout;
        } else if (_amount == poolTotal) {
            // set all staker balances to zero
            uint256 length = pool.stakerList.length;
            for (uint256 i; i < length; ) {
                address _user = pool.stakerList[i];
                UserInfo storage user = userInfo[_pid][_user];
                _updateUserReward(_pid, _user, false);
                user.amount = 0;
                unchecked {
                    ++i;
                }
            }
            pool.generalInfo.totalStaked = 0;
            delete pool.stakerList;
            pool.generalInfo.projectDeposit = 0;
        } else {
            revert("Amount too high");
        }

        // calculate saloon commission
        uint256 saloonCommission = (_amount * bountyFee) / BPS;
        // subtract commission from payout
        uint256 hunterPayout = _amount - saloonCommission;
        // update saloon Commission variable
        saloonBountyProfit[address(pool.generalInfo.token)] += saloonCommission;
        // transfer payout to hunter
        pool.generalInfo.token.safeTransfer(_hunter, hunterPayout);
        uint256 balanceAfter = pool.generalInfo.totalStaked +
            pool.generalInfo.projectDeposit;

        emit BountyPaid(
            block.timestamp,
            _hunter,
            address(pool.generalInfo.token),
            _amount
        );
        emit BountyBalanceChanged(_pid, balanceBefore, balanceAfter);
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
        return (pool.generalInfo.totalStaked + pool.generalInfo.projectDeposit);
        // note does totalStaked/project deposit take into account saloon fee?
    }

    function viewTotalStaked(uint256 _pid) public view returns (uint256) {
        PoolInfo memory pool = poolInfo[_pid];
        return pool.generalInfo.totalStaked;
    }

    function viewPoolCap(uint256 _pid) public view returns (uint256) {
        PoolInfo memory pool = poolInfo[_pid];
        return pool.generalInfo.poolCap;
    }

    function viewPoolAPY(uint256 _pid) public view returns (uint256) {
        PoolInfo memory pool = poolInfo[_pid];
        return pool.generalInfo.apy;
    }

    function viewUserInfo(uint256 _pid, address _user)
        external
        view
        returns (
            uint256 amount,
            uint256 actualPending,
            uint256 unstakeScheduledAmount,
            uint256 timelock
        )
    {
        UserInfo storage user = userInfo[_pid][_user];
        amount = user.amount;
        (, actualPending, ) = pendingToken(_pid, _user);
        unstakeScheduledAmount = user.unstakeScheduledAmount;
        timelock = user.timelock;
    }

    function viewUserUnclaimed(uint256 _pid, address _user)
        external
        view
        returns (uint256 unclaimed)
    {
        UserInfo storage user = userInfo[_pid][_user];
        unclaimed = user.unclaimed;
    }

    function viewPoolPremiumInfo(uint256 _pid)
        external
        view
        returns (
            uint256 requiredPremiumBalancePerPeriod,
            uint256 premiumBalance,
            uint256 premiumAvailable
        )
    {
        PoolInfo memory pool = poolInfo[_pid];

        requiredPremiumBalancePerPeriod = pool
            .premiumInfo
            .requiredPremiumBalancePerPeriod;
        premiumBalance = pool.premiumInfo.premiumBalance;
        premiumAvailable = pool.premiumInfo.premiumAvailable;
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
        return
            ((pool.generalInfo.totalStaked + pool.generalInfo.projectDeposit) *
                (BPS - bountyFee)) / BPS;
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
