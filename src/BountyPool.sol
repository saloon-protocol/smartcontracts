//SPDX-License-Identifier: MIT
pragma solidity 0.8.10;
import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import "openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";

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
    uint256 public APYPaymentPerPeriodSplit = 24; // maybe change where this is used so only poolPremiumPaymentPeriod is necessary.
    uint256 public poolPremiumPaymentPeriod = 2 weeks;

    // staker => last time premium was claimed
    mapping(address => uint256) public lastClaimed;

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
    function setDesiredAPY(uint256 _desiredAPY)
        external
        onlyManager
        returns (bool)
    {
        // make sure APY has right amount of decimals

        // ensure there is enough premium balance to pay stakers new APY for a month
        uint256 currentPremiumBalance = premiumBalance;
        uint256 newRequiredPremiumBalancePerPeriod = (poolCap / _desiredAPY) /
            APYPaymentPerPeriodSplit;
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

        // if APY is decreased and value is higher than needed, project gets a refund.
        if (currentPremiumBalance > newRequiredPremiumBalancePerPeriod) {
            // calculate difference to be paid
            uint256 difference = currentPremiumBalance -
                newRequiredPremiumBalancePerPeriod;
            // transfer to this address
            token.safeTransfe(projectWallet, difference);
            // decrease premium
            premiumBalance -= difference;
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
    // Current issue: if function doesnt get called in a month, premiuns wont be paid for that month.
    // could fix it to pay retroactively seeing how long since last time it has been paid... but seems like a waist of gas
    // we should be calling this every month in the manager collectPremiumForAll() function
    function payPremium() external onlyManager returns (bool) {
        uint256 currentPremiumBalance = premiumBalance;
        uint256 minimumRequiredBalance = requiredPremiumBalancePerPeriod;
        // check if current premium balance is less than required
        if (currentPremiumBalance < minimumRequiredBalance) {
            // if its less try transfer the difference to this address
            // calculate difference
            uint256 difference = minimumRequiredBalance - currentPremiumBalance;
            // try transfer, if it fails, set desired APY as current APY

            if (
                !token.safeTransferFrom(
                    projectWallet,
                    address(this),
                    difference
                )
            ) {
                desiredAPY = currentAPY;

                // update APYperiods
                APYperiods memory newAPYperiod;
                newAPYperiod.timeStamp = block.timestamp;
                newAPYperiod.periodAPY = desiredAPY;

                APYrecords.push(newAPYperiod);

                return false;
            } else {
                // update premiumBalance
                premiumBalance += difference;
            }
        }

        return true;

        // emit event?
        // update last time paid ???
        // lastTimePremiumWasPaid = block.timestamp;
    }

    // PROJECT WITHDRAWAL

    // STAKING
    // dont allow staking if stakerDeposit >= poolCap
    // increase stakerBalance
    // increase stakersDeposit

    // STAKING WITHDRAWAL
    // allow instant withdraw if stakerDeposit >= poolCap
    // otherwise have to wait for timelock period
    // decrease staker balance
    // decrease stakersDeposit

    // claim premium
    function claimPremium() external onlyManager {
        // how many chunks of time (currently = 2 weeks) since lastclaimed?
        lastTimeClaimed = lastClaimed[msg.sender];
        uint256 sinceLastClaimed = block.timestamp - lastTimeClaimed;

        if (sinceLastClaimed > poolPremiumPaymentPeriod) {
            // calculate how many chunks of period have been missed
            // calculate average APY of that time
            ///////////// current solution has to go through all changes in APY, maybe not the most optimal solution.
            // for loop iterating through APY changes and checking
            // if timestamp is >= to lastClaimed:
            // add to sum and divide by total length up until current
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
            // Pay msg.sender balance % of that time
            // update premiumBalance
        } else {}

        // update last time claimed
        lastClaimed[msg.sender] = block.timestamp;

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
