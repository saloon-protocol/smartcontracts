// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.7.0) (proxy/ERC1967/ERC1967Proxy.sol)

pragma solidity ^0.8.17;

import "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Upgrade.sol";
import "openzeppelin-contracts/contracts/proxy/Proxy.sol";
import "./lib/OwnableUpgradeable.sol";

/**
 * @dev This contract implements an upgradeable proxy. It is upgradeable because calls are delegated to an
 * implementation address that can be changed. This address is stored in storage in the location specified by
 * https://eips.ethereum.org/EIPS/eip-1967[EIP1967], so that it doesn't conflict with the storage layout of the
 * implementation behind the proxy.
 */
contract SaloonProxy is Proxy, ERC1967Upgrade {
    /**
     * @dev Initializes the upgradeable proxy with an initial implementation specified by `_logic`.
     *
     * If `_data` is nonempty, it's used as data in a delegate call to `_logic`. This will typically be an encoded
     * function call, and allows initializing the storage of the proxy like a Solidity constructor.
     */
    constructor(address _logic, bytes memory _data) payable {
        _upgradeToAndCall(_logic, _data, false);
        // _changeAdmin(_admin);
    }

    /**
     * @dev Returns the current implementation address.
     */
    function _implementation()
        internal
        view
        virtual
        override
        returns (address impl)
    {
        return ERC1967Upgrade._getImplementation();
    }

    //===========================================================================||
    //                               MANAGER                                     ||
    //===========================================================================||
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
    ) external returns (bool) {}

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
    ) external returns (uint256) {}

    /// @notice Extend the referral period for the bounty. The new end time can only be larger than the current value.
    /// @param _pid The pool id for the bounty
    /// @param _endTime The new end time for the referral bonus
    function extendReferralPeriod(uint256 _pid, uint256 _endTime) external {}

    function billPremium(uint256 _pid) public returns (bool) {}

    /// @notice Transfer Saloon profits for a specific token from premiums and bounties collected
    /// @param _token Token address to be transferred
    /// @param _saloonWallet Address where the funds will go to
    function collectSaloonProfits(address _token, address _saloonWallet)
        public
        returns (bool)
    {}

    /// @notice Transfer Saloon profits for all tokens from premiums and bounties collected
    /// @param _saloonWallet Address where the funds will go to
    function collectAllSaloonProfits(address _saloonWallet)
        external
        returns (bool)
    {}

    /// @notice Allows referrers to collect their profit from all bounties for one token
    /// @param _token Token used by the bounty that was referred
    function collectReferralProfit(address _token) public returns (bool) {}

    /// @notice Allows referrers to collect their profit from all bounties for all tokens
    function collectAllReferralProfits() external returns (bool) {}

    function viewBountyBalance(uint256 _pid) public view returns (uint256) {}

    //===========================================================================||
    //                               BOUNTY                                      ||
    //===========================================================================||

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
    ) public {}

    /// @notice Stake tokens in a Bounty pool to earn premium payments.
    /// @param _pid Bounty pool id
    /// @param _amount Amount to be staked
    function stake(uint256 _pid, uint256 _amount) external {}

    /// @notice Schedule unstake with specific amount
    /// @dev must be unstaked within a certain time window after scheduled
    /// @param _tokenId Token Id of ERC721 being unstaked
    function scheduleUnstake(uint256 _tokenId) external returns (bool) {}

    /// @notice Unstake scheduled tokenId
    /// @param _tokenId Token Id of ERC721 being unstaked
    /// @param _shouldHarvest Whether staker wants to claim their owed premium or not
    function unstake(uint256 _tokenId, bool _shouldHarvest)
        external
        returns (bool)
    {}

    /// @notice Claims premium for specified tokenId
    /// @param _tokenId Token Id of ERC721
    function claimPremium(uint256 _tokenId) external {}

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
    ) public view returns (uint256 scaledAPY) {}

    /// @notice Processes unstakes and calculates new APY for remaining stakers of a specific pool
    /// @param _pid Bounty pool id
    function consolidate(uint256 _pid) public {}

    /// @notice Processes unstakes and calculates new APY for remaining stakers for all pools
    function consolidateAll() external {}

    //===========================================================================||
    //                            PROJECT PORTAL                                 ||
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
    ) external {}

    /// @notice Makes a deposit that will serve as bounty payout
    /// @dev Only callable by projectWallet
    /// @param _pid Bounty pool id
    /// @param _deposit Amount to be deposited
    /// @param _strategyName Name of the strategy where deposit will go to
    function makeProjectDeposit(
        uint256 _pid,
        uint256 _deposit,
        string memory _strategyName
    ) external {}

    /// @notice Schedules withdrawal for a project deposit
    /// @dev withdrawal must be made within a certain time window
    /// @param _pid Bounty pool id
    /// @param _amount Amount to withdraw
    function scheduleProjectDepositWithdrawal(uint256 _pid, uint256 _amount)
        external
        returns (bool)
    {}

    /// @notice Completes scheduled withdrawal
    /// @param _pid Bounty pool id
    /// @param _amount Amount to withdraw (must be equal to amount scheduled)
    function projectDepositWithdrawal(uint256 _pid, uint256 _amount)
        external
        returns (bool)
    {}

    function withdrawProjectYield(uint256 _pid)
        external
        returns (uint256 returnedAmount)
    {}

    /// @notice Deactivates pool
    /// @param _pid Bounty pool id
    function windDownBounty(uint256 _pid) external returns (bool) {}

    /// @notice Updates the pool's project wallet address
    /// @param _pid Bounty pool id
    /// @param _projectWallet The new project wallet
    function updateProjectWalletAddress(uint256 _pid, address _projectWallet)
        external
    {}

    /// @notice Callback function from strategies upon converting yield to underlying
    /// @dev Anyone can call this but will result in lost funds for non-strategies. TODO ADD MODIFIER TO THIS?
    /// - Tokens are transferred from msg.sender to this contract and saloonStrategyProfit and/or
    ///   referralBalances are incremented.
    /// @param _token Token being received
    /// @param _amount Amount being received
    function receiveStrategyYield(address _token, uint256 _amount) external {}

    /// @notice Harvest pending yield from active strategy for single pid and reinvest
    /// @param _pid Pool id whose strategy should be compounded
    function compoundYieldForPid(uint256 _pid) public {}
}
