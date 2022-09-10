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

    // ADMIN WITHDRAWAL
    // decrease stakerDeposit
    // descrease project deposit

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
    // this address needs to be approved
    // base this off stakersDeposit
    function payFortnightlyPremium() public onlyManagerOrSelf returns (bool) {
        uint256 currentPremiumBalance = premiumBalance;
        uint256 minimumRequiredBalance = requiredPremiumBalancePerPeriod;
        // check if current premium balance is less than required
        if (currentPremiumBalance < minimumRequiredBalance) {
            uint256 lastPaid = lastTimePaid;
            uint256 paymentPeriod = poolPeriod;

            // check when function was called last time and pay premium according to how much time has passed since then.
            uint256 sinceLastPaid = block.timestamp - lastPaid;

            // calculate how many chunks of period have been missed
            uint256 timeChuncks = sinceLastClaimed / paymentPeriod;
            if (sinceLastPaid > poolPeriod) {
                // NOTE This part is not needed as everytime APY is changed the premium balance is already topped up
                // // calculate average APY of that time
                // ///////////// current solution has to go through all changes in APY, maybe not the most optimal solution.
                // uint256 APYsum;
                // uint256 count;
                // for (i; i < APYrecords.length(); ++i) {
                //     if (APYrecords.timeStamp >= lastPaid) {
                //         APYsum += APYrecords.periodAPY;
                //         count += 1;
                //     }
                // }
                // uint256 APYaverage = APYsum / count;

                // // can be paid for the right values in the past.
                // fortnightlyPremiumOwed =
                //     ((poolcap / APYaverage) / fortnightlyPremiumOwed) *
                //     timeChuncks;

                // Pay
                token.safeTransferFrom(projectWallet, fortnightlyPremiumOwed);

                // update premiumBalance
                premiumBalance += fortnightlyPremiumOwed;
            } else {
                fortnightlyPremiumOwed =
                    (stakersDeposit / desiredAPY) /
                    fortnightlyAPYSplit;

                token.safeTransferFrom(
                    projectWallet,
                    address(this),
                    fortnightlyPremiumOwed
                );
            }
        }
        // TODO Calculate saloon  fee
        // TODO subbstract saloon fee
        // TODO update saloon claimable fee
        //TODO if premium isnt paid, reset APY

        lastTimePaid = block.timestamp;

        return true;
    }

    // PROJECT WITHDRAWAL
    // timelock on this.

    // STAKING
    // staker needs to approve this address first
    function stake(address _staker, uint256 _amount)
        external
        onlyManager
        nonReentrant
    {
        // dont allow staking if stakerDeposit >= poolCap
        require(stakersDeposit >= poolCap, "Staking Pool already full");
        // TODO transferFrom to this address

        // update stakerInfo struct
        StakerInfo memory newInfo;
        newInfo.balanceTimeStamp = block.timestamp;
        newInfo.stakerBalance = staker[_staker][-1].stakerBalance + _amount;

        // save info to storage
        staker[_staker].push(newInfo);

        // increase global stakersDeposit
        stakersDeposit += _amount;
    }

    // TODO UNSTAKING
    // allow instant withdraw if stakerDeposit >= poolCap or APY = 0%
    // otherwise have to wait for timelock period
    // decrease staker balance
    // decrease stakersDeposit

    // claim premium
    // TODO doesnt take into account fluctuations in stakers Balance...
    // it uses current balance for all APY periods, however he could have had 10k at 12% and 100k at 2%
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

                //TODO calcualte owed APY for that period: (Balance / APYPerDay) * number of days in that period
                totalPremiumToClaim +=
                    (periodTotalBalance / APYPerDay) *
                    periodLength;
            }
            // TODO Calculate saloon  fee
            // TODO subbstract saloon fee
            // TODO update saloon claimable fee
            token.safeTransfer(_staker, totalPremiumToClaim);
            // TODO if transfer fails call payPremium
            // TODO if payPremium fails update APY to 0%

            // update premiumBalance
            premiumBalance -= totalPremiumToClaim;
        } else {
            // calculate currently owed for the week
            uint256 owedPremium = (stakerInfo[-1].stakerBalance / APYPerDay) *
                poolPeriod;
            // pay current period owed

            // TODO Calculate saloon  fee
            // TODO subbstract saloon fee
            // TODO update saloon claimable fee
            token.safeTransfer(_staker, owedPremium);
            // TODO if transfer fails call payPremium
            // TODO if payPremium fails update APY to 0%

            // update premium
            premiumBalance -= owedPremium;
        }

        // update last time claimed
        lastClaimed[_staker] = block.timestamp;

        return true;
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
