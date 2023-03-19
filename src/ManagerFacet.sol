// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "./Base.sol";
import "./interfaces/IManagerFacet.sol";
import "./interfaces/IStrategyFactory.sol";
import "./lib/LibSaloon.sol";

contract ManagerFacet is Base, IManagerFacet {
    using SafeERC20 for IERC20;

    //===========================================================================||
    //                         SALOON OWNER FUNCTIONS                            ||
    //===========================================================================||

    function setStrategyFactory(address _strategyFactory) external onlyOwner {
        s.strategyFactory = IStrategyFactory(_strategyFactory);
    }

    function setLibSaloonStorage() external onlyOwner {
        LibSaloon.LibSaloonStorage storage ss = LibSaloon.getLibSaloonStorage();
        ss.defaultAPY = 1.06 ether;
        ss.bps = 10_000;
        ss.precision = 1e18;
        ss.year = 365 days;
        ss.period = 1 weeks;
        ss.saloonFee = 1000;
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
        // require(// NOTE WHY WAS THIS HERE IN THE FIRST PLACE?
        //     tokenWhitelist[_token] == !_whitelisted,
        //     "no change to whitelist"
        // );
        s.tokenWhitelist[_token] = _whitelisted;
        emit tokenWhitelistUpdated(_token, _whitelisted);
        if (_whitelisted) {
            s.activeTokens.push(_token);
            s.minTokenStakeAmount[_token] = _minStakeAmount;
            return true;
        } else {
            uint256 activeTokenLength = s.activeTokens.length;
            for (uint256 i; i < activeTokenLength; ++i) {
                address token = s.activeTokens[i];
                if (token == _token) {
                    s.activeTokens[i] = s.activeTokens[activeTokenLength - 1];
                    s.activeTokens.pop();
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
        require(s.tokenWhitelist[_token], "token not whitelisted");
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
        s.poolInfo.push(newBounty);
        // emit event
        return (s.poolInfo.length - 1);
    }

    /// @notice Extend the referral period for the bounty. The new end time can only be larger than the current value.
    /// @param _pid The pool id for the bounty
    /// @param _endTime The new end time for the referral bonus
    function extendReferralPeriod(
        uint256 _pid,
        uint256 _endTime
    ) external onlyOwner {
        PoolInfo storage pool = s.poolInfo[_pid];
        require(
            _endTime > pool.referralInfo.endTime,
            "can only extend end time"
        );
        pool.referralInfo.endTime = _endTime;
    }

    /// @notice Bill premiums for a single pool.
    /// @param _pid The pool id for the bounty
    function billPremium(
        uint256 _pid
    ) public nonReentrant onlyOwner returns (bool) {
        _billPremium(_pid, 0);
        return true;
    }

    /// @notice Starts assesment period where users can withdraw instantly and
    ///  bounty payouts dont use stakers fund
    function startAssessmentPeriod(uint256 _pid) external onlyOwner {
        s.poolInfo[_pid].assessmentPeriodEnd = block.timestamp + 14 days;
    }

    /// @notice Transfer Saloon profits for a specific token from premiums and bounties collected
    /// @param _token Token address to be transferred
    /// @param _saloonWallet Address where the funds will go to
    function collectSaloonProfits(
        address _token,
        address _saloonWallet
    ) public onlyOwner returns (bool) {
        uint256 amount = s.saloonBountyProfit[_token] +
            s.saloonStrategyProfit[_token] +
            s.saloonPremiumProfit[_token];
        s.saloonBountyProfit[_token] = 0;
        s.saloonPremiumProfit[_token] = 0;
        s.saloonStrategyProfit[_token] = 0;
        IERC20(_token).safeTransfer(_saloonWallet, amount);
        return true;
    }

    /// @notice Transfer Saloon profits for all tokens from premiums and bounties collected
    /// @param _saloonWallet Address where the funds will go to
    function collectAllSaloonProfits(
        address _saloonWallet
    ) external onlyOwner returns (bool) {
        uint256 activeTokenLength = s.activeTokens.length;
        for (uint256 i; i < activeTokenLength; ++i) {
            address _token = s.activeTokens[i];
            collectSaloonProfits(_token, _saloonWallet);
        }
        return true;
    }

    //===========================================================================||
    //                       INTERNAL FUNCTIONS                                  ||
    //===========================================================================||

    // NOTE billpremium now doesnt bill includiing saloon commission...
    /// @notice Bills premium from project wallet
    /// @dev Billing is capped at requiredPremiumBalancePerPeriod so not even admins can bill more than needed
    /// @dev This prevents anyone calling this multiple times and draining the project wallet
    /// @param _pid Bounty pool id of what pool is being billed
    /// @param _pending The extra amount of pending that must be billed to bring bounty balance up to full
    function _billPremium(uint256 _pid, uint256 _pending) internal {
        LibSaloon.LibSaloonStorage memory ss = LibSaloon.getLibSaloonStorage();
        PoolInfo storage pool = s.poolInfo[_pid];

        // FIXME billAmount = weeklyPremium - (currentBalance + pendingPremium) | pendingPremium = unclaimed + accrued
        uint256 billAmount = LibSaloon.calcRequiredPremiumBalancePerPeriod(
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
        uint256 saloonPremiumCommission = (billAmount * ss.saloonFee) / ss.bps;

        (
            uint256 saloonAmount,
            uint256 referralAmount,
            address referrer
        ) = LibSaloon.calcReferralSplit(
                saloonPremiumCommission,
                pool.referralInfo.endTime,
                pool.referralInfo.referralFee,
                pool.referralInfo.referrer
            );
        address token = address(pool.generalInfo.token);
        _increaseReferralBalance(referrer, token, referralAmount);
        s.saloonPremiumProfit[token] += saloonAmount;

        uint256 billAmountMinusCommission = billAmount -
            saloonPremiumCommission;
        // available to make premium payment ->
        pool.premiumInfo.premiumAvailable += billAmountMinusCommission;

        emit PremiumBilled(_pid, billAmount);
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

    // NOTE Perhaps have another facet for this?
    //===========================================================================||
    //                        REFERRAL CLAIMING                                  ||
    //===========================================================================||

    /// @notice Allows referrers to collect their profit from all bounties for one token
    /// @param _token Token used by the bounty that was referred
    function collectReferralProfit(
        address _token
    ) public nonReentrant returns (bool) {
        uint256 amount = s.referralBalances[msg.sender][_token];
        if (amount > 0) {
            s.referralBalances[msg.sender][_token] = 0;
            IERC20(_token).safeTransfer(msg.sender, amount);
            emit referralPaid(msg.sender, amount);
        }
        return true;
    }

    /// @notice Allows referrers to collect their profit from all bounties for all tokens
    function collectAllReferralProfits() external returns (bool) {
        uint256 activeTokenLength = s.activeTokens.length;
        for (uint256 i; i < activeTokenLength; ++i) {
            address token = s.activeTokens[i];
            collectReferralProfit(token);
        }
        return true;
    }

    //===========================================================================||
    //                        OWNER TRANSFER                                     ||
    //===========================================================================||

    /// @notice Starts the transfer of owner rights. Only the current owner can propose a new pending one.
    /// @notice New owner can accept owner rights by calling `acceptOwnershipTransfer` function.
    /// @param _newPendingOwner Address of the new owner
    function setPendingOwner(address _newPendingOwner) external onlyOwner {
        // Save previous value into the stack to put it into the event later
        address oldPendingOwner = s.owner;

        if (oldPendingOwner != _newPendingOwner) {
            // Change pending owner
            s.pendingOwner = _newPendingOwner;

            emit NewPendingOwner(oldPendingOwner, _newPendingOwner);
        }
    }

    /// @notice Accepts transfer of admin rights. Only pending owner can accept the role.
    function acceptOwnershipTransfer() external {
        address pendingOwner = s.pendingOwner;
        require(msg.sender == pendingOwner, "not pending owner"); // Only proposed by current owner address can claim the owner rights

        if (pendingOwner != s.owner) {
            address previousOwner = s.owner;
            s.owner = pendingOwner;
            delete s.pendingOwner;

            emit NewPendingOwner(pendingOwner, address(0));
            emit NewOwner(previousOwner, pendingOwner);
        }
    }
}
