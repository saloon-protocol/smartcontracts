// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";

import "openzeppelin-contracts-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import "./lib/OwnableUpgradeable.sol";
import "./BountyTokenNFT.sol";
import "./interfaces/IStrategyFactory.sol";
import "./SaloonStorage.sol";

contract SaloonCommon is SaloonStorage {
    using SafeERC20 for IERC20;

    // NOTE billpremium now doesnt bill includiing saloon commission...
    /// @notice Bills premium from project wallet
    /// @dev Billing is capped at requiredPremiumBalancePerPeriod so not even admins can bill more than needed
    /// @dev This prevents anyone calling this multiple times and draining the project wallet
    /// @param _pid Bounty pool id of what pool is being billed
    /// @param _pending The extra amount of pending that must be billed to bring bounty balance up to full
    function _billPremium(uint256 _pid, uint256 _pending) internal {
        PoolInfo storage pool = poolInfo[_pid];
        // FIXME billAmount = weeklyPremium - (currentBalance + pendingPremium) | pendingPremium = unclaimed + accrued
        uint256 billAmount = calcRequiredPremiumBalancePerPeriod(
            pool.generalInfo.poolCap,
            pool.generalInfo.apy
        ) -
            pool.premiumInfo.premiumBalance +
            _pending;

        IERC20(pool.generalInfo.token).safeTransferFrom(
            pool.generalInfo.projectWallet,
            address(this),
            billAmount
        );

        pool.premiumInfo.premiumBalance += billAmount;

        // Calculate fee taken from premium payments. 10% taken from project upon billing.
        // Of that 10%, some % might go to referrer of bounty.The rest goes to The Saloon.
        uint256 saloonPremiumCommission = (billAmount * saloonFee) / BPS;

        (
            uint256 saloonAmount,
            uint256 referralAmount,
            address referrer
        ) = SaloonLib.calcReferralSplit(
                saloonPremiumCommission,
                pool.referralInfo.endTime,
                pool.referralInfo.referralFee,
                pool.referralInfo.referrer
            );
        address token = address(pool.generalInfo.token);
        _increaseReferralBalance(referrer, token, referralAmount);
        saloonPremiumProfit[token] += saloonAmount;

        uint256 billAmountMinusCommission = billAmount -
            saloonPremiumCommission;
        // available to make premium payment ->
        pool.premiumInfo.premiumAvailable += billAmountMinusCommission;

        emit PremiumBilled(_pid, billAmount);
    }

    /// @notice Withdraws current deposit held in active strategy
    /// @param _pid Bounty pool id
    function _withdrawFromActiveStrategy(uint256 _pid)
        internal
        returns (uint256)
    {
        PoolInfo storage pool = poolInfo[_pid];

        uint256 fundsWithdrawn;
        bytes32 activeStrategyHash = activeStrategies[_pid];

        // Reset active strategy upon every withdraw. All withdrawals are in full.
        activeStrategies[_pid] = bytes32(0);

        if (activeStrategyHash != bytes32(0)) {
            IStrategy activeStrategy = IStrategy(
                pidStrategies[_pid][activeStrategyHash]
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
            referralBalances[_referrer][_token] += _amount;
        }
    }

    function calcRequiredPremiumBalancePerPeriod(uint256 _poolCap, uint256 _apy)
        public
        pure
        returns (uint256 requiredPremiumBalance)
    {
        requiredPremiumBalance = (((_poolCap * _apy * PERIOD) / BPS) / YEAR);
    }

    function viewBountyBalance(uint256 _pid) public view returns (uint256) {
        PoolInfo memory pool = poolInfo[_pid];
        return (pool.generalInfo.totalStaked +
            (pool.depositInfo.projectDepositHeld +
                pool.depositInfo.projectDepositInStrategy));
    }

    function receiveStrategyYield(address _token, uint256 _amount)
        external
        virtual
    {}
}
