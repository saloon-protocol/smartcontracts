//SPDX-License-Identifier: MIT
pragma solidity 0.8.10;
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
// import "openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";
import "./SaloonWallet.sol";

//  OBS: Better suggestions for calculating the APY paid on a fortnightly basis are welcomed.

contract BountyPool is Ownable, Initializable {
    using SafeERC20 for IERC20;
    //#################### State Variables *****************\\

    address public manager;

    uint256 public constant VERSION = 1;
    uint256 public constant BOUNTY_COMMISSION = 10 * 1e18;
    uint256 public constant PREMIUM_COMMISSION = 2 * 1e18;
    uint256 public constant DENOMINATOR = 100 * 1e18;
    uint256 public constant YEAR = 365 days;

    uint256 public projectDeposit;
    uint256 public stakersDeposit;

    uint256 public saloonBountyCommission;

    uint256 public saloonPremiumFees;
    uint256 public premiumBalance;
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
    mapping(address => mapping(uint256 => TimelockInfo)) public stakerTimelock;

    mapping(uint256 => TimelockInfo) public poolCapTimelock;
    mapping(uint256 => TimelockInfo) public APYTimelock;
    mapping(uint256 => TimelockInfo) public withdrawalTimelock;

    struct StakerInfo {
        uint256 stakerBalance;
        uint256 balanceTimeStamp;
    }

    struct APYperiods {
        uint256 timeStamp;
        uint256 periodAPY;
    }

    struct TimelockInfo {
        uint256 timelock;
        bool executed;
    }

    address[] public stakerList;

    APYperiods[] public APYrecords;

    bool public APYdropped;

    //#################### State Variables End *****************\\

    function initializeImplementation(address _manager) public initializer {
        manager = _manager;
    }

    //#################### Modifiers *****************\\

    modifier onlyManager() {
        require(msg.sender == manager, "Only manager allowed");
        _;
    }

    modifier onlyManagerOrSelf() {
        require(
            msg.sender == manager || msg.sender == address(this),
            "Only manager or self allowed"
        );
        _;
    }

    //#################### Modifiers END *****************\\

    //#################### Functions *******************\\

    // ADMIN PAY BOUNTY public
    // this implementation uses investors funds first before project deposit,
    // future implementation might use a more hybrid and sophisticated splitting of costs.
    function payBounty(
        address _token,
        address _saloonWallet,
        address _hunter,
        uint256 _amount
    ) public onlyManager returns (bool) {
        uint256 stakersDeposits = stakersDeposit;

        // cache list
        address[] memory stakersList = stakerList;
        // cache length
        uint256 length = stakersList.length;

        // check if stakersDeposit is enough
        if (stakersDeposits >= _amount) {
            // decrease stakerDeposit
            stakersDeposits -= _amount;

            // if staker deposit == 0
            if (stakersDeposits == 0) {
                for (uint256 i; i < length; ++i) {
                    // update stakerInfo struct
                    StakerInfo memory newInfo;
                    newInfo.balanceTimeStamp = block.timestamp;
                    newInfo.stakerBalance = 0;

                    address stakerAddress = stakersList[i];
                    staker[stakerAddress].push(newInfo);

                    // deduct saloon commission and transfer
                    calculateCommissioAndTransferPayout(
                        _token,
                        _hunter,
                        _saloonWallet,
                        _amount
                    );
                }

                // clean stakerList array
                delete stakerList;
                return true;
            }
            // calculate percentage of stakersDeposit
            uint256 percentage = _amount / stakersDeposits;
            // loop through all stakers and deduct percentage from their balances
            for (uint256 i; i < length; ++i) {
                address stakerAddress = stakersList[i];
                uint256 arraySize = staker[stakerAddress].length - 1;
                uint256 oldStakerBalance = staker[stakerAddress][arraySize]
                    .stakerBalance;

                // update stakerInfo struct
                StakerInfo memory newInfo;
                newInfo.balanceTimeStamp = block.timestamp;
                newInfo.stakerBalance =
                    oldStakerBalance -
                    ((oldStakerBalance * percentage) / DENOMINATOR);

                staker[stakerAddress].push(newInfo);
            }

            // deduct saloon commission and transfer
            calculateCommissioAndTransferPayout(
                _token,
                _hunter,
                _saloonWallet,
                _amount
            );

            return true;
        } else {
            // reset baalnce of all stakers
            for (uint256 i; i < length; ++i) {
                // update stakerInfo struct
                StakerInfo memory newInfo;
                newInfo.balanceTimeStamp = block.timestamp;
                newInfo.stakerBalance = 0;

                address stakerAddress = stakersList[i];
                staker[stakerAddress].push(newInfo);
            }
            // clean stakerList array
            delete stakerList;
            // if stakersDeposit not enough use projectDeposit to pay the rest
            uint256 remainingCost = _amount - stakersDeposits;
            // descrease project deposit by the remaining amount
            projectDeposit -= remainingCost;

            // set stakers deposit to 0
            stakersDeposit = 0;

            // deduct saloon commission and transfer
            calculateCommissioAndTransferPayout(
                _token,
                _hunter,
                _saloonWallet,
                _amount
            );

            return true;
        }
    }

    function calculateCommissioAndTransferPayout(
        address _token,
        address _hunter,
        address _saloonWallet,
        uint256 _amount
    ) internal returns (bool) {
        // deduct saloon commission
        uint256 saloonCommission = (_amount * BOUNTY_COMMISSION) / DENOMINATOR;
        uint256 hunterPayout = _amount - saloonCommission;
        // transfer to hunter
        //note maybe have a two step process to transfer payout
        IERC20(_token).safeTransfer(_hunter, hunterPayout);
        // transfer commission to saloon address
        IERC20(_token).safeTransfer(_saloonWallet, saloonCommission);

        return true;
    }

    // ADMIN HARVEST FEES public
    function collectSaloonPremiumFees(address _token, address _saloonWallet)
        external
        onlyManager
        returns (uint256)
    {
        // send current fees to saloon address
        IERC20(_token).safeTransfer(_saloonWallet, saloonPremiumFees);
        uint256 totalCollected = saloonPremiumFees;
        // reset claimable fees
        saloonPremiumFees = 0;

        return totalCollected;
    }

    // PROJECT DEPOSIT
    // project must approve this address first.
    function bountyDeposit(
        address _token,
        address _projectWallet,
        uint256 _amount
    ) external onlyManager returns (bool) {
        // transfer from project account
        IERC20(_token).safeTransferFrom(_projectWallet, address(this), _amount);

        // update deposit variable
        projectDeposit += _amount;

        return true;
    }

    function schedulePoolCapChange(uint256 _newPoolCap) external onlyManager {
        poolCapTimelock[_newPoolCap].timelock = block.timestamp + poolPeriod;
        poolCapTimelock[_newPoolCap].executed = false;
    }

    // PROJECT SET CAP
    function setPoolCap(uint256 _amount) external onlyManager {
        // check timelock if current poolCap != 0
        if (poolCap != 0) {
            // Check If queued check time has passed && its hasnt been executed && timestamp cant be =0
            require(
                poolCapTimelock[_amount].timelock < block.timestamp &&
                    poolCapTimelock[_amount].executed == false &&
                    poolCapTimelock[_amount].timelock != 0,
                "Timelock not set or not completed"
            );
            // set executed to true
            poolCapTimelock[_amount].executed = true;
        }

        poolCap = _amount;
    }

    function scheduleAPYChange(uint256 _newAPY) external onlyManager {
        poolCapTimelock[_newAPY].timelock = block.timestamp + poolPeriod;
        poolCapTimelock[_newAPY].executed = false;
    }

    // PROJECT SET APY
    // project must approve this address first.
    // project will have to pay upfront cost of full period on the first time.
    // this will serve two purposes:
    // 1. sign of good faith and working payment system
    // 2. if theres is ever a problem with payment the initial premium deposit can be used as a buffer so users can still be paid while issue is fixed.
    function setDesiredAPY(
        address _token,
        address _projectWallet,
        uint256 _desiredAPY
    ) external onlyManager returns (bool) {
        // check timelock if current APY != 0
        if (desiredAPY != 0) {
            // Check If queued check time has passed && its hasnt been executed && timestamp cant be =0
            require(
                APYTimelock[_desiredAPY].timelock < block.timestamp &&
                    APYTimelock[_desiredAPY].executed == false &&
                    APYTimelock[_desiredAPY].timelock != 0,
                "Timelock not set or not completed"
            );
            // set executed to true
            APYTimelock[_desiredAPY].executed = true;
        }

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
            IERC20(_token).safeTransferFrom(
                _projectWallet,
                address(this),
                difference
            );
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

        // loop through stakerList array and push new balance for new APY period time stamp for every staker
        address[] memory stakersList = stakerList;
        uint256 length = stakersList.length;
        for (uint256 i; i < length; ) {
            address stakerAddress = stakersList[i];
            uint256 arraySize = staker[stakerAddress].length - 1;

            StakerInfo memory newInfo;
            // get last balance
            newInfo.stakerBalance = staker[stakerAddress][arraySize]
                .stakerBalance;
            // update current time
            newInfo.balanceTimeStamp = block.timestamp;
            // push to array so user can claim it.
            staker[stakerAddress].push(newInfo);

            unchecked {
                ++i;
            }
        }

        // disable instant withdrawals
        APYdropped = false;

        return true;
    }

    // PROJECT PAY weekly/monthly PREMIUM to this address
    // this address needs to be approved first
    function billFortnightlyPremium(address _token, address _projectWallet)
        public
        onlyManagerOrSelf
        returns (bool)
    {
        uint256 currentPremiumBalance = premiumBalance;
        uint256 minimumRequiredBalance = requiredPremiumBalancePerPeriod;
        uint256 stakersDeposits = stakersDeposit;
        // check if current premium balance is less than required
        if (currentPremiumBalance < minimumRequiredBalance) {
            uint256 lastPaid = lastTimePaid;
            uint256 paymentPeriod = poolPeriod;

            // check when function was called last time and pay premium according to how much time has passed since then.
            uint256 sinceLastPaid = block.timestamp - lastPaid;

            if (sinceLastPaid > paymentPeriod) {
                // multiple by `sinceLastPaid` instead of two weeks
                uint256 fortnightlyPremiumOwed = ((
                    ((stakersDeposits * desiredAPY) / DENOMINATOR)
                ) / YEAR) * sinceLastPaid;

                if (
                    !IERC20(_token).safeTransferFrom(
                        _projectWallet,
                        address(this),
                        fortnightlyPremiumOwed
                    )
                ) {
                    // if transfer fails APY is reset and premium is paid with new APY
                    // register new APYperiod

                    APYperiods memory newAPYperiod;
                    newAPYperiod.timeStamp = block.timestamp;
                    newAPYperiod.periodAPY = viewcurrentAPY();
                    APYrecords.push(newAPYperiod);
                    // set new APY
                    desiredAPY = viewcurrentAPY();

                    uint256 newFortnightlyPremiumOwed = (((stakersDeposits *
                        desiredAPY) / DENOMINATOR) / YEAR) * sinceLastPaid;
                    {
                        // Calculate saloon fee
                        uint256 saloonFee = (newFortnightlyPremiumOwed *
                            PREMIUM_COMMISSION) / DENOMINATOR;

                        // update saloon claimable fee
                        saloonPremiumFees += saloonFee;

                        // update premiumBalance
                        premiumBalance += newFortnightlyPremiumOwed;

                        lastTimePaid = block.timestamp;

                        uint256 newRequiredPremiumBalancePerPeriod = (((poolCap *
                                desiredAPY) / DENOMINATOR) / YEAR) *
                                paymentPeriod;

                        requiredPremiumBalancePerPeriod = newRequiredPremiumBalancePerPeriod;
                    }
                    // try transferring again...
                    IERC20(_token).safeTransferFrom(
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
                    desiredAPY) / DENOMINATOR) / YEAR) * paymentPeriod;

                if (
                    !IERC20(_token).safeTransferFrom(
                        _projectWallet,
                        address(this),
                        fortnightlyPremiumOwed
                    )
                ) {
                    // if transfer fails APY is reset and premium is paid with new APY
                    // register new APYperiod
                    APYperiods memory newAPYperiod;
                    newAPYperiod.timeStamp = block.timestamp;
                    newAPYperiod.periodAPY = viewcurrentAPY();
                    APYrecords.push(newAPYperiod);
                    // set new APY
                    desiredAPY = viewcurrentAPY();

                    uint256 newFortnightlyPremiumOwed = (((stakersDeposit *
                        desiredAPY) / DENOMINATOR) / YEAR) * paymentPeriod;
                    {
                        // Calculate saloon fee
                        uint256 saloonFee = (newFortnightlyPremiumOwed *
                            PREMIUM_COMMISSION) / DENOMINATOR;

                        // update saloon claimable fee
                        saloonPremiumFees += saloonFee;

                        // update premiumBalance
                        premiumBalance += newFortnightlyPremiumOwed;

                        lastTimePaid = block.timestamp;

                        uint256 newRequiredPremiumBalancePerPeriod = (((poolCap *
                                desiredAPY) / DENOMINATOR) / YEAR) *
                                paymentPeriod;

                        requiredPremiumBalancePerPeriod = newRequiredPremiumBalancePerPeriod;
                    }
                    // try transferring again...
                    IERC20(_token).safeTransferFrom(
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

    function scheduleprojectDepositWithdrawal(uint256 _amount)
        external
        onlyManager
        returns (bool)
    {
        withdrawalTimelock[_amount].timelock = block.timestamp + poolPeriod;
        withdrawalTimelock[_amount].executed = false;
        return true;
    }

    // PROJECT DEPOSIT WITHDRAWAL
    function projectDepositWithdrawal(
        address _token,
        address _projectWallet,
        uint256 _amount
    ) external onlyManager returns (bool) {
        // time lock check
        // Check If queued check time has passed && its hasnt been executed && timestamp cant be =0
        require(
            withdrawalTimelock[_amount].timelock < block.timestamp &&
                withdrawalTimelock[_amount].executed == false &&
                withdrawalTimelock[_amount].timelock != 0,
            "Timelock not set or not completed"
        );
        withdrawalTimelock[_amount].executed = true;

        projectDeposit -= _amount;
        IERC20(_token).safeTransfer(_projectWallet, _amount);
        return true;
    }

    // STAKING
    // staker needs to approve this address first
    function stake(
        address _token,
        address _staker,
        uint256 _amount
    ) external onlyManager returns (bool) {
        // dont allow staking if stakerDeposit >= poolCap
        require(
            stakersDeposit + _amount <= poolCap,
            "Staking Pool already full"
        );

        uint256 arrayLength = staker[_staker].length;

        // uint256 position = arrayLength == 0 ? 0 : arrayLength - 1;

        //  if array length is  == 0 we must push first
        if (arrayLength == 0) {
            StakerInfo memory init;
            init.stakerBalance = 0;
            init.balanceTimeStamp = 0;
            staker[_staker].push(init);
        }

        uint256 position = staker[_staker].length - 1;

        // Push to stakerList array if previous balance = 0
        if (staker[_staker][position].stakerBalance == 0) {
            stakerList.push(_staker);
        }

        // update stakerInfo struct
        StakerInfo memory newInfo;
        newInfo.balanceTimeStamp = block.timestamp;
        newInfo.stakerBalance =
            staker[_staker][position].stakerBalance +
            _amount;

        // if staker is new update array[0] created earlier
        if (arrayLength == 0) {
            staker[_staker][position] = newInfo;
        } else {
            // if staker is not new:
            // save info to storage
            staker[_staker].push(newInfo);
        }

        // increase global stakersDeposit
        stakersDeposit += _amount;

        // transferFrom to this address
        IERC20(_token).safeTransferFrom(_staker, address(this), _amount);

        return true;
    }

    function scheduleUnstake(address _staker, uint256 _amount)
        external
        onlyManager
        returns (bool)
    {
        // this cant be un-initiliazed because its already been when staking
        uint256 arraySize = staker[_staker].length - 1;
        require(
            staker[_staker][arraySize].stakerBalance >= _amount,
            "Insuficcient balance"
        );

        stakerTimelock[_staker][_amount].timelock =
            block.timestamp +
            poolPeriod;
        stakerTimelock[_staker][_amount].executed = false;

        return true;
    }

    // UNSTAKING
    // allow instant withdraw if stakerDeposit >= poolCap or APY = 0%
    // otherwise have to wait for timelock period
    function unstake(
        address _token,
        address _staker,
        uint256 _amount
    ) external onlyManager returns (bool) {
        // allow for immediate withdrawal if APY drops from desired APY
        // going to need to create an extra variable for storing this when apy changes for worse
        if (desiredAPY != 0 || APYdropped == true) {
            // time lock check
            // Check If queued check time has passed && its hasnt been executed && timestamp cant be =0
            require(
                stakerTimelock[_staker][_amount].timelock < block.timestamp &&
                    stakerTimelock[_staker][_amount].executed == false &&
                    stakerTimelock[_staker][_amount].timelock != 0,
                "Timelock not set or not completed"
            );
            stakerTimelock[_staker][_amount].executed = true;

            uint256 arraySize = staker[_staker].length - 1;

            // decrease staker balance
            // update stakerInfo struct
            StakerInfo memory newInfo;
            newInfo.balanceTimeStamp = block.timestamp;
            newInfo.stakerBalance =
                staker[_staker][arraySize].stakerBalance -
                _amount;

            address[] memory stakersList = stakerList;
            if (newInfo.stakerBalance == 0) {
                // loop through stakerlist
                uint256 length = stakersList.length;
                for (uint256 i; i < length; ) {
                    // find staker
                    if (stakersList[i] == _staker) {
                        // exchange it with last address in array
                        address lastAddress = stakersList[length - 1];
                        stakerList[length - 1] = _staker;
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
            IERC20(_token).safeTransfer(_staker, _amount);

            return true;
        }
    }

    // claim premium
    function claimPremium(
        address _token,
        address _staker,
        address _projectWallet
    ) external onlyManager returns (uint256, bool) {
        // how many chunks of time (currently = 2 weeks) since lastclaimed?
        uint256 lastTimeClaimed = lastClaimed[_staker];
        uint256 sinceLastClaimed = block.timestamp - lastTimeClaimed;
        uint256 paymentPeriod = poolPeriod;
        StakerInfo[] memory stakerInfo = staker[_staker];
        uint256 stakerLength = stakerInfo.length;
        // if last time premium was called > 1 period

        if (sinceLastClaimed > paymentPeriod) {
            uint256 totalPremiumToClaim = calculatePremiumToClaim(
                lastTimeClaimed,
                stakerInfo,
                stakerLength
            );
            // Calculate saloon fee
            uint256 saloonFee = (totalPremiumToClaim * PREMIUM_COMMISSION) /
                DENOMINATOR;
            // subtract saloon fee
            totalPremiumToClaim -= saloonFee;
            uint256 owedPremium = totalPremiumToClaim;

            if (!IERC20(_token).safeTransfer(_staker, owedPremium)) {
                billFortnightlyPremium(_token, _projectWallet);
                /* NOTE: if function above changes APY than accounting is going to get messed up,
                because the APY used for for new transfer will be different than APY 
                used to calculate totalPremiumToClaim.
                If function above fails then it fails... 
                */
            }

            // update premiumBalance
            premiumBalance -= totalPremiumToClaim;

            // update last time claimed
            lastClaimed[_staker] = block.timestamp;
            return (owedPremium, true);
        } else {
            // calculate currently owed for the week
            uint256 owedPremium = (((stakerInfo[stakerLength - 1]
                .stakerBalance * desiredAPY) / DENOMINATOR) / YEAR) *
                poolPeriod;
            // pay current period owed

            // Calculate saloon fee
            uint256 saloonFee = (owedPremium * PREMIUM_COMMISSION) /
                DENOMINATOR;
            // subtract saloon fee
            owedPremium -= saloonFee;

            if (!IERC20(_token).safeTransfer(_staker, owedPremium)) {
                billFortnightlyPremium(_token, _projectWallet);
                /* NOTE: if function above changes APY than accounting is going to get messed up,
                because the APY used for for new transfer will be different than APY 
                used to calculate totalPremiumToClaim.
                If function above fails then it fails... 
                */
            }

            // update premium
            premiumBalance -= owedPremium;

            // update last time claimed
            lastClaimed[_staker] = block.timestamp;
            return (owedPremium, true);
        }
    }

    function calculatePremiumToClaim(
        uint256 _lastTimeClaimed,
        StakerInfo[] memory _stakerInfo,
        uint256 _stakerLength
    ) internal view returns (uint256) {
        uint256 length = APYrecords.length;
        // loop through APY periods (reversely) until last missed period is found
        uint256 lastMissed;
        uint256 totalPremiumToClaim;
        for (uint256 i = length - 1; i == 0; --i) {
            if (APYrecords[i].timeStamp < _lastTimeClaimed) {
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

            uint256 periodTotalBalance;
            for (uint256 j; j < _stakerLength; ++j) {
                // check staker balance at that moment
                if (
                    _stakerInfo[j].balanceTimeStamp > periodStart &&
                    _stakerInfo[j].balanceTimeStamp < periodEnd
                ) {
                    // add it to that period total
                    periodTotalBalance += _stakerInfo[j].stakerBalance;
                    /* note: stakerInfo is updated for every user everytime 
                    APY changes. 
                    
                    */
                }
            }

            //calcualte owed APY for that period: (APY * amount / Seconds in a year) * number of seconds in X period
            totalPremiumToClaim +=
                (((periodTotalBalance * APYrecords[i + 1].periodAPY) /
                    DENOMINATOR) / YEAR) *
                periodLength;
        }

        return totalPremiumToClaim;
    }

    ///// VIEW FUNCTIONS /////

    // View currentAPY
    function viewcurrentAPY() public view returns (uint256) {
        uint256 apy = premiumBalance / poolCap;
        return apy;
    }

    // View total balance
    function viewHackerPayout() external view returns (uint256) {
        uint256 totalBalance = projectDeposit + stakersDeposit;
        uint256 saloonCommission = (totalBalance * BOUNTY_COMMISSION) /
            DENOMINATOR;

        return totalBalance - saloonCommission;
    }

    function viewBountyBalance() external view returns (uint256) {
        uint256 totalBalance = projectDeposit + stakersDeposit;
        return totalBalance;
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
    function viewDesiredAPY() external view returns (uint256) {
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
        uint256 length = staker[_staker].length;
        return (
            staker[_staker][length - 1].stakerBalance,
            staker[_staker][length - 1].balanceTimeStamp
        );
    }

    //note view user current claimable premium ???

    //note view version function??

    ///// VIEW FUNCTIONS END /////
}
