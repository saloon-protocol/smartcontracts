//SPDX-License-Identifier: MIT
pragma solidity 0.8.10;
import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import "openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";

// todo import safe library for openzeppeling safeTransfer()

//  OBS: Better suggestions for calculating the APY paid on a fortnightly basis are welcomed.

contract BountyPool is ReentrancyGuard {
    //#################### State Variables *****************\\
    
    //todo possibly make this a constant
    address public immutable manager;
    

    bool public APYdropped;

    uint256 public constant VERSION = 1;
    uint256 public constant BOUNTY_COMMISSION = 12 * 1e18;
    uint256 public constant PREMIUM_COMMISSION = 2 * 1e18;
    uint256 public constant DENOMINATOR = 100 * 1e18;
    uint256 public constant YEAR = 365 days;

    uint256 public projectDeposit;
    uint256 public stakersDeposit;
    uint256 public bountyBalance = projectDeposit + stakersDeposit;

    // TODO perhaps this is done in the payout address...
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
    // amount => timelock
    mapping(uint256 => uint256) public projectWithdrawalTimeLock;
    // staker => last time premium was claimed
    mapping(address => uint256) public lastClaimed;
    // staker address => stakerInfo array
    mapping(address => StakerInfo[]) public staker;
    address[] public stakerList;
    // staker address => amount => timelock time
    mapping(address => mapping(uint256 => uint256)) public stakerTimelock;

    // NOT NEEDED - proxy address =>
    // mapping(address => uint256) public proxyWhitelist;

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
    // todo maybe make this check at the manager level
    // modifier onlyProxy() {
    //     require(proxyWhitelist[msg.sender] != 0, "Address not whitelisted");
    //     _;
    // }
    //todo  maybe make this check at the manager level
    modifier onlyManagerOrSelf() {
        require(
            msg.sender == manager || msg.sender == address(this),
            "Only manager allowed"
        );
        _;
    }

    //#################### Modifiers END *****************\\

    // TODO Create Init function
    // constructor(address _projectWallet, address _manager) {
    //     projectWallet = _projectWallet;
    //     manager = _manager;
    // }

    //#################### Functions *******************\\

    // NOT NEEDED -  WHITELIST PROXY
    // function updateProxyWhitelist(address _proxy, bool _whitelist)
    //     external
    //     onlyManager
    // {
    //     proxyWhitelist[_proxy] = _whitelist;
    // }

    // ADMIN PAY BOUNTY public
    // this implementation uses investors funds first before project deposit,
    // future implementation might use a more hybrid and sophisticated splitting of costs.
    // todo cache variables to make it more gas effecient
    function payBounty(address _token, address _saloonWallet, address _hunter, uint256 _amount)
        public
        onlyManager
        returns (bool)
    {
        // check if stakersDeposit is enough
        if (stakersDeposit >= _amount) {
            // decrease stakerDeposit
            stakersDeposit -= _amount;
            // if staker deposit == 0
            if (stakersDeposit == 0) {
                for (uint256 i; i < length; ++i) {
                    address stakerAddress = stakerList[i]; //todo cache stakerList before
                    staker[stakerAddress].stakerBalance = 0;
                    staker[stakerAddress].timeStamp = block.timestamp;
                    // clean stakerList array
                    delete stakerList;
                    // transfer  to saloonWallet address
                    _token.safeTransfer(_saloonWallet, _amount);

                    // todo Emit event with timestamp and amount
                    return true;
                }
            }
            // calculate percentage of stakersDeposit
            uint256 percentage = _amount / stakersDeposit;
            // loop through all stakers and deduct percentage from their balances
            uint256 length = stakerList.length;
            for (uint256 i; i < length; ++i) {
                address stakerAddress = stakerList[i]; //todo cache stakerList before
                staker[stakerAddress].stakerBalance =
                    staker[stakerAddress].stakerBalance -
                    ((staker[stakerAddress].stakerBalance * percentage) /
                        DENOMINATOR);
                staker[stakerAddress].timeStamp = block.timestamp;
            }
           
            // transfer to saloon funds address
            _token.safeTransfer(_saloonWallet, _amount);

            // todo Emit event with timestamp and amount

            return true;
        } else {
            // reset baalnce of all stakers
            uint256 length = stakerList.length;
            for (uint256 i; i < length; ++i) {
                address stakerAddress = stakerList[i]; //   TODO cache stakerList before
                staker[stakerAddress].stakerBalance = 0;
                staker[stakerAddress].timeStamp = block.timestamp;
                // clean stakerList array
                delete stakerList;
            }
            // if stakersDeposit not enough use projectDeposit to pay the rest
            uint256 remainingCost = _amount - stakersDeposit;
            // descrease project deposit by the remaining amount
            projectDeposit -= remainingCost;

            // set stakers deposit to 0
            stakersDeposit = 0;

            // transfer funds to saloon address
            _token.safeTransfer(_saloonWallet, _amount);

            // todo Emit event with timestamp and amount
            return true;
        }
    }

    // ADMIN HARVEST FEES public
    function collectSaloonPremiumFees(address _token, address _saloonWallet) external onlyManager returns (uint) {
        // send current fees to saloon address
        _token.safeTransfer(_saloonWallet, saloonPremiumFees);
        uint totalCollected = saloonPremiumFees;
        // reset claimable fees
        saloonPremiumFees = 0;

        return totalCollected;

        // todo emit event
    }

    // PROJECT DEPOSIT
    // project must approve this address first.
    function bountyDeposit(address _token, address _projectWallet, uint256 _amount) external onlyManager returns (bool) {
        // transfer from project account
        _token.safeTransferFrom(_projectWallet, address(this), _amount);

        // update deposit variable
        projectDeposit += _amount;

        return true;
    }

    // PROJECT SET CAP
    function setPoolCap(uint256 _amount) external onlyManager {
        // todo two weeks time lock?
        poolCap = _amount;
    }

    // PROJECT SET APY
    // project must approve this address first.
    // project will have to pay upfront cost of full period on the first time.
    // this will serve two purposes:
    // 1. sign of good faith and working payment system
    // 2. if theres is ever a problem with payment the initial premium deposit can be used as a buffer so users can still be paid while issue is fixed.
    function setDesiredAPY(address _token, address _projectWallet, uint256 _desiredAPY)
        external
        onlyManager
        returns (bool)
    {
        // set timelock on this???
        // make sure APY has right amount of decimals (1e18)

        // ensure there is enough premium balance to pay stakers new APY for a month
        uint256 currentPremiumBalance = premiumBalance;
        uint256 newRequiredPremiumBalancePerPeriod = (((poolCap * _desiredAPY) /
            DENOMINATOR) / YEAR) * poolPeriod;
        // this might lead to leftover premium if project decreases APY, we will see what to do about that later
        if (currentPremiumBalance < newRequiredPremiumBalancePerPeriod) {
            // calculate difference to be paid
            uint256 difference = newRequiredPremiumBalancePerPeriod -
                currentPremiumBalance;
            // transfer to this address
            _token.safeTransferFrom(_projectWallet, address(this), difference);
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

        // disable instant withdrawals
        APYdropped = false;

        return true;
    }

    // PROJECT PAY weekly/monthly PREMIUM to this address
    // this address needs to be approved first
    function billFortnightlyPremium(address _token, address _projectWallet) public onlyManagerOrSelf returns (bool) {
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

                if (
                    !_token.safeTransferFrom(
                        _projectWallet,
                        address(this),
                        fortnightlyPremiumOwed
                    )
                ) {
                    // if transfer fails APY is reset and premium is paid with new APY
                    // register new APYperiod
                    APYperiods memory newAPYperiod;
                    newAPYperiod.timeStamp = block.timestamp;
                    newAPYperiod.periodAPY = currentAPY;
                    APYrecords.push(newAPYperiod);
                    // set new APY
                    desiredAPY = currentAPY;

                    uint256 newFortnightlyPremiumOwed = (((stakersDeposit *
                        desiredAPY) / DENOMINATOR) / YEAR) * sinceLastPaid;

                    // Calculate saloon fee
                    uint256 saloonFee = (newFortnightlyPremiumOwed *
                        PREMIUM_COMMISSION) / DENOMINATOR;

                    // update saloon claimable fee
                    saloonPremiumFees += saloonFee;

                    // update premiumBalance
                    premiumBalance += newFortnightlyPremiumOwed;

                    lastTimePaid = block.timestamp;

                    uint256 newRequiredPremiumBalancePerPeriod = (((poolCap *
                        desiredAPY) / DENOMINATOR) / YEAR) * poolPeriod;

                    requiredPremiumBalancePerPeriod = newRequiredPremiumBalancePerPeriod;

                    // try transferring again...
                    _token.safeTransferFrom(
                        _projectWallet,
                        address(this),
                        newFortnightlyPremiumOwed
                    );
                    // enable instant withdrawals
                    APYdropped = true;

                    return true;
                } else {
                    // Calculate saloon fee
                    uint256 saloonFee = (fortnightlyPremiumOwed *
                        PREMIUM_COMMISSION) / DENOMINATOR;

                    // update saloon claimable fee
                    saloonPremiumFees += saloonFee;

                    // update premiumBalance
                    premiumBalance += fortnightlyPremiumOwed;

                    lastTimePaid = block.timestamp;

                    // disable instant withdrawals
                    APYdropped = false;

                    return true;
                }
            } else {
                uint256 fortnightlyPremiumOwed = (((stakersDeposit *
                    desiredAPY) / DENOMINATOR) / YEAR) * poolPeriod;

                if (
                    !_token.safeTransferFrom(
                        _projectWallet,
                        address(this),
                        fortnightlyPremiumOwed
                    )
                ) {
                    // if transfer fails APY is reset and premium is paid with new APY
                    // register new APYperiod
                    APYperiods memory newAPYperiod;
                    newAPYperiod.timeStamp = block.timestamp;
                    newAPYperiod.periodAPY = currentAPY;
                    APYrecords.push(newAPYperiod);
                    // set new APY
                    desiredAPY = currentAPY;

                    uint256 newFortnightlyPremiumOwed = (((stakersDeposit *
                        desiredAPY) / DENOMINATOR) / YEAR) * poolPeriod;

                    // Calculate saloon fee
                    uint256 saloonFee = (newFortnightlyPremiumOwed *
                        PREMIUM_COMMISSION) / DENOMINATOR;

                    // update saloon claimable fee
                    saloonPremiumFees += saloonFee;

                    // update premiumBalance
                    premiumBalance += newFortnightlyPremiumOwed;

                    lastTimePaid = block.timestamp;

                    uint256 newRequiredPremiumBalancePerPeriod = (((poolCap *
                        desiredAPY) / DENOMINATOR) / YEAR) * poolPeriod;

                    requiredPremiumBalancePerPeriod = newRequiredPremiumBalancePerPeriod;

                    // try transferring again...
                    _token.safeTransferFrom(
                        _projectWallet,
                        address(this),
                        newFortnightlyPremiumOwed
                    );
                    // enable instant withdrawals
                    APYdropped = true;

                    return true;
                } else {
                    // Calculate saloon fee
                    uint256 saloonFee = (fortnightlyPremiumOwed *
                        PREMIUM_COMMISSION) / DENOMINATOR;

                    // update saloon claimable fee
                    saloonPremiumFees += saloonFee;

                    // update premiumBalance
                    premiumBalance += fortnightlyPremiumOwed;

                    lastTimePaid = block.timestamp;

                    // disable instant withdrawals
                    APYdropped = false;

                    return true;
                }
            }
        }
        return false;
    }

    // PROJECT EXCESS PREMIUM BALANCE WITHDRAWAL -- NOT SURE IF SHOULD IMPLEMENT THIS
    // timelock on this?

    function scheduleprojectDepositWithdrawal(uint256 _amount) {
        projectWithdrawalTimeLock[_amount] = block.timestamp + poolPeriod;

        //todo emit event -> necessary to predict payout payment in the following week
        //todo OR have variable that gets updated with new values? - forgot what we discussed about this
    }

    // PROJECT DEPOSIT WITHDRAWAL
    function projectDepositWithdrawal(address _token, address _projectWallet, uint256 _amount) external returns (bool) {
        // timelock on this.
        require(
            projectWithdrawalTimeLock[_amount] < block.timestamp &&
                projectWithdrawalTimeLock[_amount] != 0,
            "Timelock not finished or started"
        );

        projectDeposit -= _amount;
        _token.safeTransfer(_projectWallet, _amount);
        // todo emit event
        return true;
    }

    // STAKING
    // staker needs to approve this address first
    function stake(address _token, address _staker, uint256 _amount)
        external
        onlyManager
        nonReentrant
        returns (bool)
    {
        // dont allow staking if stakerDeposit >= poolCap
        require(
            stakersDeposit + _amount <= poolCap,
            "Staking Pool already full"
        );

        // Push to stakerList array if previous balance = 0
        if (staker[_staker][-1].stakerBalance == 0) {
            stakerList.push(_staker);
        }

        // update stakerInfo struct
        StakerInfo memory newInfo;
        newInfo.balanceTimeStamp = block.timestamp;
        newInfo.stakerBalance = staker[_staker][-1].stakerBalance + _amount;

        // save info to storage
        staker[_staker].push(newInfo);

        // increase global stakersDeposit
        stakersDeposit += _amount;

        // transferFrom to this address
        _token.safeTransferFrom(_staker, address(this), _amount);

        return true;
    }

    function askForUnstake(address _staker, uint256 _amount)
        external
        onlyManager
    {
        require(staker[_staker].stakerBalance >= _amount, "Insuficcient balance");
        stakerTimeLock[_staker][_amount] = block.timestamp + poolPeriod;

        //todo emit event -> necessary to predict payout payment in the following week
        //todo OR have variable that gets updated with new values? - forgot what we discussed about this
    }

    // UNSTAKING
    // allow instant withdraw if stakerDeposit >= poolCap or APY = 0%
    // otherwise have to wait for timelock period
    function unstake(address _token, address _staker, uint256 _amount)
        external
        onlyManager
        nonReentrant
        returns (bool)
    {
        // allow for immediate withdrawal if APY drops from desired APY
        // going to need to create an extra variable for storing this when apy changes for worse
        if (desiredAPY != 0 || APYdropped == true) {
            require(
                stakerTimelock[_staker][_amount] < block.timestamp &&
                    stakerTimelock[_staker][_amount] != 0,
                "Timelock not finished or started"
            );

            // decrease staker balance
            // update stakerInfo struct
            StakerInfo memory newInfo;
            newInfo.balanceTimeStamp = block.timestamp;
            newInfo.stakerBalance = staker[_staker][-1].stakerBalance - _amount;

            address[] memory stakersList = stakerList;
            if (newInfo.stakerBalance == 0) {
                // loop through stakerlist
                uint256 length = stakersList.length(); // can you do length on memory arrays?
                for (uint256 i; i < length; ) {
                    // find staker
                    if (stakersList[i] == _staker) {
                        // exchange it with last address in array
                        address lastAddress = stakersList[-1];
                        stakerList[-1] = _staker;
                        stakerList[i] = lastAddress;
                        // pop it
                        stakerList.pop();
                        break;
                    }

                    unchecked {
                        ++i;
                    }
                }
            }
            // save info to storage
            staker[_staker].push(newInfo);

            // decrease global stakersDeposit
            stakersDeposit -= _amount;

            // transfer it out
            _token.safeTransfer(_staker, _amount);

            return true;
        }
    }

    // claim premium
    function claimPremium(address _token, address _staker) external onlyManager nonReentrant returns(owedPremium){
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
            uint owedPremium = totalPremiumToClaim
            if (!_token.safeTransfer(_staker, owedPremium)) {
                billFortnightlyPremium();
                // if function above changes APY than accounting is going to get messed up,
                // because the APY used for for new transfer will be different than APY used to calculate totalPremiumToClaim
                // if function above fails then it fails...
            }

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

            if (!_token.safeTransfer(_staker, owedPremium)) {
                billFortnightlyPremium();
                // if function above changes APY than accounting is going to get messed up,
                // because the APY used for for new transfer will be different than APY used to calculate totalPremiumToClaim
                // if function above fails then it fails...
            }

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
    function viewHackerPayout() external view returns (uint256) {
        return bountyHackerPayout;
    }

    // View stakersDeposit balance
    function viewStakersDeposit() external view returns (uint256) {
        return stakersDeposit;
    }

    // View deposit balance
    function viewProjecDeposit() external view returns (uint256) {
        return projectDeposit;
    }

    // view premium balance
    function viewPremiumBalance() external view returns (uint256) {
        return premiumBalance;
    }

    // view required premium balance
    function viewRequirePremiumBalance() external view returns (uint256) {
        return requiredPremiumBalancePerPeriod;
    }

    // View APY
    function viewDesireAPY() external view returns (uint256) {
        return desiredAPY;
    }

    // View Cap
    function viewPoolCap() external view returns (uint256) {
        return poolCap;
    }

    // View user staking balance
    function viewUserStakingBalance(address _staker)
        external
        view
        returns (uint256, uint256)
    {
        return (staker[_staker].stakerBalance, staker[_staker].timeStamp);
    }

    //todo view user current claimable premium ???

    //todo view version???

    ///// VIEW FUNCTIONS END /////
}
