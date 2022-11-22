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
- Bounty payouts needing to decrement all stakers
- Billing premium when necessary.
- add token whitelist and whitelist check in `addNewBounty`
- Make it upgradeable
*/

///NOTE `tokensPerSecond` needs to be substituted by something `tokenReward`

interface IMigratorChef {
    // Perform LP token migration from legacy PancakeSwap to CakeSwap.
    // Take the current LP token address and return the new LP token address.
    // Migrator should have full access to the caller's LP token.
    // Return the new LP token address.
    //
    // XXX Migrator must have allowance access to PancakeSwap LP tokens.
    // CakeSwap must mint EXACTLY the same amount of CakeSwap LP tokens or
    // else something bad will happen. Traditional PancakeSwap does not
    // do that so be careful!
    function migrate(IERC20 token) external returns (IERC20);
}

contract MasterChef is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 lastTokenPerShare; // Reward debt. See explanation below.
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
        address projectWallet;
        uint256 allocPoint; // How many allocation points assigned to this pool. Tokens to distribute per block.
        uint256 projectDeposit;
        uint256 apy;
        uint256 poolLimit;
        uint256 totalStaked;
        uint256 lastRewardTime; // Last block number that Tokens distribution occurs.
        uint256 accTokenPerShare; // Accumulated Tokens per share, times 1e18. See below.
        bool initialized;
    }

    // Dev address.
    address public devaddr;

    // Bonus muliplier for early cake makers.
    uint256 public denominator = 100 * (1e18);

    // The migrator contract. It has a lot of power. Can only be set through governance (owner).
    IMigratorChef public migrator;

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
    function addNewBountyPool(
        IERC20 _token,
        address _projectWallet,
        bool _withUpdate //note should be this defaulted to true or false?
    ) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools(); //note is this necessary?
        }
        uint256 lastRewardTime = block.timestamp > startTime
            ? block.timestamp
            : startTime;

        // totalAllocPoint = totalAllocPoint.add(_allocPoint); // note this doesnt seem necessary
        poolInfo.push(
            PoolInfo({
                token: _token,
                projectWallet: _projectWallet,
                lastRewardTime: lastRewardTime
            })
        );
    }

    function setDepositAPYandPoolLimit(
        uint256 _pid,
        uint256 _deposit,
        uint256 _apy
    ) external {
        PoolInfo storage pool = poolInfo[_pid];

        require(
            msg.sender == pool.projectWallet && pool.initialized == false,
            "Not authorized"
        );
        // transferfrom token
        pool.projectDeposit = _deposit;
        pool.apy = _apy;
        pool.initialized = true;
    }

    // // Update the given pool's CAKE allocation point. Can only be called by the owner.
    // // NOTE how can this be used to update APY, deposit?
    // function set(
    //     uint256 _pid,
    //     uint256 _allocPoint,
    //     bool _withUpdate
    // ) public onlyOwner {
    //     if (_withUpdate) {
    //         massUpdatePools();
    //     }
    //     uint256 prevAllocPoint = poolInfo[_pid].allocPoint;
    //     poolInfo[_pid].allocPoint = _allocPoint;
    //     if (prevAllocPoint != _allocPoint) {
    //         totalAllocPoint = totalAllocPoint.sub(prevAllocPoint).add(
    //             _allocPoint
    //         );
    //         updateStakingPool();
    //     }
    // }

    // // Set the migrator contract. Can only be called by the owner.
    // function setMigrator(IMigratorChef _migrator) public onlyOwner {
    //     migrator = _migrator;
    // }

    // // Migrate lp token to another lp contract. Can be called by anyone. We trust that migrator contract is good.
    // //TODO change this function to migrate funds and staker data to another pool?
    // function migrate(uint256 _pid) public {
    //     require(address(migrator) != address(0), "migrate: no migrator");
    //     PoolInfo storage pool = poolInfo[_pid];
    //     IBEP20 lpToken = pool.lpToken;
    //     uint256 bal = lpToken.balanceOf(address(this));
    //     lpToken.safeApprove(address(migrator), bal);
    //     IBEP20 newLpToken = migrator.migrate(lpToken);
    //     require(bal == newLpToken.balanceOf(address(this)), "migrate: bad");
    //     pool.lpToken = newLpToken;
    // }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to)
        public
        view
        returns (uint256)
    {
        return _to.sub(_from);
    }

    // make into function to view Pending yield to claim
    function pendingToken(uint256 _pid, address _user)
        external
        view
        returns (uint256)
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accTokenPerShare = pool.accTokenPerShare;
        uint256 totalStaked = pool.totalStaked;
        if (block.timestamp > pool.lastRewardTime && totalStaked != 0) {
            uint256 multiplier = getMultiplier(
                pool.lastRewardTime,
                block.timestamp
            );

            // note/todo should we calculate tokensPerSecond based on user.amount or totalStaked and APY?
            uint256 tokensPerSecond = ((user.amount * pool.apy) / denominator) /
                31536000; //todo fix decimals so this doesnt under/overflow

            uint256 tokenReward = multiplier.mul(tokensPerSecond);
            accTokenPerShare = accTokenPerShare.add(
                tokenReward.mul(1e18).div(totalStaked)
            );
        }
        return
            user
                .amount
                .mul(accTokenPerShare.sub(user.lastTokenPerShare))
                .div(1e18)
                .add(user.unclaimed);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.timestamp <= pool.lastRewardTime) {
            return;
        }
        if (pool.totalStaked == 0) {
            pool.lastRewardTime = block.timestamp;
            return;
        }
        // multiplier =  block.timestamp - pool.lastRewardTime
        uint256 multiplier = getMultiplier(
            pool.lastRewardTime,
            block.timestamp
        );

        // // note/todo should we calculate tokensPerSecond based on user.amount and APY?
        // uint256 tokensPerSecond = ((totalStaked? * pool.apy) / denominator) /
        //     31536000; //todo fix decimals so this doesnt under/overflow

        uint256 tokenReward = multiplier.mul(tokensPerSecond);

        pool.accTokenPerShare = pool.accTokenPerShare.add(
            tokenReward.mul(1e18).div(pool.totalStaked) //note does this last variable make sense?
        );

        pool.lastRewardTime = block.timestamp;
    }

    // Stake tokens in a Bounty pool to earn premium payments.
    function stake(uint256 _pid, uint256 _amount) public {
        require(_pid != 0, "deposit Token by staking");

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        _updateUserReward(_pid, true);

        if (_amount > 0) {
            pool.token.safeTransferFrom(msg.sender, address(this), _amount);
            user.amount = user.amount.add(_amount);
            pool.totalStaked = pool.totalStaked.add(_amount);
        }
        require(
            pool.poolLimit > 0 && pool.totalStaked <= pool.poolLimit,
            "Exceeded pool limit"
        );

        // emit Deposit(msg.sender, _pid, _amount); //todo change to Staking event
    }

    // Withdraw LP tokens from MasterChef.
    function unstake(uint256 _pid, uint256 _amount) public {
        require(_pid != 0, "withdraw Token by unstaking");
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");

        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accTokenPerShare).div(1e18).sub(
            user.lastTokenPerShare
        );

        uint256 amount = _amount + pending;
        if (amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.token.safeTransfer(address(msg.sender), amount);
        }
        user.lastTokenPerShare = user.amount.mul(pool.accTokenPerShare).div(
            1e18
        );
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        pool.token.safeTransfer(address(msg.sender), user.amount);
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        user.amount = 0;
        user.lastTokenPerShare = 0;
    }

    // Update the rewards of caller, and harvests if needed
    function _updateUserReward(uint256 _pid, bool _shouldHarvest) internal {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount == 0) {
            user.lastTokenPerShare = pool.accTokenPerShare;
        }
        uint256 pending = user
            .amount
            .mul(pool.accTokenPerShare.sub(user.lastTokenPerShare))
            .div(1e18)
            .add(user.unclaimed);
        user.unclaimed = _shouldHarvest ? 0 : pending;
        if (pending > 0) {
            //todo transfer pending premium to user account
            //todo emit Claim event
        }
        user.lastTokenPerShare = pool.accTokenPerShare;
    }

    // Harvest one pool
    function claim(uint256 _pid) external nonReentrant {
        _updateUserReward(_pid, true);
    }

    // Safe cake transfer function, just in case if rounding error causes pool to not have enough CAKEs.
    // function safeCakeTransfer(address _to, uint256 _amount) internal {
    //     syrup.safeCakeTransfer(_to, _amount);
    // }

    // Update dev address by the previous dev.
    function dev(address _devaddr) public {
        require(msg.sender == devaddr, "dev: wut?");
        devaddr = _devaddr;
    }
}
