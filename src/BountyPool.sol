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

    uint256 public projectDeposit;
    uint256 public stakersDeposit;
    uint256 public premiumBalance;
    uint256 public bountyBalance = projectDeposit + stakersDeposit;
    // bountyBalance - % commission
    uint256 public bountyPayout = bountyBalance - saloonCommission;
    uint256 public saloonCommission = (bountyBalance / commissionRate);
    uint256 public commissionRate = 12; // 12% ?
    uint256 public currentAPY = premiumBalance / poolCap;
    uint256 public desiredAPY;
    uint256 public poolCap;
    uint256 public lastTimePremiumWasPaid;
    uint256 public requiredPremiumBalancePerPeriod;
    // Total APY % divided per fortnight.
    uint256 public fortnightlyAPYSplit = 24; // maybe change where this is used so only poolPremiumPaymentPeriod is necessary.
    uint256 public poolPremiumPaymentPeriod = 2 weeks;

    // staker => last time premium was claimed
    mapping(address => uint256) public lastClaimed;
    // staker address => staker balance
    mapping(address => uint256) public stakerBalance;

    struct APYperiods {
        uint256 timeStamp;
        uint256 periodAPY;
    }

    APYperiods public APYrecords;
    //#################### State Variables End *****************\\

    //#################### Modifiers *****************\\

    modifier onlyManager() {
        require(msg.sender == manager, "Only manager allowed");
        _;
    }

    //#################### Modifiers *****************\\

    constructor(address _projectWallet, address _manager) {
        projectWallet = _projectWallet;
        manager = _manager;
    }

    ////FUNCTIONS //////

    // ADMIN WITHDRAWAL

    // PROJECT DEPOSIT
    // project must approve this address first.
    function bountyDeposit(uint256 _amount)
        external
        onlyManager
        returns (bool)
    {
        // transfer from project account
        token.safetransferFrom(projectWallet, address(this), _amount);

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
        // make sure APY has right amount of decimals

        // ensure there is enough premium balance to pay stakers new APY for a month
        uint256 currentPremiumBalance = premiumBalance;
        uint256 newRequiredPremiumBalancePerPeriod = (poolCap / _desiredAPY) /
            fortnightlyAPYSplit;
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
    function payFortnightlyPremium() external onlyManager returns (bool) {
        // TODO make sure function can only be called once every two weeks
        // TODO check when function was called last time and pay premium according to how much time has passed since then.
        fortnightlyPremiumOwed =
            (stakersDeposit / desiredAPY) /
            fortnightlyAPYSplit;

        token.safeTransferFrom(
            projectWallet,
            address(this),
            fortnightlyPremiumOwed
        );

        return true;
    }

    // PROJECT WITHDRAWAL

    // STAKING
    // staker needs to approve this address first
    function stake(address _staker, uint256 _amount) external onlyManager {
        // dont allow staking if stakerDeposit >= poolCap
        require(stakersDeposit >= poolCap, "Staking Pool already full");
        // transferFrom to this address
        // increase stakerBalance
        stakerBalance[_staker] += _amount;
        // increase stakersDeposit
        stakersDeposit += _amount;
    }

    // STAKING WITHDRAWAL
    // allow instant withdraw if stakerDeposit >= poolCap or APY = 0%
    // otherwise have to wait for timelock period
    // decrease staker balance
    // decrease stakersDeposit

    // claim premium
    function claimPremium(address _staker) external onlyManager nonReentrant {
        // how many chunks of time (currently = 2 weeks) since lastclaimed?
        lastTimeClaimed = lastClaimed[_staker];
        uint256 sinceLastClaimed = block.timestamp - lastTimeClaimed;
        uint256 paymentPeriod = poolPremiumPaymentPeriod;
        if (sinceLastClaimed > paymentPeriod) {
            // calculate how many chunks of period have been missed
            timeChuncks = sinceLastClaimed / paymentPeriod;
            // calculate average APY of that time
            ///////////// current solution has to go through all changes in APY, maybe not the most optimal solution.
            uint256 APYsum;
            uint256 count;
            for (i; i < APYrecords.length(); ++i) {
                if (APYrecords.timeStamp >= lastTimeClaimed) {
                    APYsum += APYrecords.periodAPY;
                    count += 1;
                }
            }
            uint256 APYaverage = APYsum / count;
            ////////////

            // Caculate owedPremium times how many periods were missed
            uint256 owedPremium = ((stakerBalance[_staker] / APYaverage) /
                fortnightlyAPYSplit) * timeChuncks;

            // Pay
            // TODO if transfer fails update APY to 0%
            token.safeTransfer(_staker, owedPremium);

            // update premiumBalance
            premiumBalance -= owedPremium;
        } else {
            // calculate currently owed for the week
            uint256 owedPremium = (stakerBalance[_staker] / desiredAPY) /
                fortnightlyAPYSplit;
            // pay current period owed
            // TODO if transfer fails update APY to 0%
            token.safeTransfer(_staker, owedPremium);
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
