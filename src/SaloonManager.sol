// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import "./lib/OwnableUpgradeable.sol";
import "./interfaces/IStrategyFactory.sol";
import "./SaloonCommon.sol";
import "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Upgrade.sol";

// import "./interfaces/ISaloon.sol";

contract SaloonManager is
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    SaloonCommon
{
    using SafeERC20 for IERC20;

    ///////////////////////////////////////////////////////////////////////////////
    //                           SALOON OWNER FUNCTIONS                          //
    ///////////////////////////////////////////////////////////////////////////////
    function initialize() public initializer {
        __Ownable_init();
    }

    function setImplementations(
        ISaloonManager _saloonManager,
        ISaloonProjectPortal _saloonProjectPortal,
        ISaloonBounty _saloonBounty
    ) public onlyOwner {
        saloonManager = _saloonManager;
        saloonProjectPortal = _saloonProjectPortal;
        saloonBounty = _saloonBounty;
    }

    function setStrategyFactory(address _strategyFactory) external onlyOwner {
        strategyFactory = IStrategyFactory(_strategyFactory);
    }

    /// @notice Updates the list of ERC20 tokens allow to be used in bounty pools
    /// @notice _minStakeAmount must either be set on first whitelisting for token, or must be un-whitelisted and then re-whitelisted to reset value
    /// @dev Only one token is allowed per pool
    /// @param _token ERC20 to add or remove from whitelist
    /// @param _whitelisted bool to select if a token will be added or removed
    /// @param _minStakeAmount The minimum amount for staking for pools pools using such token
    function updateTokenWhitelist(
        address _token,
        bool _whitelisted,
        uint256 _minStakeAmount
    ) external onlyOwner returns (bool) {
        // require(
        //     tokenWhitelist[_token] == !_whitelisted,
        //     "no change to whitelist"
        // );
        tokenWhitelist[_token] = _whitelisted;
        emit tokenWhitelistUpdated(_token, _whitelisted);
        if (_whitelisted) {
            activeTokens.push(_token);
            minTokenStakeAmount[_token] = _minStakeAmount;
            return true;
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
    }

    /// @notice Adds a new bounty pool.
    /// @dev Can only be called by the owner.
    /// @param _token Token to be used by bounty pool
    /// @param _projectWallet Address that will be able to deposit funds, set APY and poolCap for the pool
    /// @param _projectName Name of the project that is hosting the bounty
    /// @param _referrer Address of the individual that referred this bounty to The Saloon
    /// @param _referralFee Referral fee that the referrer will receive (in BPS), max 50%
    /// @param _referralEndTime Timestamp up until the referral will be active
    function addNewBountyPool(
        address _token,
        address _projectWallet,
        string memory _projectName,
        address _referrer,
        uint256 _referralFee,
        uint256 _referralEndTime
    ) external onlyOwner returns (uint256) {
        require(tokenWhitelist[_token], "token not whitelisted");
        require(_referralFee <= 5000, "referral fee too high");
        // uint8 _tokenDecimals = IERC20(_token).decimals();
        (, bytes memory _decimals) = _token.staticcall(
            abi.encodeWithSignature("decimals()")
        );
        uint8 decimals = abi.decode(_decimals, (uint8));
        require(decimals >= 6, "Invalid decimal return");

        PoolInfo memory newBounty;
        newBounty.generalInfo.token = IERC20(_token);
        newBounty.generalInfo.tokenDecimals = decimals;
        newBounty.generalInfo.projectWallet = _projectWallet;
        newBounty.generalInfo.projectName = _projectName;
        newBounty.referralInfo.referrer = _referrer;
        newBounty.referralInfo.referralFee = _referralFee;
        newBounty.referralInfo.endTime = _referralEndTime;
        poolInfo.push(newBounty);
        // emit event
        return (poolInfo.length - 1);
    }

    /// @notice Extend the referral period for the bounty. The new end time can only be larger than the current value.
    /// @param _pid The pool id for the bounty
    /// @param _endTime The new end time for the referral bonus
    function extendReferralPeriod(uint256 _pid, uint256 _endTime)
        external
        onlyOwner
    {
        PoolInfo storage pool = poolInfo[_pid];
        require(
            _endTime > pool.referralInfo.endTime,
            "can only extend end time"
        );
        pool.referralInfo.endTime = _endTime;
    }

    /// @notice Bill premiums for a single pool.
    /// @param _pid The pool id for the bounty
    function billPremium(uint256 _pid)
        public
        nonReentrant
        onlyOwner
        returns (bool)
    {
        _billPremium(_pid, 0);
        return true;
    }

    // @notice Starts assesment period where users can withdraw instantly and
    //  bounty payouts dont use stakers fund
    function startAssessmentPeriod(uint256 _pid) external onlyOwner {
        poolInfo[_pid].assessmentPeriodEnd = block.timestamp + 14 days;
    }

    /// @notice Transfer Saloon profits for a specific token from premiums and bounties collected
    /// @param _token Token address to be transferred
    /// @param _saloonWallet Address where the funds will go to
    function collectSaloonProfits(address _token, address _saloonWallet)
        public
        onlyOwner
        returns (bool)
    {
        uint256 amount = saloonBountyProfit[_token] +
            saloonStrategyProfit[_token] +
            saloonPremiumProfit[_token];
        saloonBountyProfit[_token] = 0;
        saloonPremiumProfit[_token] = 0;
        saloonStrategyProfit[_token] = 0;
        IERC20(_token).safeTransfer(_saloonWallet, amount);
        return true;
    }

    /// @notice Transfer Saloon profits for all tokens from premiums and bounties collected
    /// @param _saloonWallet Address where the funds will go to
    function collectAllSaloonProfits(address _saloonWallet)
        external
        onlyOwner
        returns (bool)
    {
        uint256 activeTokenLength = activeTokens.length;
        for (uint256 i; i < activeTokenLength; ++i) {
            address _token = activeTokens[i];
            collectSaloonProfits(_token, _saloonWallet);
        }
        return true;
    }

    ///////////////////////////////////////////////////////////////////////////////
    //                          REFERRAL CLAIMING                                //
    ///////////////////////////////////////////////////////////////////////////////

    /// @notice Allows referrers to collect their profit from all bounties for one token
    /// @param _token Token used by the bounty that was referred
    function collectReferralProfit(address _token)
        public
        nonReentrant
        returns (bool)
    {
        uint256 amount = referralBalances[msg.sender][_token];
        if (amount > 0) {
            referralBalances[msg.sender][_token] = 0;
            IERC20(_token).safeTransfer(msg.sender, amount);
            emit referralPaid(msg.sender, amount);
        }
        return true;
    }

    /// @notice Allows referrers to collect their profit from all bounties for all tokens
    function collectAllReferralProfits() external returns (bool) {
        uint256 activeTokenLength = activeTokens.length;
        for (uint256 i; i < activeTokenLength; ++i) {
            address token = activeTokens[i];
            collectReferralProfit(token);
        }
        return true;
    }
}
