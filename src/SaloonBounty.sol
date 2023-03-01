// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./lib/ERC721Upgradeable.sol";
import "prb-math/UD60x18.sol";
import "./interfaces/ISaloon.sol";
import "./SaloonCommon.sol";

//TODO Turn some magic numbers used in calculateEffectiveAPY to constants

/* 
BountyToken ERC721
================================================
    ** Default Variables **
================================================
Default Curve: 1/(0.66x+0.1) 
--------------------------------
defaultAPY "average" ~= 1.06
--------------------------------
default MaxAPY(y-value) = 10 
--------------------------------
default max x-value = 5
--------------------------------
max-to-standard APY ratio:
ratio = ~9.43 = maxAPY/defaultAPY 
e.g 10/1.06 ~= 9.43
--------------------------------
Definite Integral to calculate effective APY:
(50000000000000 * ((ln(33 * (sk)) + 5_000_000) - ln((33 * s) + 5_000_000))) / 33
--------------------------------
Notes:
Default Curve is used to calculate the staking reward.
Such reward is then multiplied by scalingMultiplier to match the targetAPY offered by the project,
which my differ from the standard 1.06%
================================================
================================================
*/

contract SaloonBounty is
    ERC721Upgradeable,
    SaloonCommon,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;

    constructor() initializer {
        __ERC721_init("BountyToken", "BTT");
    }

    function initialize(address _strategyFactory) public initializer {
        __Ownable_init();
        strategyFactory = IStrategyFactory(_strategyFactory);
    }

    modifier activePool(uint256 _pid) {
        PoolInfo memory pool = poolInfo[_pid];
        if (!pool.isActive) revert("pool not active");
        _;
    }

    /// @notice Updates and transfers amount owed to a tokenId
    /// @param _tokenId Token Id of ERC721 being updated
    /// @param _shouldHarvest Whether staker wants to claim their owed premium or not
    function _updateTokenReward(uint256 _tokenId, bool _shouldHarvest)
        internal
    {
        NFTInfo storage token = nftInfo[_tokenId];
        uint256 pid = token.pid;
        PoolInfo storage pool = poolInfo[pid];

        (
            uint256 totalPending,
            uint256 actualPending,
            uint256 newPending
        ) = SaloonLib.pendingPremium(
                pool.freezeTime,
                token.lastClaimedTime,
                token.amount,
                token.apy,
                token.unclaimed
            );

        if (!_shouldHarvest) {
            token.lastClaimedTime = pool.freezeTime != 0
                ? pool.freezeTime
                : block.timestamp;
            token.unclaimed += newPending;
            return;
        }

        if (totalPending > pool.premiumInfo.premiumBalance) {
            // bill premium calculates commission
            _billPremium(pid, totalPending);
        }
        // if billPremium is not called we need to calcualte commission here
        if (totalPending > 0) {
            token.unclaimed = 0;
            token.lastClaimedTime = pool.freezeTime != 0
                ? pool.freezeTime
                : block.timestamp;
            pool.premiumInfo.premiumBalance -= totalPending;
            pool.premiumInfo.premiumAvailable -= actualPending;
            pool.generalInfo.token.safeTransfer(
                ownerOf(_tokenId),
                actualPending
            );
        }
    }

    /// @notice Pays valid bounty submission to hunter
    /// @dev only callable by Saloon owner
    /// @dev Includes Saloon commission + hunter payout
    /// @param __pid Bounty pool id
    /// @param _hunter Hunter address that will receive payout
    /// @param _payoutBPS Percentage of pool to payout in BPS
    /// @param _payoutBPS Percentage of Saloon's fee that will go to hunter as bonus
    function payBounty(
        uint256 __pid,
        address _hunter,
        uint16 _payoutBPS,
        uint16 _hunterBonusBPS
    ) public onlyOwner {
        require(_payoutBPS <= 10000, "Payout too high");
        require(_hunterBonusBPS <= 10000, "Bonus too high");
        uint256 _pid = __pid; // Appeasing "Stack too Deep" Gods
        PoolInfo storage pool = poolInfo[_pid];
        NFTInfo storage token;
        uint256 totalStaked = pool.generalInfo.totalStaked;
        uint256 poolTotal = viewBountyBalance(_pid);
        uint256 payoutAmount = (poolTotal * _payoutBPS) / BPS;
        uint256 length = pidNFTList[_pid].length;

        // if stakers can cover payout
        if (payoutAmount < totalStaked) {
            uint256 percentage = ((payoutAmount * PRECISION) / totalStaked);
            for (uint256 i; i < length; ) {
                uint256 tokenId = pidNFTList[_pid][i];
                token = nftInfo[tokenId];
                _updateTokenReward(tokenId, false);
                uint256 userPay = (token.amount * percentage) / PRECISION;
                token.amount -= userPay;
                pool.generalInfo.totalStaked -= userPay;
                unchecked {
                    ++i;
                }
            }
        } else if (payoutAmount >= totalStaked && payoutAmount <= poolTotal) {
            // set all token balances to zero
            for (uint256 i; i < length; ) {
                uint256 tokenId = pidNFTList[_pid][i];
                token = nftInfo[tokenId];
                _updateTokenReward(tokenId, false);
                token.amount = 0;
                token.apy = 0;
                pool.curveInfo.unstakedTokens.push(tokenId);
                unchecked {
                    ++i;
                }
            }
            pool.generalInfo.totalStaked = 0;
            // calculate remaining amount for project to pay
            _withdrawFromActiveStrategy(_pid);
            uint256 projectPayout = payoutAmount - totalStaked;
            pool.depositInfo.projectDepositHeld -= projectPayout;
        } else {
            revert("Amount too high");
        }

        // calculate saloon commission (10% by default, lower if _hunterBonusBPS > 0)
        uint256 saloonCommission = (((payoutAmount * saloonFee) / BPS) *
            (BPS - _hunterBonusBPS)) / BPS;

        // Calculate fee taken from bounty payments. 10% taken from total payment upon payout.
        // Of that 10%, some % might go to referrer of bounty. The rest goes to The Saloon.
        (
            uint256 saloonAmount,
            uint256 referralAmount,
            address referrer
        ) = SaloonLib.calcReferralSplit(
                saloonCommission,
                pool.referralInfo.endTime,
                pool.referralInfo.referralFee,
                pool.referralInfo.referrer
            );
        address paymentToken = address(pool.generalInfo.token);
        _increaseReferralBalance(referrer, paymentToken, referralAmount);
        saloonBountyProfit[paymentToken] += saloonAmount;

        // transfer payout to hunter
        IERC20(paymentToken).safeTransfer(
            _hunter,
            payoutAmount - saloonCommission
        );

        emit BountyPaid(_hunter, paymentToken, payoutAmount);
        emit BountyBalanceChanged(_pid, poolTotal, viewBountyBalance(_pid));
    }

    /// @notice Stake tokens in a Bounty pool to earn premium payments.
    /// @param _pid Bounty pool id
    /// @param _amount Amount to be staked
    function stake(uint256 _pid, uint256 _amount)
        external
        nonReentrant
        activePool(_pid)
        returns (uint256)
    {
        PoolInfo storage pool = poolInfo[_pid];
        require(
            _amount >= minTokenStakeAmount[address(pool.generalInfo.token)],
            "Min stake not met"
        );

        uint256 balanceBefore = viewBountyBalance(_pid);

        pool.generalInfo.token.safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );

        uint256 tokenId = _mint(_pid, msg.sender, _amount);

        pool.generalInfo.totalStaked += _amount;
        require(
            pool.generalInfo.totalStaked <= pool.generalInfo.poolCap,
            "Exceeded pool limit"
        );
        emit Staked(msg.sender, _pid, _amount);

        uint256 balanceAfter = viewBountyBalance(_pid);
        emit BountyBalanceChanged(_pid, balanceBefore, balanceAfter);

        return tokenId;
    }

    /// @notice Schedule unstake with specific amount
    /// @dev must be unstaked within a certain time window after scheduled
    /// @param _tokenId Token Id of ERC721 being unstaked
    function scheduleUnstake(uint256 _tokenId)
        external
        nonReentrant
        returns (bool)
    {
        require(
            _isApprovedOrOwner(msg.sender, _tokenId),
            "sender is not owner"
        );

        NFTInfo storage token = nftInfo[_tokenId];
        uint256 pid = token.pid;
        token.timelock = block.timestamp + PERIOD;
        token.timelimit = block.timestamp + PERIOD + 3 days;

        emit WithdrawalOrUnstakeScheduled(pid, token.amount);
        return true;
    }

    /// @notice Unstake scheduled tokenId
    /// @param _tokenId Token Id of ERC721 being unstaked
    /// @param _shouldHarvest Whether staker wants to claim their owed premium or not
    function unstake(uint256 _tokenId, bool _shouldHarvest)
        external
        nonReentrant
        returns (bool)
    {
        require(
            _isApprovedOrOwner(msg.sender, _tokenId),
            "sender is not owner"
        );

        NFTInfo storage token = nftInfo[_tokenId];
        uint256 pid = token.pid;
        PoolInfo storage pool = poolInfo[pid];

        require(
            token.timelock < block.timestamp &&
                token.timelimit > block.timestamp,
            "Timelock not set or not completed in time"
        );

        _updateTokenReward(_tokenId, _shouldHarvest);

        uint256 amount = token.amount;

        token.amount = 0;
        token.timelock = 0;
        token.timelimit = 0;

        uint256 balanceBefore = viewBountyBalance(pid);

        // If user is claiming premium while unstaking, burn the NFT position.
        // We only allow the user to not claim premium to ensure that they can
        // unstake even if premium can't be pulled from project.
        // We burn the position if both token.amount and token.unclaimed are 0.
        if (_shouldHarvest) _burn(_tokenId);

        if (amount > 0) {
            pool.generalInfo.totalStaked -= amount;

            pool.generalInfo.token.safeTransfer(msg.sender, amount);
        }

        emit Unstaked(msg.sender, pid, amount);

        uint256 balanceAfter = viewBountyBalance(pid);
        emit BountyBalanceChanged(pid, balanceBefore, balanceAfter);

        // If any unstake occurs, pool needs consolidation. Even if the last token in the pid array unstakes, the pool X value needs
        // to be reset to the proper location
        pool.curveInfo.unstakedTokens.push(_tokenId);

        return true;
    }

    /// @notice Claims premium for specified tokenId
    /// @param _tokenId Token Id of ERC721
    function claimPremium(uint256 _tokenId) external nonReentrant {
        require(
            _isApprovedOrOwner(msg.sender, _tokenId),
            "ERC721: caller is not token owner or approved"
        );
        _updateTokenReward(_tokenId, true);

        // Burn token in case token amount == 0. This can occur when:
        // 1) User called unstake() with _shouldHarvest == false. They received their deposit back
        // and left their unclaimed premium in the contract.
        // 2) The pool was emptied via payBounty() following payout for a critical severity submission.
        if (nftInfo[_tokenId].amount == 0) _burn(_tokenId);
    }

    //===========================================================================||
    //                               TOKEN UTILS                                 ||
    //===========================================================================||

    /// @notice Gets Current APY of pool (y-value) scaled to target APY
    /// @param _pid Bounty pool id
    function getCurrentAPY(uint256 _pid)
        public
        view
        returns (uint256 currentAPY)
    {
        PoolInfo memory pool = poolInfo[_pid];

        // get current x-value
        uint256 x = pool.curveInfo.currentX;
        // get pool multiplier
        uint256 m = pool.generalInfo.scalingMultiplier;

        // current unit APY = current y-value * scalingMultiplier
        currentAPY = SaloonLib.getCurrentAPY(x, m);
    }

    /// @notice Calculates effective APY staker will be entitled to in exchange for amount staked
    /// @dev formula for calculating effective price:
    ///      (50000000000000 * ((ln(33 * (sk)) + 5_000_000) - ln((33 * s) + 5_000_000))) / 33
    /// @param _pid Bounty pool id
    /// @param _stake amount to be staked
    /// @param _x Arbitrary X value
    function calculateEffectiveAPY(
        uint256 _pid,
        uint256 _stake,
        uint256 _x
    ) public view returns (uint256 scaledAPY) {
        PoolInfo memory pool = poolInfo[_pid];

        scaledAPY = SaloonLib.calculateArbitraryEffectiveAPY(
            _stake,
            _x,
            pool.generalInfo.poolCap,
            pool.generalInfo.scalingMultiplier
        );
    }

    /// @notice Update current pool size (X value)
    /// @dev reflects the new value of X in relation to change in pool size
    /// @param _pid Bounty pool id
    /// @param _newX New X value
    function _updateCurrentX(uint256 _pid, uint256 _newX)
        internal
        returns (bool)
    {
        poolInfo[_pid].curveInfo.currentX = _newX;
        return true;
    }

    ///  update unit APY value (y value)
    /// @param _x current x-value representing total stake amount
    /// @param _pid ID of pool
    function _updateCurrentY(uint256 _pid, uint256 _x)
        internal
        returns (uint256 newAPY)
    {
        newAPY = SaloonLib._curveImplementation(_x);
        poolInfo[_pid].curveInfo.currentY = newAPY;
    }

    function _removeNFTFromPidList(uint256 _tokenId) internal {
        NFTInfo memory token = nftInfo[_tokenId];
        uint256 pid = token.pid;

        uint256[] memory cachedList = pidNFTList[pid];
        uint256 length = cachedList.length;
        uint256 pos;

        for (uint256 i = 0; i < length; ++i) {
            if (cachedList[i] == _tokenId) {
                pos = i;
                break;
            }
        }

        if (pos >= length) revert("Token not found in array");

        for (uint256 i = pos; i < length - 1; ++i) {
            cachedList[i] = cachedList[i + 1];
        }
        pidNFTList[pid] = cachedList;
        pidNFTList[pid].pop(); // Can't pop from array in memory, so pop after writing to storage
    }

    /// @notice Mints ERC721 to staker representing their stake and how much APY they are entitled to
    /// @dev also updates pool variables
    /// @param _pid Bounty pool id
    /// @param _staker Staker address
    /// @param _stake Stake amount
    function _mint(
        uint256 _pid,
        address _staker,
        uint256 _stake
    ) internal returns (uint256) {
        require(_staker != address(0), "ERC20: mint to the zero address");

        uint256 apy = calculateEffectiveAPY(
            _pid,
            _stake,
            poolInfo[_pid].curveInfo.currentX
        );
        // uint256 apy = poolInfo[_pid].generalInfo.apy;

        uint256 tokenId = super._mint(_staker);

        NFTInfo memory token;

        token.pid = _pid;
        // Convert _amount to X value
        token.amount = _stake;
        (uint256 xDelta, ) = SaloonLib._convertStakeToPoolMeasurements(
            _stake,
            poolInfo[_pid].generalInfo.poolCap
        );

        require(
            poolInfo[_pid].curveInfo.totalSupply + xDelta <= 5 ether,
            "X boundary violated"
        );

        token.xDelta = xDelta;
        token.apy = apy;
        token.lastClaimedTime = block.timestamp;
        nftInfo[tokenId] = token;

        pidNFTList[_pid].push(tokenId);

        poolInfo[_pid].curveInfo.totalSupply += xDelta;
        _updateCurrentX(_pid, poolInfo[_pid].curveInfo.totalSupply);

        // _afterTokenTransfer(address(0), _staker, _amount);

        return tokenId;
    }

    /// @notice Processes unstakes and calculates new APY for remaining stakers of a specific pool
    /// @param _pid Bounty pool id
    function consolidate(uint256 _pid) public {
        PoolInfo memory pool = poolInfo[_pid];
        uint256[] memory unstakedTokens = pool.curveInfo.unstakedTokens;
        uint256 unstakeLength = unstakedTokens.length;

        if (unstakeLength == 0 || !pool.isActive) return; // No unstakes have occured, no need to consolidate

        for (uint256 i = 0; i < unstakeLength; ++i) {
            _removeNFTFromPidList(unstakedTokens[i]);
        }

        uint256[] memory tokenArray = pidNFTList[_pid];
        uint256 length = tokenArray.length;
        uint256 memX;

        for (uint256 i = 0; i < length; ++i) {
            uint256 tokenId = tokenArray[i];
            NFTInfo storage token = nftInfo[tokenId];
            uint256 stakeAmount = token.amount;
            token.apy = calculateEffectiveAPY(_pid, stakeAmount, memX);
            memX += token.xDelta;
        }

        poolInfo[_pid].curveInfo.totalSupply = memX;
        delete poolInfo[_pid].curveInfo.unstakedTokens;
    }

    /// @notice Processes unstakes and calculates new APY for remaining stakers for all pools
    function consolidateAll() external {
        uint256 arrayLength = poolInfo.length;
        for (uint256 i = 0; i < arrayLength; ++i) {
            consolidate(i);
        }
    }

    // function receiveStrategyYield(address _token, uint256 _amount)
    //     external
    //     virtual
    // {}

    function getAllTokensByOwner(
        address _owner //NOTE function not necessary if same can be done via frontend
    ) public view returns (NFTInfo[] memory userTokens) {
        uint256[] memory tokens = _ownedTokens[_owner];
        uint256 tokenLength = tokens.length;
        userTokens = new NFTInfo[](tokenLength);

        for (uint256 i = 0; i < tokenLength; ++i) {
            userTokens[i] = nftInfo[tokens[i]];
        }
    }
}
