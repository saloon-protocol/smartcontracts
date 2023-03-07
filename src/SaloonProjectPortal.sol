// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import "./lib/OwnableUpgradeable.sol";
import "./BountyTokenNFT.sol";
import "./interfaces/IStrategyFactory.sol";
import "./SaloonCommon.sol";

contract SaloonProjectPortal is
    SaloonCommon,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;

    // function initialize() public initializer {
    //     __Ownable_init();
    // }

    modifier onlyOwnerOrProject(uint256 _pid) {
        PoolInfo memory pool = poolInfo[_pid];
        require(
            msg.sender == pool.generalInfo.projectWallet ||
                msg.sender == _owner,
            "Not authorized"
        );
        _;
    }

    modifier activePool(uint256 _pid) {
        PoolInfo memory pool = poolInfo[_pid];
        if (!pool.isActive) revert("pool not active");
        _;
    }

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
        PoolInfo storage pool = poolInfo[_pid];
        require(
            !pool.isActive && pool.generalInfo.poolCap == 0,
            "Pool already initialized"
        );
        require(_apy > 0 && _apy <= 10000, "APY out of range");
        require(
            _poolCap >= 1000 * (10**pool.generalInfo.tokenDecimals) &&
                _poolCap <= 10000000 * (10**pool.generalInfo.tokenDecimals),
            "Pool cap out of range"
        );
        require(msg.sender == pool.generalInfo.projectWallet, "Not authorized");
        // requiredPremiumBalancePerPeriod includes Saloons commission
        uint256 requiredPremiumBalancePerPeriod = calcRequiredPremiumBalancePerPeriod(
                _poolCap,
                _apy
            );

        uint256 saloonCommission = (requiredPremiumBalancePerPeriod * //note could make this a pool.variable
            saloonFee) / BPS;

        uint256 balanceBefore = viewBountyBalance(_pid);

        IERC20(pool.generalInfo.token).safeTransferFrom(
            msg.sender,
            address(this),
            _deposit + requiredPremiumBalancePerPeriod
        );
        pool.depositInfo.projectDepositHeld += _deposit;
        pool.generalInfo.poolCap = _poolCap;
        pool.generalInfo.apy = _apy;
        pool.generalInfo.scalingMultiplier = SaloonLib._updateScalingMultiplier(
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
        PoolInfo storage pool = poolInfo[_pid];
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
    function scheduleProjectDepositWithdrawal(uint256 _pid, uint256 _amount)
        external
        returns (bool)
    {
        PoolInfo storage pool = poolInfo[_pid];
        require(
            (pool.depositInfo.projectDepositHeld +
                pool.depositInfo.projectDepositInStrategy) >= _amount,
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

    /// @notice Completes scheduled withdrawal
    /// @param _pid Bounty pool id
    /// @param _amount Amount to withdraw (must be equal to amount scheduled)
    function projectDepositWithdrawal(uint256 _pid, uint256 _amount)
        external
        nonReentrant
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

    function withdrawProjectYield(uint256 _pid)
        external
        nonReentrant
        returns (uint256 returnedAmount)
    {
        PoolInfo memory pool = poolInfo[_pid];
        require(msg.sender == pool.generalInfo.projectWallet, "Not authorized");

        bytes32 activeStrategyHash = activeStrategies[_pid];
        if (activeStrategyHash != bytes32(0)) {
            IStrategy activeStrategy = IStrategy(
                pidStrategies[_pid][activeStrategyHash]
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
    function windDownBounty(uint256 _pid)
        external
        onlyOwnerOrProject(_pid)
        returns (bool)
    {
        PoolInfo storage pool = poolInfo[_pid];
        require(pool.isActive, "Pool not active");
        pool.isActive = false;
        pool.freezeTime = block.timestamp;
        return true;
    }

    /// @notice Updates the pool's project wallet address
    /// @param _pid Bounty pool id
    /// @param _projectWallet The new project wallet
    function updateProjectWalletAddress(uint256 _pid, address _projectWallet)
        external
        onlyOwnerOrProject(_pid)
    {
        require(_projectWallet != address(0), "Invalid wallet address");
        poolInfo[_pid].generalInfo.projectWallet = _projectWallet;
    }

    //===========================================================================||
    //                               STRATEGY FUNCTIONS                          ||
    //===========================================================================||

    /// @notice Deploys a new strategy contract if the bounty does not have one already
    function _deployStrategyIfNeeded(uint256 _pid, string memory _strategyName)
        internal
        returns (address)
    {
        address deployedStrategy;
        bytes32 strategyHash = keccak256(abi.encode(_strategyName));
        address pidStrategy = pidStrategies[_pid][strategyHash];

        // Active strategy must be updated regardless of deployment success/failure

        if (pidStrategy == address(0)) {
            deployedStrategy = strategyFactory.deployStrategy(
                _strategyName,
                address(poolInfo[_pid].generalInfo.token)
            );
        } else {
            activeStrategies[_pid] = strategyHash;
            return pidStrategy;
        }

        if (deployedStrategy != address(0)) {
            pidStrategies[_pid][strategyHash] = deployedStrategy;
            strategyAddressToPid[deployedStrategy] = _pid;
            activeStrategies[_pid] = strategyHash;
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
        PoolInfo storage pool = poolInfo[_pid];

        bytes32 _strategyHash = keccak256(abi.encode(_strategyName));
        bytes32 activeStrategyHash = activeStrategies[_pid];
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
    function receiveStrategyYield(address _token, uint256 _amount)
        external
        override
    {
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
        uint256 pid = strategyAddressToPid[msg.sender];
        if (pid == 0) {
            saloonStrategyProfit[_token] += _amount;
        } else {
            (
                uint256 saloonAmount,
                uint256 referralAmount,
                address referrer
            ) = SaloonLib.calcReferralSplit(
                    _amount,
                    poolInfo[pid].referralInfo.endTime,
                    poolInfo[pid].referralInfo.referralFee,
                    poolInfo[pid].referralInfo.referrer
                );
            _increaseReferralBalance(referrer, _token, referralAmount);
            saloonStrategyProfit[_token] += saloonAmount;
        }
    }

    /// @notice Harvest pending yield from active strategy for single pid and reinvest
    /// @param _pid Pool id whose strategy should be compounded
    function compoundYieldForPid(uint256 _pid)
        public
        onlyOwnerOrProject(_pid)
        nonReentrant
    {
        bytes32 strategyHash = activeStrategies[_pid];
        address deployedStrategy = pidStrategies[_pid][strategyHash];
        if (deployedStrategy != address(0)) {
            uint256 depositAdded = IStrategy(deployedStrategy).compound();
            poolInfo[_pid].depositInfo.projectDepositInStrategy +=
                depositAdded -
                1; // Subtract 1 wei for immediate withdrawal precision issues
        }
    }

    // /// @notice Increases how much a referrer is entitled to withdraw
    // /// @param _referrer Referrer address
    // /// @param _token ERC20 Token address
    // /// @param _amount Amount referrer is entitled to
    // function _increaseReferralBalance(
    //     address _referrer,
    //     address _token,
    //     uint256 _amount
    // ) internal {
    //     if (_referrer != address(0)) {
    //         referralBalances[_referrer][_token] += _amount;
    //     }
    // }

    //===========================================================================||
    //                             VIEW & PURE FUNCTIONS                         ||
    //===========================================================================||

    // function viewBountyBalance(uint256 _pid) public view returns (uint256) {
    //     PoolInfo memory pool = poolInfo[_pid];
    //     return (pool.generalInfo.totalStaked +
    //         (pool.depositInfo.projectDepositHeld +
    //             pool.depositInfo.projectDepositInStrategy));
    // }

    // function calcRequiredPremiumBalancePerPeriod(uint256 _poolCap, uint256 _apy)
    //     public
    //     pure
    //     returns (uint256 requiredPremiumBalance)
    // {
    //     requiredPremiumBalance = (((_poolCap * _apy * PERIOD) / BPS) / YEAR);
    // }
}
