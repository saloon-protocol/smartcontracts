//SPDX-License-Identifier: MIT
pragma solidity 0.8.10;
import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import "openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";

//  OBS: Better suggestions for calculating the APY paid on a fortnightly basis are welcomed.

contract BountyPool is ReentrancyGuard, Ownable {
    //#################### State Variables *****************\\
    address public immutable projectWallet;
    address public immutable manager;
    address public immutable token;

    uint256 public constant VERSION = 1;
    uint256 public constant BOUNTY_COMMISSION = 12 * 1e18;
    uint256 public constant PREMIUM_COMMISSION = 2 * 1e18;
    uint256 public constant DENOMINATOR = 100 * 1e18;
    uint256 public constant YEAR = 365 days;

    uint256 public projectDeposit;
    uint256 public stakersDeposit;
    uint256 public bountyBalance = projectDeposit + stakersDeposit;

    uint256 public saloonBountyCommission =
        (bountyBalance * BOUNTY_COMMISSION) / DENOMINATOR;
    // bountyBalance - % commission
    uint256 public bountyHackerPayout = bountyBalance - saloonBountyCommission;

    uint256 public saloonPremiumFees;
    uint256 public premiumBalance;
    uint256 public currentAPY = premiumBalance / poolCap;
    uint256 public desiredAPY;
    uint256 public poolCap;
    uint256 public lastTimePaid;
    uint256 public requiredPremiumBalancePerPeriod;
    uint256 public poolPeriod = 2 weeks;

    // staker => last time premium was claimed
    mapping(address => uint256) public lastClaimed;
    // staker address => stakerInfo array
    mapping(address => StakerInfo[]) public staker;

    // staker address => amount => timelock time
    mapping(address => mapping(uint256 => uint256)) public stakerTimelock;

    struct StakerInfo {
        uint256 stakerBalance;
        uint256 balanceTimeStamp;
    }

    struct APYperiods {
        uint256 timeStamp;
        uint256 periodAPY;
    }

    APYperiods[] public APYrecords;
    //#################### State Variables End *****************\\

    //#################### Modifiers *****************\\

    modifier onlyManager() {
        require(msg.sender == manager, "Only manager allowed");
        _;
    }

    modifier onlyManagerOrSelf() {
        require(
            msg.sender == manager || msg.sender == address(this),
            "Only manager allowed"
        );
        _;
    }

    //#################### Modifiers *****************\\

    constructor(address _projectWallet, address _manager) {
        projectWallet = _projectWallet;
        manager = _manager;
    }

    ////FUNCTIONS //////

    // ADMIN PAY BOUNTY
    // decrease stakerDeposit
    // descrease project deposit

    // ADMIN HARVEST FEES

    // PROJECT DEPOSIT
    // project must approve this address first.
    function bountyDeposit(uint256 _amount)
        external
        onlyManager
        returns (bool)
    {
        // transfer from project account
        token.safeTransferFrom(projectWallet, address(this), _amount);

        // update deposit variable
        projectDeposit += _amount;

        return true;
    }

    // PROJECT SET CAP
    function setPoolCap(uint256 _amount) external onlyManager {
        // two weeks time lock?
        poolCap = _amount;
    }

    // PROJECT SET APY
    // project must approve this address first.
    // project will have to pay upfront cost of full period on the first time.
    // this will serve two purposes:
    // 1. sign of good faith and working payment system
    // 2. if theres is ever a problem with payment the initial premium deposit can be used as a buffer so users can still be paid while issue is fixed.
    function setDesiredAPY(uint256 _desiredAPY)
        external
        onlyManager
        returns (bool)
    {
        // make sure APY has right amount of decimals (1e18)

        // ensure there is enough premium balance to pay stakers new APY for a month
        uint256 currentPremiumBalance = premiumBalance;
        uint256 newRequiredPremiumBalancePerPeriod = ((poolCap * _desiredAPY) /
            YEAR) * poolPeriod;
        // this might lead to leftover premium if project decreases APY, we will see what to do about that later
        if (currentPremiumBalance < newRequiredPremiumBalancePerPeriod) {
            // calculate difference to be paid
            uint256 difference = newRequiredPremiumBalancePerPeriod -
                currentPremiumBalance;
            // transfer to this address
            token.safeTransferFrom(projectWallet, address(this), difference);
            // increase premium
            premiumBalance += difference;
        }

        requiredPremiumBalancePerPeriod = newRequiredPremiumBalancePerPeriod;

        // register new APYperiod
        APYperiods memory newAPYperiod;
        newAPYperiod.timeStamp = block.timestamp;
        newAPYperiod.periodAPY = _desiredAPY;
        APYrecords.push(newAPYperiod);

        // set APY
        desiredAPY = _desiredAPY;

        return true;
    }

    // PROJECT PAY weekly/monthly PREMIUM to this address
    // this address needs to be approved first
    function payFortnightlyPremium() public onlyManagerOrSelf returns (bool) {
        uint256 currentPremiumBalance = premiumBalance;
        uint256 minimumRequiredBalance = requiredPremiumBalancePerPeriod;
        // check if current premium balance is less than required
        if (currentPremiumBalance < minimumRequiredBalance) {
            uint256 lastPaid = lastTimePaid;
            uint256 paymentPeriod = poolPeriod;

            // check when function was called last time and pay premium according to how much time has passed since then.
            uint256 sinceLastPaid = block.timestamp - lastPaid;

            if (sinceLastPaid > poolPeriod) {
                // multiple by `sinceLastPaid` instead of two weeks
                uint256 fortnightlyPremiumOwed = ((
                    ((stakersDeposit * desiredAPY) / DENOMINATOR)
                ) / YEAR) * sinceLastPaid;

                token.safeTransferFrom(projectWallet, fortnightlyPremiumOwed); // Pay
                // Calculate saloon fee
                uint256 saloonFee = (fortnightlyPremiumOwed *
                    PREMIUM_COMMISSION) / DENOMINATOR;

                // update saloon claimable fee
                saloonPremiumFees += saloonFee;

                // update premiumBalance
                premiumBalance += fortnightlyPremiumOwed;

                //TODO if premium isnt paid, reset APY

                lastTimePaid = block.timestamp;

                return true;
            } else {
                uint256 fortnightlyPremiumOwed = (((stakersDeposit *
                    desiredAPY) / DENOMINATOR) / YEAR) * poolPeriod;

                token.safeTransferFrom(
                    projectWallet,
                    address(this),
                    fortnightlyPremiumOwed
                );

                // Calculate saloon fee
                uint256 saloonFee = (fortnightlyPremiumOwed *
                    PREMIUM_COMMISSION) / DENOMINATOR;

                // update saloon claimable fee
                saloonPremiumFees += saloonFee;

                // update premiumBalance
                premiumBalance += fortnightlyPremiumOwed;

                //TODO if premium isnt paid, reset APY

                lastTimePaid = block.timestamp;

                return true;
            }
        }
        return false;
    }

    // PROJECT EXCESS PREMIUM BALANCE WITHDRAWAL -- NOT SURE IF SHOULD IMPLEMENT THIS
    // timelock on this?

    // PROJECT DEPOSIT WITHDRAWAL
    // timelock on this.

    // STAKING
    // staker needs to approve this address first
    function stake(address _staker, uint256 _amount)
        external
        onlyManager
        nonReentrant
        returns (bool)
    {
        // dont allow staking if stakerDeposit >= poolCap
        require(stakersDeposit >= poolCap, "Staking Pool already full");

        // update stakerInfo struct
        StakerInfo memory newInfo;
        newInfo.balanceTimeStamp = block.timestamp;
        newInfo.stakerBalance = staker[_staker][-1].stakerBalance + _amount;

        // save info to storage
        staker[_staker].push(newInfo);

        // increase global stakersDeposit
        stakersDeposit += _amount;

        // transferFrom to this address
        token.safeTransferFrom(_staker, address(this), _amount);

        return true;
    }

    function askForUnstake(address _staker, uint256 _amount)
        external
        onlyManager
    {
        stakerTimeLock[_staker][_amount] = block.timestamp;

        // TODO emit event -> necessary to predict payout payment in the following week
    }

    // UNSTAKING
    // allow instant withdraw if stakerDeposit >= poolCap or APY = 0%
    // otherwise have to wait for timelock period
    function unstake(address _staker, uint256 _amount)
        external
        onlyManager
        nonReentrant
        returns (bool)
    {
        if (desiredAPY != 0) {
            require(
                stakerTimelock[_staker][_amount] + poolPeriod < block.timestamp,
                "Timelock not finished or started"
            );

            // decrease staker balance
            // update stakerInfo struct
            StakerInfo memory newInfo;
            newInfo.balanceTimeStamp = block.timestamp;
            newInfo.stakerBalance = staker[_staker][-1].stakerBalance - _amount;

            // save info to storage
            staker[_staker].push(newInfo);

            // decrease global stakersDeposit
            stakersDeposit -= _amount;

            // transfer it out
            token.safeTransfer(_staker, _amount);

            return true;
        }
    }

    // claim premium
    function claimPremium(address _staker) external onlyManager nonReentrant {
        // how many chunks of time (currently = 2 weeks) since lastclaimed?
        lastTimeClaimed = lastClaimed[_staker];
        uint256 sinceLastClaimed = block.timestamp - lastTimeClaimed;
        uint256 paymentPeriod = poolPeriod;
        StakerInfo[] memory stakerInfo = staker[_staker];
        // if last time premium was called > 1 period

        if (sinceLastClaimed > paymentPeriod) {
            uint256 length = APYrecords.length();
            // loop through APY periods (reversely) until last missed period is found
            uint256 lastMissed;
            uint256 totalPremiumToClaim;
            for (uint256 i = length - 1; i == 0; --i) {
                if (APYrecords.timeStamp[i] < lastTimeClaimed) {
                    lastMissed = i + 1;
                }
            }
            // loop through all missed periods
            for (uint256 i = lastMissed; i < length; ++i) {
                uint256 periodStart = APYrecords[i].timeStamp;
                // period end end is equal NOW for last APY that has been set
                uint256 periodEnd = APYrecords[i + 1].timeStamp != 0
                    ? APYrecords[i + 1].timeStamp
                    : block.timestamp;
                uint256 periodLength = periodEnd - periodStart;
                // loop through stakers balance fluctiation during this period

                uint256 stakerLength = stakerInfo.length();
                uint256 periodTotalBalance;
                for (uint256 j; j < stakerLength; ++j) {
                    // check staker balance at that moment
                    if (
                        stakerInfo[j].balanceTimeStamp > periodStart &&
                        stakerInfo[j].balanceTimeStamp < periodEnd
                    ) {
                        // add it to that period total
                        periodTotalBalance += stakerInfo[j].stakerBalance;
                    }
                }

                //calcualte owed APY for that period: (APY * amount / Seconds in a year) * number of seconds in X period
                totalPremiumToClaim +=
                    (((periodTotalBalance * desiredAPY) / DENOMINATOR) / YEAR) *
                    periodLength;
            }
            // Calculate saloon fee
            uint256 saloonFee = (totalPremiumToClaim * PREMIUM_COMMISSION) /
                DENOMINATOR;
            // subtract saloon fee
            totalPremiumToClaim -= saloonFee;
            token.safeTransfer(_staker, totalPremiumToClaim);
            // TODO if transfer fails call payPremium

            // update premiumBalance
            premiumBalance -= totalPremiumToClaim;

            // update last time claimed
            lastClaimed[_staker] = block.timestamp;
            return true;
        } else {
            // calculate currently owed for the week

            uint256 owedPremium = (((stakerInfo[-1].stakerBalance *
                desiredAPY) / DENOMINATOR) / YEAR) * poolPeriod;
            // pay current period owed

            // Calculate saloon fee
            uint256 saloonFee = (owedPremium * PREMIUM_COMMISSION) /
                DENOMINATOR;
            // subtract saloon fee
            owedPremium -= saloonFee;

            token.safeTransfer(_staker, owedPremium);
            // TODO if transfer fails call payPremium

            // update premium
            premiumBalance -= owedPremium;

            // update last time claimed
            lastClaimed[_staker] = block.timestamp;
            return true;
        }

        return false;
    }

    ///// VIEW FUNCTIONS /////

    // View total balance
    // View stakersDeposit balance
    // View deposit balance
    // view premium balance
    // view required premium balance
    // View APY
    // View Cap
    // View user staking balance

    ///// VIEW FUNCTIONS END /////
}
