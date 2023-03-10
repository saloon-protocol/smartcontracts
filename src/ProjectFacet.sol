// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "./Base.sol";
import "./interfaces/IProjectFacet.sol";
import "./interfaces/IStrategyFactory.sol";
import "./lib/LibSaloon.sol";

contract ProjectFacet is Base, IProjectFacet {
    using SafeERC20 for IERC20;

    //===========================================================================||
    //                               PROJECT FUNCTIONS                           ||
    //===========================================================================||

    /// @notice Sets the average APY,Pool Cap and deposits project payout
    /// @dev Can only be called by the projectWallet
    /// @param _pid Bounty pool id
    /// @param _poolCap Max size of pool in token amount
    /// @param _apy Average APY that will be paid to stakers
    /// @param _deposit Amount to be deopsited as bounty payout
    /// @param _strategyName Name of the strategy to be used
    function setAPYandPoolCapAndDeposit(
        uint256 _pid,
        uint256 _poolCap,
        uint16 _apy,
        uint256 _deposit,
        string memory _strategyName
    ) external nonReentrant {
        LibSaloon.LibSaloonStorage storage ss = LibSaloon.getLibSaloonStorage();

        PoolInfo storage pool = s.poolInfo[_pid];
        require(
            !pool.isActive && pool.generalInfo.poolCap == 0,
            "Pool already initialized"
        );
        require(_apy > 0 && _apy <= 10000, "APY out of range");
        require(
            _poolCap >= 1000 * (10 ** pool.generalInfo.tokenDecimals) &&
                _poolCap <= 10000000 * (10 ** pool.generalInfo.tokenDecimals),
            "Pool cap out of range"
        );
        require(msg.sender == pool.generalInfo.projectWallet, "Not authorized");
        // requiredPremiumBalancePerPeriod includes Saloons commission
        uint256 requiredPremiumBalancePerPeriod = LibSaloon
            .calcRequiredPremiumBalancePerPeriod(_poolCap, _apy);

        uint256 saloonCommission = (requiredPremiumBalancePerPeriod * //note could make this a pool.variable
            ss.saloonFee) / ss.bps;

        uint256 balanceBefore = viewBountyBalance(_pid);

        IERC20(pool.generalInfo.token).safeTransferFrom(
            msg.sender,
            address(this),
            _deposit + requiredPremiumBalancePerPeriod
        );
        pool.depositInfo.projectDepositHeld += _deposit;
        pool.generalInfo.poolCap = _poolCap;
        pool.generalInfo.apy = _apy;
        pool.generalInfo.scalingMultiplier = LibSaloon._updateScalingMultiplier(
            _apy
        );
        pool.isActive = true;
        pool.premiumInfo.premiumBalance = requiredPremiumBalancePerPeriod;
        pool.premiumInfo.premiumAvailable =
            requiredPremiumBalancePerPeriod -
            saloonCommission;

        if (bytes(_strategyName).length > 0) {
            _handleStrategyDeposit(_pid, _strategyName, _deposit);
        }

        uint256 balanceAfter = viewBountyBalance(_pid);
        emit BountyBalanceChanged(_pid, balanceBefore, balanceAfter);
    }

    /// @notice Makes a deposit that will serve as bounty payout
    /// @dev Only callable by projectWallet
    /// @param _pid Bounty pool id
    /// @param _deposit Amount to be deposited
    /// @param _strategyName Name of the strategy where deposit will go to
    function makeProjectDeposit(
        uint256 _pid,
        uint256 _deposit,
        string memory _strategyName
    ) external nonReentrant {
        PoolInfo storage pool = s.poolInfo[_pid];
        require(msg.sender == pool.generalInfo.projectWallet, "Not authorized");

        uint256 balanceBefore = viewBountyBalance(_pid);
        IERC20(pool.generalInfo.token).safeTransferFrom(
            msg.sender,
            address(this),
            _deposit
        );
        pool.depositInfo.projectDepositHeld += _deposit;

        if (bytes(_strategyName).length > 0) {
            _handleStrategyDeposit(_pid, _strategyName, _deposit);
        }

        uint256 balanceAfter = viewBountyBalance(_pid);
        emit BountyBalanceChanged(_pid, balanceBefore, balanceAfter);
    }

    /// @notice Schedules withdrawal for a project deposit
    /// @dev withdrawal must be made within a certain time window
    /// @param _pid Bounty pool id
    /// @param _amount Amount to withdraw
    function scheduleProjectDepositWithdrawal(
        uint256 _pid,
        uint256 _amount
    ) external returns (bool) {
        LibSaloon.LibSaloonStorage storage ss = LibSaloon.getLibSaloonStorage();

        PoolInfo storage pool = s.poolInfo[_pid];
        require(
            (pool.depositInfo.projectDepositHeld +
                pool.depositInfo.projectDepositInStrategy) >= _amount,
            "Amount bigger than deposit"
        );
        require(msg.sender == pool.generalInfo.projectWallet, "Not authorized");
        pool.poolTimelock.timelock = block.timestamp + ss.period;
        pool.poolTimelock.timeLimit = block.timestamp + ss.period + 3 days;
        pool.poolTimelock.withdrawalScheduledAmount = _amount;
        pool.poolTimelock.withdrawalExecuted = false;

        emit WithdrawalOrUnstakeScheduled(_pid, _amount);
        return true;
    }

    /// @notice Completes scheduled withdrawal
    /// @param _pid Bounty pool id
    /// @param _amount Amount to withdraw (must be equal to amount scheduled)
    function projectDepositWithdrawal(
        uint256 _pid,
        uint256 _amount
    ) external nonReentrant returns (bool) {
        PoolInfo storage pool = s.poolInfo[_pid];
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

        if (pool.depositInfo.projectDepositHeld < _amount)
            _withdrawFromActiveStrategy(_pid);

        uint256 balanceBefore = viewBountyBalance(_pid);
        pool.depositInfo.projectDepositHeld -= _amount;
        IERC20(pool.generalInfo.token).safeTransfer(
            pool.generalInfo.projectWallet,
            _amount
        );
        uint256 balanceAfter = viewBountyBalance(_pid);

        emit BountyBalanceChanged(_pid, balanceBefore, balanceAfter);
        return true;
    }

    function withdrawProjectYield(
        uint256 _pid
    ) external nonReentrant returns (uint256 returnedAmount) {
        PoolInfo memory pool = s.poolInfo[_pid];
        require(msg.sender == pool.generalInfo.projectWallet, "Not authorized");

        bytes32 activeStrategyHash = s.activeStrategies[_pid];
        if (activeStrategyHash != bytes32(0)) {
            IStrategy activeStrategy = IStrategy(
                s.pidStrategies[_pid][activeStrategyHash]
            );
            returnedAmount = activeStrategy.withdrawYield();
            IERC20(pool.generalInfo.token).safeTransfer(
                pool.generalInfo.projectWallet,
                returnedAmount
            );
        }
    }

    /// @notice Deactivates pool
    /// @param _pid Bounty pool id
    function windDownBounty(
        uint256 _pid
    ) external onlyOwnerOrProject(_pid) returns (bool) {
        PoolInfo storage pool = s.poolInfo[_pid];
        require(pool.isActive, "Pool not active");
        pool.isActive = false;
        pool.freezeTime = block.timestamp;
        return true;
    }

    /// @notice Updates the pool's project wallet address
    /// @param _pid Bounty pool id
    /// @param _projectWallet The new project wallet
    function updateProjectWalletAddress(
        uint256 _pid,
        address _projectWallet
    ) external onlyOwnerOrProject(_pid) {
        require(_projectWallet != address(0), "Invalid wallet address");
        s.poolInfo[_pid].generalInfo.projectWallet = _projectWallet;
    }

    //===========================================================================||
    //                               STRATEGY FUNCTIONS                          ||
    //===========================================================================||

    /// @notice Withdraws current deposit held in active strategy
    /// @param _pid Bounty pool id
    function _withdrawFromActiveStrategy(
        uint256 _pid
    ) internal returns (uint256) {
        PoolInfo storage pool = s.poolInfo[_pid];

        uint256 fundsWithdrawn;
        bytes32 activeStrategyHash = s.activeStrategies[_pid];

        // Reset active strategy upon every withdraw. All withdrawals are in full.
        s.activeStrategies[_pid] = bytes32(0);

        if (activeStrategyHash != bytes32(0)) {
            IStrategy activeStrategy = IStrategy(
                s.pidStrategies[_pid][activeStrategyHash]
            );
            uint256 activeStrategyLPDepositBalance = activeStrategy
                .lpDepositBalance();
            fundsWithdrawn = activeStrategy.withdrawFromStrategy(
                activeStrategyLPDepositBalance
            );
            pool.depositInfo.projectDepositInStrategy = 0;
            pool.depositInfo.projectDepositHeld += fundsWithdrawn;
        }

        return fundsWithdrawn;
    }

    /// @notice Deploys a new strategy contract if the bounty does not have one already
    function _deployStrategyIfNeeded(
        uint256 _pid,
        string memory _strategyName
    ) internal returns (address) {
        address deployedStrategy;
        bytes32 strategyHash = keccak256(abi.encode(_strategyName));
        address pidStrategy = s.pidStrategies[_pid][strategyHash];

        // Active strategy must be updated regardless of deployment success/failure

        if (pidStrategy == address(0)) {
            deployedStrategy = s.strategyFactory.deployStrategy(
                _strategyName,
                address(s.poolInfo[_pid].generalInfo.token)
            );
        } else {
            s.activeStrategies[_pid] = strategyHash;
            return pidStrategy;
        }

        if (deployedStrategy != address(0)) {
            s.pidStrategies[_pid][strategyHash] = deployedStrategy;
            s.strategyAddressToPid[deployedStrategy] = _pid;
            s.activeStrategies[_pid] = strategyHash;
        }

        return deployedStrategy;
    }

    /// @notice Function to handle deploying new strategy, switching strategies, depositing to strategy
    /// @param _pid Bounty pool id
    /// @param _strategyName Name of the strategy
    /// @param _newDeposit New deposit amount
    function _handleStrategyDeposit(
        uint256 _pid,
        string memory _strategyName,
        uint256 _newDeposit
    ) internal returns (uint256) {
        PoolInfo storage pool = s.poolInfo[_pid];

        bytes32 _strategyHash = keccak256(abi.encode(_strategyName));
        bytes32 activeStrategyHash = s.activeStrategies[_pid];
        if (activeStrategyHash != _strategyHash) {
            uint256 fundsWithdrawn = _withdrawFromActiveStrategy(_pid);
            address deployedStrategy = _deployStrategyIfNeeded(
                _pid,
                _strategyName
            );
            if (deployedStrategy != address(0)) {
                IStrategy strategy = IStrategy(deployedStrategy);
                uint256 projectDepositHeld = pool
                    .depositInfo
                    .projectDepositHeld;
                pool.depositInfo.projectDepositHeld = 0;
                // Subtract 1 wei due to precision loss when depositing into strategy if redeemed immediately
                //      TODO NOTE FIXME: this will underflow when calling setAPYandPoolCapAndDeposit when deposit = 0
                //          We should have a minimum deposit. lets say $100
                pool.depositInfo.projectDepositInStrategy =
                    projectDepositHeld -
                    1;
                IERC20(pool.generalInfo.token).safeTransfer(
                    deployedStrategy,
                    projectDepositHeld
                );
                strategy.depositToStrategy();
            }
        }
    }

    /// @notice Callback function from strategies upon converting yield to underlying
    /// @dev Anyone can call this but will result in lost funds for non-strategies. TODO ADD MODIFIER TO THIS?
    /// - Tokens are transferred from msg.sender to this contract and saloonStrategyProfit and/or
    ///   referralBalances are incremented.
    /// @param _token Token being received
    /// @param _amount Amount being received
    function receiveStrategyYield(
        address _token,
        uint256 _amount
    ) external override {
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
        uint256 pid = s.strategyAddressToPid[msg.sender];
        if (pid == 0) {
            s.saloonStrategyProfit[_token] += _amount;
        } else {
            (
                uint256 saloonAmount,
                uint256 referralAmount,
                address referrer
            ) = LibSaloon.calcReferralSplit(
                    _amount,
                    s.poolInfo[pid].referralInfo.endTime,
                    s.poolInfo[pid].referralInfo.referralFee,
                    s.poolInfo[pid].referralInfo.referrer
                );
            _increaseReferralBalance(referrer, _token, referralAmount);
            s.saloonStrategyProfit[_token] += saloonAmount;
        }
    }

    /// @notice Harvest pending yield from active strategy for single pid and reinvest
    /// @param _pid Pool id whose strategy should be compounded
    function compoundYieldForPid(
        uint256 _pid
    ) public onlyOwnerOrProject(_pid) nonReentrant {
        bytes32 strategyHash = s.activeStrategies[_pid];
        address deployedStrategy = s.pidStrategies[_pid][strategyHash];
        if (deployedStrategy != address(0)) {
            uint256 depositAdded = IStrategy(deployedStrategy).compound();
            s.poolInfo[_pid].depositInfo.projectDepositInStrategy +=
                depositAdded -
                1; // Subtract 1 wei for immediate withdrawal precision issues
        }
    }

    /// @notice Increases how much a referrer is entitled to withdraw
    /// @param _referrer Referrer address
    /// @param _token ERC20 Token address
    /// @param _amount Amount referrer is entitled to
    function _increaseReferralBalance(
        address _referrer,
        address _token,
        uint256 _amount
    ) internal {
        if (_referrer != address(0)) {
            s.referralBalances[_referrer][_token] += _amount;
        }
    }

    // NOTE MOVE VIEW BOUNTY BALANCE to somewhere else???
    //===========================================================================||
    //                             VIEW & PURE FUNCTIONS                         ||
    //===========================================================================||

    function viewBountyBalance(uint256 _pid) public view returns (uint256) {
        PoolInfo memory pool = s.poolInfo[_pid];
        return (pool.generalInfo.totalStaked +
            (pool.depositInfo.projectDepositHeld +
                pool.depositInfo.projectDepositInStrategy));
    }
}
