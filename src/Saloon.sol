// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "openzeppelin-contracts/contracts/utils/math/SafeMath.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import "./lib/OwnableUpgradeable.sol";
import "./BountyTokenNFT.sol";
import "./StrategyFactory.sol";

/* Implement:
- TODO implement BPS in payBounty
- TODO Fill in missing events
- TODO Referral profit tests (Bounty/Premium/Yield)
*/

contract Saloon is
    OwnableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuard,
    BountyTokenNFT
{
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    uint256 constant YEAR = 365 days;
    uint256 constant PERIOD = 1 weeks;
    uint256 constant bountyFee = 1000; // 10%
    uint256 constant premiumFee = 1000; // 10%

    mapping(address => uint256) public saloonBountyProfit;
    mapping(address => uint256) public saloonPremiumProfit;
    mapping(address => uint256) public saloonStrategyProfit;
    mapping(address => mapping(address => uint256)) public referralBalances; // referrer => token => amount

    // Strategy factory to deploy unique strategies for each pid. No co-mingling.
    StrategyFactory strategyFactory;

    // Mapping of all strategies for pid
    // pid => keccak256(abi.encode(strategyName)) => strategy address
    mapping(uint256 => mapping(bytes32 => address)) public pidStrategies;

    // Mapping of active strategy for pid
    mapping(uint256 => bytes32) public activeStrategies;

    // Reverse mapping of strategy to pid for easy lookup
    mapping(address => uint256) public strategyAddressToPid;

    // Mapping of whitelisted tokens
    mapping(address => bool) public tokenWhitelist;

    // Mapping of whitelisted tokens
    address[] public activeTokens;

    // Minimum stake amounts per token.
    mapping(address => uint256) public minTokenStakeAmount;

    modifier activePool(uint256 _pid) {
        PoolInfo memory pool = poolInfo[_pid];
        if (!pool.isActive) revert("pool not active");
        _;
    }

    function initialize(address _strategyFactory) public initializer {
        __Ownable_init();
        strategyFactory = StrategyFactory(_strategyFactory);
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

    ///////////////////////////////////////////////////////////////////////////////
    /////////////////////////// SALOON OWNER FUNCTIONS ///////////////////////////
    ///////////////////////////////////////////////////////////////////////////////

    /// @notice Updates the list of ERC20 tokens allow to be used in bounty pools
    /// @dev Only one token is allowed per pool
    /// @param _token ERC20 to add or remove from whitelist
    /// @param _whitelisted bool to select if a token will be added or removed
    /// @param _minStakeAmount The minimum amount for staking for pools pools using such token
    function updateTokenWhitelist(
        address _token,
        bool _whitelisted,
        uint256 _minStakeAmount
    ) external onlyOwner returns (bool) {
        require(
            tokenWhitelist[_token] == !_whitelisted || _minStakeAmount > 0,
            "no change to whitelist"
        );
        tokenWhitelist[_token] = _whitelisted;
        emit tokenWhitelistUpdated(_token, _whitelisted);

        if (_whitelisted) {
            activeTokens.push(_token);
            minTokenStakeAmount[_token] = _minStakeAmount;
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

    /// @notice Adds a new bounty pool
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

    function billPremium(uint256 _pid) public onlyOwner returns (bool) {
        _billPremium(_pid, 0);
        return true;
    }

    /// @notice Transfer Saloon profits for a specific token from premiums and bounties collected
    /// @param _token Token address to be transferred
    /// @param _saloonWallet Address where the funds will go to
    function collectSaloonProfits(address _token, address _saloonWallet)
        public
        onlyOwner
        returns (bool)
    {
        (uint256 amount, , , ) = viewSaloonProfitBalance(_token);
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

    ///////////////////////////////////////////////////////////////////////////////
    /////////////////////////// REFERRAL CLAIMING /////////////////////////////////
    ///////////////////////////////////////////////////////////////////////////////

    /// @notice Allows referrers to collect their profit from all bounties for one token
    /// @param _token Token used by the bounty that was referred
    function collectReferralProfit(address _token) public returns (bool) {
        uint256 amount = viewReferralBalance(msg.sender, _token);
        referralBalances[msg.sender][_token] = 0;
        IERC20(_token).safeTransfer(msg.sender, amount);
        emit referralPaid(msg.sender, amount);
        return true;
    }

    /// @notice Allows referrers to collect their profit from all bounties for all tokens
    function collectAllReferralProfits() external returns (bool) {
        uint256 activeTokenLength = activeTokens.length;
        for (uint256 i; i < activeTokenLength; ++i) {
            address _token = activeTokens[i];
            collectReferralProfit(_token);
        }
        return true;
    }

    ///////////////////////////////////////////////////////////////////////////////
    /////////////////////////// STRATEGY MANAGEMENT ///////////////////////////////
    ///////////////////////////////////////////////////////////////////////////////

    /// @notice Updates Stategy Factory address
    /// @param _strategyFactory new Strategy Factory address
    function updateStrategyFactoryAddress(address _strategyFactory)
        external
        onlyOwner
    {
        strategyFactory = StrategyFactory(_strategyFactory);
    }

    /// @notice Deploys a new strategy contract if the bounty does not have one already
    function _deployStrategyIfNeeded(uint256 _pid, string memory _strategyName)
        internal
        returns (address)
    {
        address deployedStrategy;
        bytes32 strategyHash = keccak256(abi.encode(_strategyName));
        address pidStrategy = pidStrategies[_pid][strategyHash];
        if (pidStrategy == address(0)) {
            deployedStrategy = strategyFactory.deployStrategy(
                _strategyName,
                address(poolInfo[_pid].generalInfo.token)
            );
        } else {
            return pidStrategy;
        }

        if (deployedStrategy == address(0)) {
            return address(0);
        } else {
            pidStrategies[_pid][strategyHash] = deployedStrategy;
            activeStrategies[_pid] = strategyHash;
            strategyAddressToPid[deployedStrategy] = _pid;
        }

        return deployedStrategy;
    }

    /// @notice Function to handle deploying new strategy, switching strategies, depositing to strategy
    /// @param _pid Bounty pool id
    /// @param _strategyName Name of the strategy
    /// @param _newDeposit New deposit amount
    function handleStrategyDeposit(
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
                pool.depositInfo.projectDepositHeld -=
                    _newDeposit +
                    fundsWithdrawn;
                // Subtract 1 wei due to precision loss when depositing into strategy if redeemed immediately
                pool.depositInfo.projectDepositInStrategy +=
                    _newDeposit +
                    fundsWithdrawn -
                    1;
                IERC20(pool.generalInfo.token).safeTransfer(
                    deployedStrategy,
                    _newDeposit + fundsWithdrawn
                );
                strategy.depositToStrategy();
            } else {
                pool.depositInfo.projectDepositHeld += _newDeposit;
            }
        }
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
            ) = calcReferralSplit(pid, _amount);
            _increaseReferralBalance(referrer, _token, referralAmount);
            saloonStrategyProfit[_token] += saloonAmount;
        }
    }

    /// @notice Harvest pending yield from active strategy for single pid and reinvest
    /// @param _pid Pool id whose strategy should be compounded
    function compoundYieldForPid(uint256 _pid) public {
        bytes32 strategyHash = activeStrategies[_pid];
        address deployedStrategy = pidStrategies[_pid][strategyHash];
        if (deployedStrategy != address(0))
            IStrategy(deployedStrategy).compound();
    }

    /// @notice Harvest pending yield from active strategy for all pids and reinvest
    function compoundYieldForAll() external {
        uint256 arrayLength = poolInfo.length;
        for (uint256 i = 0; i < arrayLength; ++i) {
            compoundYieldForPid(i);
        }
    }

    ///////////////////////////////////////////////////////////////////////////////
    /////////////////////////// PROJECT OWNER FUNCTIONS ///////////////////////////
    ///////////////////////////////////////////////////////////////////////////////

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
        uint256 requiredPremiumBalancePerPeriod = calcRequiredPremiumBalancePerPeriod(
                _poolCap,
                _apy
            );

        uint256 saloonCommission = (requiredPremiumBalancePerPeriod * //note could make this a pool.variable
            premiumFee) / BPS;

        IERC20(pool.generalInfo.token).safeTransferFrom(
            msg.sender,
            address(this),
            _deposit + requiredPremiumBalancePerPeriod
        );
        pool.depositInfo.projectDepositHeld += _deposit;
        pool.generalInfo.poolCap = _poolCap;
        pool.generalInfo.apy = _apy;
        pool.isActive = true;
        pool.premiumInfo.premiumBalance = requiredPremiumBalancePerPeriod;
        pool.premiumInfo.premiumAvailable =
            requiredPremiumBalancePerPeriod -
            saloonCommission;

        updateScalingMultiplier(_pid, _apy);

        if (bytes(_strategyName).length > 0) {
            handleStrategyDeposit(_pid, _strategyName, _deposit);
        }
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
    ) external {
        PoolInfo storage pool = poolInfo[_pid];
        require(msg.sender == pool.generalInfo.projectWallet, "Not authorized");

        uint256 balanceBefore = pool.generalInfo.totalStaked +
            viewMinProjectDeposit(_pid);
        IERC20(pool.generalInfo.token).safeTransferFrom(
            msg.sender,
            address(this),
            _deposit
        );
        pool.depositInfo.projectDepositHeld += _deposit;
        uint256 balanceAfter = pool.generalInfo.totalStaked +
            viewMinProjectDeposit(_pid);

        handleStrategyDeposit(_pid, _strategyName, _deposit);

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
            viewMinProjectDeposit(_pid) >= _amount,
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

        uint256 balanceBefore = pool.generalInfo.totalStaked +
            viewMinProjectDeposit(_pid);
        pool.depositInfo.projectDepositHeld -= _amount;
        IERC20(pool.generalInfo.token).safeTransfer(
            pool.generalInfo.projectWallet,
            _amount
        );
        uint256 balanceAfter = pool.generalInfo.totalStaked +
            viewMinProjectDeposit(_pid);

        emit BountyBalanceChanged(_pid, balanceBefore, balanceAfter);
        return true;
    }

    /// @notice Deactivates pool
    /// @param _pid Bounty pool id
    function windDownBounty(uint256 _pid) external returns (bool) {
        PoolInfo storage pool = poolInfo[_pid];
        require(
            msg.sender == pool.generalInfo.projectWallet ||
                msg.sender == _owner,
            "Not authorized"
        );
        require(pool.isActive, "Pool not active");
        pool.isActive = false;
        pool.freezeTime = block.timestamp;
        return true;
    }

    ///////////////////////////////////////////////////////////////////////////////
    /////////////////////////// USER FUNCTIONS ////////////////////////////////////
    ///////////////////////////////////////////////////////////////////////////////

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

        uint256 balanceBefore = pool.generalInfo.totalStaked +
            viewMinProjectDeposit(_pid);

        pool.generalInfo.token.safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );

        uint256 tokenId = _mint(_pid, msg.sender, _amount);

        pool.generalInfo.totalStaked += _amount;
        require(
            pool.generalInfo.poolCap > 0 &&
                pool.generalInfo.totalStaked <= pool.generalInfo.poolCap,
            "Exceeded pool limit"
        );
        emit Staked(msg.sender, _pid, _amount);

        uint256 balanceAfter = pool.generalInfo.totalStaked +
            viewMinProjectDeposit(_pid);
        emit BountyBalanceChanged(_pid, balanceBefore, balanceAfter);

        return tokenId;
    }

    /// @notice Schedule unstake with specific amount
    /// @dev must be unstaked within a certain time window after scheduled
    /// @param _tokenId Token Id of ERC721 being unstaked
    function scheduleUnstake(uint256 _tokenId) external returns (bool) {
        require(ownerOf(_tokenId) == msg.sender, "sender is not owner");

        uint256 _pid = nftToPid[_tokenId];
        NFTInfo storage token = nftInfo[_tokenId];
        token.timelock = block.timestamp + PERIOD;
        token.timelimit = block.timestamp + PERIOD + 3 days;

        uint256 withdrawableAmount = token.amount;

        emit WithdrawalOrUnstakeScheduled(_pid, withdrawableAmount);
        return true;
    }

    /// @notice Unstake scheduled tokenId
    /// @param _tokenId Token Id of ERC721 being unstaked
    /// @param _shouldHarvest Whether staker wants to claim his owed premium or not
    function unstake(uint256 _tokenId, bool _shouldHarvest)
        external
        nonReentrant
        returns (bool)
    {
        require(ownerOf(_tokenId) == msg.sender, "sender is not owner");

        uint256 _pid = nftToPid[_tokenId];
        PoolInfo storage pool = poolInfo[_pid];
        NFTInfo storage token = nftInfo[_tokenId];

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

        uint256 balanceBefore = pool.generalInfo.totalStaked +
            viewMinProjectDeposit(_pid);

        // If user is claiming premium while unstaking, burn the NFT position.
        // We only allow the user to not claim premium to ensure that they can
        // unstake even if premium can't be pulled from project.
        // We burn the position if both token.amount and token.unclaimed are 0.
        if (_shouldHarvest) _burn(_tokenId);

        if (amount > 0) {
            pool.generalInfo.totalStaked = pool.generalInfo.totalStaked.sub(
                amount
            );
            pool.generalInfo.token.safeTransfer(msg.sender, amount);
        }

        emit Unstaked(msg.sender, _pid, amount);

        uint256 balanceAfter = pool.generalInfo.totalStaked +
            viewMinProjectDeposit(_pid);
        emit BountyBalanceChanged(_pid, balanceBefore, balanceAfter);

        // If any unstake occurs, pool needs consolidation. Even if the last token in the pid array unstakes, the pool X value needs
        // to be reset to the proper location
        pool.curveInfo.unstakedTokens.push(_tokenId);

        return true;
    }

    /// @notice Updates and transfers amount owed to a tokenId
    /// @param _tokenId Token Id of ERC721 being updated
    /// @param _shouldHarvest Whether staker wants to claim his owed premium or not
    function _updateTokenReward(uint256 _tokenId, bool _shouldHarvest)
        internal
    {
        uint256 pid = nftToPid[_tokenId];
        PoolInfo storage pool = poolInfo[pid];
        NFTInfo storage token = nftInfo[_tokenId];

        // if (token.amount == 0 && token.unclaimed == 0) { todo delete this?
        //     token.lastClaimedTime = block.timestamp;
        //     return;
        // }
        (
            uint256 totalPending,
            uint256 actualPending,
            uint256 newPending
        ) = pendingPremium(_tokenId);

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

    /// @notice Claims premium for specified tokenId
    /// @param _tokenId Token Id of ERC721
    function claimPremium(uint256 _tokenId) external nonReentrant {
        require(
            _isApprovedOrOwner(_msgSender(), _tokenId),
            "ERC721: caller is not token owner or approved"
        );
        _updateTokenReward(_tokenId, true);
    }

    ///////////////////////////////////////////////////////////////////////////////
    /////////////////////////// INTERNAL FUNCTIONS ////////////////////////////////
    ///////////////////////////////////////////////////////////////////////////////

    /// @notice Bills premium from project wallet
    /// @param _pid Bounty pool id of what pool is being billed
    /// @param _pending How much premium stakers are owed
    function _billPremium(uint256 _pid, uint256 _pending) internal {
        PoolInfo storage pool = poolInfo[_pid];

        // Billing is capped at requiredPremiumBalancePerPeriod so not even admins can bill more than needed
        // This prevents anyone calling this 1000 times and draining the project wallet

        uint256 billAmount = calcRequiredPremiumBalancePerPeriod(
            pool.generalInfo.poolCap,
            pool.generalInfo.apy
        ) -
            pool.premiumInfo.premiumBalance +
            _pending; // NOTE bill premium now doesnt bill includiing saloon commission...

        IERC20(pool.generalInfo.token).safeTransferFrom(
            pool.generalInfo.projectWallet,
            address(this),
            billAmount
        );

        // Calculate fee taken from premium payments. 10% taken from project upon billing.
        // Of that 10%, some % might go to referrer of bounty.The rest goes to The Saloon.
        uint256 saloonPremiumCommission = (billAmount * premiumFee) / BPS;
        pool.premiumInfo.premiumBalance += billAmount;

        (
            uint256 saloonAmount,
            uint256 referralAmount,
            address referrer
        ) = calcReferralSplit(_pid, saloonPremiumCommission);
        address token = address(pool.generalInfo.token);
        _increaseReferralBalance(referrer, token, referralAmount);
        saloonPremiumProfit[token] += saloonAmount;

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
            referralBalances[_referrer][_token] += _amount;
        }
    }

    /// @notice Pays valid bounty submission to hunter
    /// @dev only callable by Saloon owner
    /// @dev Includes Saloon commission + hunter payout
    /// @param _pid Bounty pool id
    /// @param _hunter Hunter address that will receive payout
    /// @param _payoutBPS Percentage of pool to payout in BPS
    function payBounty(
        uint256 _pid,
        address _hunter,
        uint256 _payoutBPS
    ) public onlyOwner returns (bool) {
        PoolInfo storage pool = poolInfo[_pid];
        uint256 totalStaked = pool.generalInfo.totalStaked;
        uint256 poolTotal = totalStaked + viewMinProjectDeposit(_pid);
        uint256 payoutAmount = (poolTotal * _payoutBPS) / BPS;

        // if stakers can cover payout
        if (payoutAmount == totalStaked) {
            // set all token balances to zero
            uint256 length = pidNFTList[_pid].length;
            for (uint256 i; i < length; ) {
                uint256 tokenId = pidNFTList[_pid][i];
                NFTInfo storage token = nftInfo[tokenId];
                _updateTokenReward(tokenId, false);
                token.amount = 0;
                unchecked {
                    ++i;
                }
            }
            pool.generalInfo.totalStaked = 0;
            delete pool.stakerList;
        } else if (payoutAmount < totalStaked) {
            uint256 percentage = ((payoutAmount * PRECISION) / totalStaked);
            uint256 length = pidNFTList[_pid].length;
            for (uint256 i; i < length; ) {
                uint256 tokenId = pidNFTList[_pid][i];
                NFTInfo storage token = nftInfo[tokenId];
                _updateTokenReward(tokenId, false);
                uint256 userPay = (token.amount * percentage) / PRECISION;
                token.amount -= userPay;
                pool.generalInfo.totalStaked -= userPay;
                unchecked {
                    ++i;
                }
            }
        } else if (payoutAmount > totalStaked && payoutAmount <= poolTotal) {
            // set all token balances to zero
            uint256 length = pidNFTList[_pid].length;
            for (uint256 i; i < length; ) {
                uint256 tokenId = pidNFTList[_pid][i];
                NFTInfo storage token = nftInfo[tokenId];
                _updateTokenReward(tokenId, false);
                token.amount = 0;
                unchecked {
                    ++i;
                }
            }
            pool.generalInfo.totalStaked = 0;
            delete pool.stakerList;
            // calculate remaining amount for project to pay
            _withdrawFromActiveStrategy(_pid);
            uint256 projectPayout = payoutAmount - totalStaked;
            pool.depositInfo.projectDepositHeld -= projectPayout;
        } else {
            revert("Amount too high");
        }

        // calculate saloon commission
        uint256 saloonCommission = (payoutAmount * bountyFee) / BPS;
        // subtract commission from payout
        uint256 hunterPayout = payoutAmount - saloonCommission;

        // Calculate fee taken from bounty payments. 10% taken from total payment upon payout.
        // Of that 10%, some % might go to referrer of bounty. The rest goes to The Saloon.
        (
            uint256 saloonAmount,
            uint256 referralAmount,
            address referrer
        ) = calcReferralSplit(_pid, saloonCommission);
        address token = address(pool.generalInfo.token);
        _increaseReferralBalance(referrer, token, referralAmount);
        saloonBountyProfit[token] += saloonAmount;

        // transfer payout to hunter
        IERC20(pool.generalInfo.token).safeTransfer(_hunter, hunterPayout);
        uint256 balanceAfter = pool.generalInfo.totalStaked +
            viewMinProjectDeposit(_pid);

        emit BountyPaid(_hunter, address(pool.generalInfo.token), payoutAmount);
        emit BountyBalanceChanged(_pid, poolTotal, balanceAfter);
        return true;
    }

    /// @notice Calculates time passed in seconds from lastClaimedTime to endTime.
    /// @param _from lastClaimedTime
    /// @param _to endTime
    function getSecondsPassed(uint256 _from, uint256 _to)
        public
        pure
        returns (uint256)
    {
        return _to.sub(_from);
    }

    // TODO make into function to view Pending yield to claim
    function pendingPremium(uint256 _tokenId)
        public
        view
        returns (
            uint256 totalPending,
            uint256 actualPending,
            uint256 newPending
        )
    {
        uint256 pid = nftToPid[_tokenId];
        PoolInfo memory pool = poolInfo[pid];
        NFTInfo memory token = nftInfo[_tokenId];

        uint256 endTime = pool.freezeTime != 0
            ? pool.freezeTime
            : block.timestamp;

        // secondsPassed = number of seconds between lastClaimedTime and endTime
        uint256 secondsPassed = getSecondsPassed(
            token.lastClaimedTime,
            endTime
        );
        newPending =
            (((token.amount * token.apy) / BPS) * secondsPassed) /
            YEAR;
        totalPending = newPending + token.unclaimed;
        // actualPending subtracts Saloon premium fee
        actualPending = (totalPending * (BPS - premiumFee)) / BPS;

        // note saloonPremiumProfit variable is updated in billPremium()

        return (totalPending, actualPending, newPending);
    }

    function viewSaloonProfitBalance(address _token)
        public
        view
        returns (
            uint256 totalProfit,
            uint256 bountyProfit,
            uint256 strategyProfit,
            uint256 premiumProfit
        )
    {
        bountyProfit = saloonBountyProfit[_token];
        premiumProfit = saloonPremiumProfit[_token];
        strategyProfit = saloonStrategyProfit[_token];
        totalProfit = premiumProfit + bountyProfit + strategyProfit;
    }

    function viewReferralBalance(address _referrer, address _token)
        public
        view
        returns (uint256 referralBalance)
    {
        referralBalance = referralBalances[_referrer][_token];
    }

    function viewBountyBalance(uint256 _pid) external view returns (uint256) {
        PoolInfo memory pool = poolInfo[_pid];
        return (pool.generalInfo.totalStaked + viewMinProjectDeposit(_pid));
        // note does totalStaked/project deposit take into account saloon fee?
    }

    function viewMinProjectDeposit(uint256 _pid) public view returns (uint256) {
        PoolInfo memory pool = poolInfo[_pid];
        return (pool.depositInfo.projectDepositHeld +
            pool.depositInfo.projectDepositInStrategy);
        // note Certain strategies like Stargate return 1 wei less than deposited if withdrawn immediately.
        // We subtract 1 wei to prevent the edge case of underflow when withdrawing deposit or paying bounty.
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

    function viewTokenInfo(uint256 _tokenId)
        external
        view
        returns (
            uint256 amount,
            uint256 apy,
            uint256 actualPending,
            uint256 unclaimed,
            uint256 timelock
        )
    {
        uint256 pid = nftToPid[_tokenId];
        NFTInfo memory token = nftInfo[_tokenId];
        amount = token.amount;
        apy = token.apy;
        (, actualPending, ) = pendingPremium(_tokenId);
        unclaimed = token.unclaimed;
        timelock = token.timelock;
    }

    function viewUserUnclaimed(uint256 _tokenId)
        external
        view
        returns (uint256 unclaimed)
    {
        NFTInfo storage token = nftInfo[_tokenId];
        unclaimed = token.unclaimed;
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

        requiredPremiumBalancePerPeriod = calcRequiredPremiumBalancePerPeriod(
            pool.generalInfo.poolCap,
            pool.generalInfo.apy
        );
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
            ((pool.generalInfo.totalStaked +
                pool.depositInfo.projectDepositHeld) * (BPS - bountyFee)) / BPS;
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

    function calcRequiredPremiumBalancePerPeriod(uint256 _poolCap, uint256 _apy)
        public
        pure
        returns (uint256 requiredPremiumBalance)
    {
        return (((_poolCap * _apy * PERIOD) / BPS) / YEAR);
    }

    function calcReferralSplit(uint256 _pid, uint256 _totalAmount)
        public
        view
        returns (
            uint256,
            uint256,
            address
        )
    {
        PoolInfo memory pool = poolInfo[_pid];
        address referrer = pool.referralInfo.referrer;
        uint256 endTime = pool.referralInfo.endTime;
        if (referrer == address(0) || endTime < block.timestamp) {
            return (_totalAmount, 0, referrer);
        } else {
            uint256 referralAmount = (_totalAmount *
                pool.referralInfo.referralFee) / BPS;
            uint256 saloonAmount = _totalAmount - referralAmount;
            return (saloonAmount, referralAmount, referrer);
        }
    }
}
