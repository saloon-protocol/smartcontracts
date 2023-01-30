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
- TODO Integrate keeping track of owed rewards when transferring BountyTokens between users
- TODO Integrate minting and burning of tokens in staking and unstaking
- TEST event emissions
import "./interfaces/ISaloon.sol";
import "./interfaces/IStrategy.sol";
import "./StrategyFactory.sol";

/// Make sure accounting references deposits and stakings separately and never uses address(this) as reference
/// Ensure there is enough access control

/* Implement:
- DONE implement stargate strategy
- TODO makeProjectDeposit BountyBalanceChanged Event
- TODO Fill in missing events
- DONE add token whitelisting
- TEST event emissions
- DONE Saloon collect all profits
- DONE Wind down (kill) bounties
- DONE Withdrawals with _shouldHarvest == false
- DONE Ownership transfer
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
    // Info of each user.
    //NOTE This might need to be changed because stakerBalance has been introduced in BountyToken

    StrategyFactory strategyFactory;

    // Mapping of all strategies for pid
    mapping(uint256 => mapping(bytes32 => address)) public pidStrategies;

    // Mapping of active strategy for pid
    mapping(uint256 => bytes32) public activeStrategies;

    // Mapping of whitelisted tokens
    mapping(address => bool) public tokenWhitelist;
    // Mapping of whitelisted tokens
    address[] public activeTokens;

    mapping(address => uint256) public minTokenStakeAmount;

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

    function updateTokenWhitelist(
        address _token,
        bool _whitelisted,
        uint256 _minStakeAmount
    ) external onlyOwner returns (bool) {
        require(
            tokenWhitelist[_token] == !_whitelisted || _whitelisted == false,
            "whitelist already set"
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
        newBounty.generalInfo.apy = 0;
        newBounty.generalInfo.poolCap = 0;
        newBounty.generalInfo.multiplier = 0;
        newBounty.generalInfo.totalStaked = 0;
        newBounty.depositInfo.projectDepositHeld = 0;
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

    function billPremium(uint256 _pid) public onlyOwner returns (bool) {
        _billPremium(_pid, 0);
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

    ///////////////////////////////////////////////////////////////////////////////
    /////////////////////////// STRATEGY MANAGEMENT ///////////////////////////////
    ///////////////////////////////////////////////////////////////////////////////

    function updateStrategyFactoryAddress(address _strategyFactory)
        external
        onlyOwner
    {
        strategyFactory = StrategyFactory(_strategyFactory);
    }

    function deployStrategyIfNeeded(uint256 _pid, string memory _strategyName)
        internal
        returns (address)
    {
        address deployedStrategy;
        bytes32 strategyHash = keccak256(abi.encode(_strategyName));
        address pidStrategy = pidStrategies[_pid][strategyHash];
        if (pidStrategy == address(0)) {
            deployedStrategy = strategyFactory.deployStrategy(_strategyName);
        } else {
            return pidStrategy;
        }

        if (deployedStrategy == address(0)) {
            return address(0);
        } else {
            pidStrategies[_pid][strategyHash] = deployedStrategy;
            activeStrategies[_pid] = strategyHash;
        }

        return deployedStrategy;
    }

    function withdrawFromActiveStrategy(uint256 _pid)
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
                1,
                activeStrategyLPDepositBalance
            );
            pool.depositInfo.projectDepositHeld += fundsWithdrawn;
        }

        return fundsWithdrawn;
    }

    // Function to handle deploying new strategy, switching strategies, depositing to strategy
    function handleStrategyDeposit(
        uint256 _pid,
        string memory _strategyName,
        uint256 _newDeposit
    ) internal returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];

        bytes32 _strategyHash = keccak256(abi.encode(_strategyName));
        bytes32 activeStrategyHash = activeStrategies[_pid];
        if (activeStrategyHash != _strategyHash) {
            uint256 fundsWithdrawn = withdrawFromActiveStrategy(_pid);
            address deployedStrategy = deployStrategyIfNeeded(
                _pid,
                _strategyName
            );
            if (deployedStrategy != address(0)) {
                IStrategy strategy = IStrategy(deployedStrategy);
                pool.depositInfo.projectDepositHeld -=
                    _newDeposit +
                    fundsWithdrawn;
                pool.depositInfo.projectDepositInStrategy +=
                    _newDeposit +
                    fundsWithdrawn;
                IERC20(pool.generalInfo.token).safeTransfer(
                    deployedStrategy,
                    _newDeposit + fundsWithdrawn
                );
                strategy.depositToStrategy(1); // This is stargate USDC pool hardcode
            } else {
                pool.depositInfo.projectDepositHeld += _newDeposit;
            }
        }
    }

    ///////////////////////////////////////////////////////////////////////////////
    /////////////////////////// PROJECT OWNER FUNCTIONS ///////////////////////////
    ///////////////////////////////////////////////////////////////////////////////

    //todo change order of names to match inputs
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

        updateMultiplier(_pid, _apy);

        if (bytes(_strategyName).length > 0) {
            handleStrategyDeposit(_pid, _strategyName, _deposit);
        }
    }

    function makeProjectDeposit(
        uint256 _pid,
        uint256 _deposit,
        string memory _strategyName
    ) external {
        PoolInfo storage pool = poolInfo[_pid];
        require(msg.sender == pool.generalInfo.projectWallet, "Not authorized");

        uint256 balanceBefore = pool.generalInfo.totalStaked +
            pool.depositInfo.projectDepositHeld;
        IERC20(pool.generalInfo.token).safeTransferFrom(
            msg.sender,
            address(this),
            _deposit
        );
        pool.depositInfo.projectDepositHeld += _deposit;
        uint256 balanceAfter = pool.generalInfo.totalStaked +
            pool.depositInfo.projectDepositHeld;

        handleStrategyDeposit(_pid, _strategyName, _deposit);
    }

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
            withdrawFromActiveStrategy(_pid);

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

    // Stake tokens in a Bounty pool to earn premium payments.
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
            pool.depositInfo.projectDepositHeld;

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
            pool.depositInfo.projectDepositHeld;
        emit BountyBalanceChanged(_pid, balanceBefore, balanceAfter);

        return tokenId;
    }

    /// Schedule unstake with specific amount
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

    // Withdraw LP tokens from MasterChef.
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
        pool.tokenInfo.needsConsolidation = true;

        return true;
    }

    function _updateTokenReward(uint256 _tokenId, bool _shouldHarvest)
        internal
    {
        uint256 pid = nftToPid[_tokenId];
        PoolInfo storage pool = poolInfo[pid];
        NFTInfo storage token = nftInfo[_tokenId];

        // if (token.amount == 0 && token.unclaimed == 0) {
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

    // CONSOLIDATION
    function consolidate() external {
        // loop through the unstakes (where are the gaps).
        //              How do we get the unstakes (most recently burnt nfts)?
        //              - Have array with burnt tokenIds, sort it out from lowest to biggest.
        //      calcualte what is the new x-axis positions and shift all to the left. Repeat until no more gaps
        // calculate how much APY NFTs should have according to their new position in x-axis
        // empty burnt tokens array
        //  OR
        // When unstake occurs all positions are moved to the left and consolidate() only calculates their new APY
    }

    // Harvest one pool
    function claimPremium(uint256 _tokenId) external nonReentrant {
        // Intentionally allow non-owners to claim for token
        _updateTokenReward(_tokenId, true);
    }

    ///////////////////////////////////////////////////////////////////////////////
    /////////////////////////// INTERNAL FUNCTIONS ////////////////////////////////
    ///////////////////////////////////////////////////////////////////////////////

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
        uint256 poolTotal = totalStaked + viewMinProjectDeposit(_pid);
        uint256 balanceBefore = poolTotal;

        // if stakers can cover payout
        if (_amount <= totalStaked) {
            if (_amount == totalStaked) {
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
            } else {
                uint256 percentage = ((_amount * PRECISION) / totalStaked);
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
            }
            // if stakers alone cannot cover payout
        } else if (_amount > totalStaked && _amount <= poolTotal) {
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
            withdrawFromActiveStrategy(_pid);
            uint256 projectPayout = _amount - totalStaked;
            pool.depositInfo.projectDepositHeld -= projectPayout;

            // I believe the following condition is unnecessary
            //
            // } else if (_amount == poolTotal) {
            //     // set all staker balances to zero
            //     uint256 length = pool.stakerList.length;
            //     for (uint256 i; i < length; ) {
            //         address _user = pool.stakerList[i];
            //         NFTInfo storage user = nftInfo[_user];
            //         _updateTokenReward(_tokenId, false);
            //         user.amount = 0;
            //         unchecked {
            //             ++i;
            //         }
            //     }
            //     pool.generalInfo.totalStaked = 0;
            //     delete pool.stakerList;
            //     withdrawFromActiveStrategy(_pid);
            //     pool.depositInfo.projectDepositHeld = 0;
        } else {
            revert("Amount too high");
        }

        // calculate saloon commission
        uint256 saloonCommission = (_amount * bountyFee) / BPS;
        // subtract commission from payout
        uint256 hunterPayout = _amount - saloonCommission;
        // update saloon Commission variable
        saloonBountyProfit[address(pool.generalInfo.token)] += saloonCommission;
        // transfer payout to hunteI
        IERC20(pool.generalInfo.token).safeTransfer(_hunter, hunterPayout);
        uint256 balanceAfter = pool.generalInfo.totalStaked +
            viewMinProjectDeposit(_pid);

        emit BountyPaid(
            block.timestamp,
            _hunter,
            address(pool.generalInfo.token),
            _amount
        );
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

        // multiplier = number of seconds
        uint256 multiplier = getMultiplier(token.lastClaimedTime, endTime);
        newPending = (((token.amount * token.apy) / BPS) * multiplier) / YEAR;
        totalPending = newPending + token.unclaimed;
        // actualPending subtracts Saloon premium fee
        actualPending = (totalPending * (BPS - premiumFee)) / BPS;

        // note saloonPremiumProfit variable is updated in billPremium()

        return (totalPending, actualPending, newPending);
    }

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
        return (pool.generalInfo.totalStaked + viewMinProjectDeposit(_pid));
        // note does totalStaked/project deposit take into account saloon fee?
    }

    function viewMinProjectDeposit(uint256 _pid) public view returns (uint256) {
        PoolInfo memory pool = poolInfo[_pid];
        return (pool.depositInfo.projectDepositHeld +
            pool.depositInfo.projectDepositInStrategy);
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
}
