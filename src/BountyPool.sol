//SPDX-License-Identifier: MIT
pragma solidity 0.8.10;
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
// import "openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";
import "./SaloonWallet.sol";

contract BountyPool is Ownable, Initializable {
    using SafeERC20 for IERC20;
    //#################### State Variables *****************\\

    address public manager;

    uint256 public constant VERSION = 1;
    uint256 public constant PRECISION = 100;
    uint256 public constant YEAR = 365 days;
    uint256 public constant PERIOD = 1 weeks;

    uint256 public decimals;
    uint256 public bountyCommission;
    uint256 public premiumCommission;
    uint256 public denominator;

    uint256 public saloonBountyCommission;
    uint256 public saloonPremiumFees;
    uint256 public premiumBalance;

    uint256 public desiredAPY;
    uint256 public poolCap;
    uint256 public lastTimePaid;
    uint256 public projectDeposit;
    uint256 public requiredPremiumBalancePerPeriod;
    uint256 public stakingPause;

    // staker => last time premium was claimed
    mapping(address => uint256) public lastClaimed;
    // staker address => StakingInfo array
    mapping(address => StakingInfo[]) public staker;

    // staker address => amount => timelock time
    mapping(address => TimelockInfo) public stakerTimelock;

    TimelockInfo public poolCapTimelock;
    TimelockInfo public APYTimelock;
    TimelockInfo public withdrawalTimelock;

    struct StakingInfo {
        uint256 stakeBalance;
        uint256 balanceTimeStamp;
    }

    struct APYperiods {
        uint256 timeStamp;
        uint256 periodAPY;
    }

    struct TimelockInfo {
        uint256 timelock;
        uint256 timeLimit;
        uint256 amount;
        bool executed;
    }

    address[] public stakerList;

    APYperiods[] public APYrecords;

    StakingInfo[] public stakersDeposit;
    uint256[] private APYChanges;
    uint256[] private stakeChanges;
    uint256[] private stakerChange;

    bool public APYdropped;
    bool public firstDeposit;

    //#################### State Variables End *****************\\

    function initializeImplementation(address _manager, uint256 _decimals)
        public
        initializer
    {
        manager = _manager;
        decimals = _decimals;
        bountyCommission = 10 * (10**_decimals);
        premiumCommission = 10 * (10**_decimals);
        denominator = 100 * (10**_decimals);
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
        StakingInfo[] memory stakersDeposits = stakersDeposit;
        uint256 stakingLenght = stakersDeposits.length - 1;

        // cache list
        address[] memory stakersList = stakerList;
        // cache length
        uint256 length = stakersList.length;

        // check if stakersDeposit is enough
        if (stakersDeposits[stakingLenght].stakeBalance >= _amount) {
            // decrease stakerDeposit
            stakersDeposits[stakingLenght].stakeBalance -= _amount;
            // push new value to array
            StakingInfo memory stakingInfo;
            stakingInfo.balanceTimeStamp = block.timestamp;
            stakingInfo.stakeBalance = stakersDeposits[stakingLenght]
                .stakeBalance;

            // if staker deposit == 0
            // check new pushed value
            if (stakersDeposits[stakingLenght].stakeBalance == 0) {
                for (uint256 i; i < length; ++i) {
                    // update StakingInfo struct
                    StakingInfo memory newInfo;
                    newInfo.balanceTimeStamp = block.timestamp;
                    newInfo.stakeBalance = 0;

                    address stakerAddress = stakersList[i];
                    staker[stakerAddress].push(newInfo);
                }

                // deduct saloon commission and transfer
                calculateCommissioAndTransferPayout(
                    _token,
                    _hunter,
                    _saloonWallet,
                    _amount
                );

                // update stakersDeposit
                stakersDeposit.push(stakingInfo);
                // clean stakerList array
                delete stakerList;
                return true;
            }
            // calculate percentage of stakersDeposit
            // note should we increase precision?
            uint256 percentage = (_amount * PRECISION) /
                stakersDeposits[stakingLenght].stakeBalance;
            // loop through all stakers and deduct percentage from their balances
            for (uint256 i; i < length; ++i) {
                address stakerAddress = stakersList[i];
                uint256 arraySize = staker[stakerAddress].length - 1;
                uint256 oldStakerBalance = staker[stakerAddress][arraySize]
                    .stakeBalance;

                // update StakingInfo struct
                StakingInfo memory newInfo;
                newInfo.balanceTimeStamp = block.timestamp;
                newInfo.stakeBalance =
                    oldStakerBalance -
                    ((oldStakerBalance * percentage) / denominator);

                staker[stakerAddress].push(newInfo);
            }
            // push to
            stakersDeposit.push(stakingInfo);

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
                // update StakingInfo struct
                StakingInfo memory newInfo;
                newInfo.balanceTimeStamp = block.timestamp;
                newInfo.stakeBalance = 0;

                address stakerAddress = stakersList[i];
                staker[stakerAddress].push(newInfo);
            }
            // clean stakerList array
            delete stakerList;
            // if stakersDeposit not enough use projectDeposit to pay the rest
            uint256 remainingCost = _amount -
                stakersDeposits[stakingLenght].stakeBalance;
            // descrease project deposit by the remaining amount
            projectDeposit -= remainingCost;

            // set stakers deposit to 0
            StakingInfo memory stakingInfo;
            stakingInfo.balanceTimeStamp = block.timestamp;
            stakingInfo.stakeBalance = stakersDeposits[stakingLenght]
                .stakeBalance;
            stakersDeposit.push(stakingInfo);

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
        uint256 saloonCommission = (_amount * bountyCommission) / denominator;
        uint256 hunterPayout = _amount - saloonCommission;
        // transfer to hunter
        IERC20(_token).safeTransfer(_hunter, hunterPayout);
        // transfer commission to saloon address
        IERC20(_token).safeTransfer(_saloonWallet, saloonCommission);

        return true;
    }

    // ADMIN HARVEST FEES
    function collectSaloonPremiumFees(address _token, address _saloonWallet)
        external
        onlyManager
        returns (uint256)
    {
        uint256 totalCollected = saloonPremiumFees;

        // reset claimable fees
        saloonPremiumFees = 0;

        // send current fees to saloon address
        IERC20(_token).safeTransfer(_saloonWallet, totalCollected);

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

        if (firstDeposit == false) {
            stakingPause = block.timestamp + PERIOD;
            firstDeposit = true;
        }

        // update deposit variable
        projectDeposit += _amount;

        return true;
    }

    function schedulePoolCapChange(uint256 _newPoolCap) external onlyManager {
        poolCapTimelock.timelock = block.timestamp + PERIOD;
        poolCapTimelock.amount = _newPoolCap;
        poolCapTimelock.executed = false;
    }

    // PROJECT SET CAP
    function setPoolCap(uint256 _amount) external onlyManager {
        // check timelock if current poolCap != 0
        if (poolCap != 0) {
            TimelockInfo memory poolCapLock = poolCapTimelock;
            // Check If queued check time has passed && its hasnt been executed && timestamp cant be =0
            require(
                poolCapLock.timelock < block.timestamp &&
                    poolCapLock.executed == false &&
                    poolCapLock.amount == _amount &&
                    poolCapLock.timelock != 0,
                "Timelock not set or not completed"
            );
            // set executed to true
            poolCapTimelock.executed = true;
        }

        poolCap = _amount;
    }

    function scheduleAPYChange(uint256 _newAPY) external onlyManager {
        APYTimelock.timelock = block.timestamp + PERIOD;
        APYTimelock.amount = _newAPY;
        APYTimelock.executed = false;
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
        uint256 _desiredAPY // make sure APY has right amount of decimals (1e18)
    ) public onlyManagerOrSelf returns (bool) {
        // check timelock if current APY != 0
        if (desiredAPY != 0) {
            TimelockInfo memory APYLock = APYTimelock;
            // Check If queued check time has passed && its hasnt been executed && timestamp cant be =0
            require(
                APYLock.timelock < block.timestamp &&
                    APYLock.executed == false &&
                    APYLock.amount == _desiredAPY &&
                    APYLock.timelock != 0,
                "Timelock not set or not completed"
            );
            // set executed to true
            APYTimelock.executed = true;
        }
        uint256 currentPremiumBalance = premiumBalance;
        uint256 newRequiredPremiumBalancePerPeriod;
        StakingInfo[] memory stakersDeposits = stakersDeposit;
        uint256 stakingLenght = stakersDeposits.length;
        if (stakingLenght != 0) {
            if (stakersDeposits[stakingLenght - 1].stakeBalance != 0) {
                // bill all premium due before changing APY
                billPremium(_token, _projectWallet);
            }
        } else {
            // ensure there is enough premium balance to pay stakers new APY for one period
            newRequiredPremiumBalancePerPeriod =
                (((poolCap * _desiredAPY) / denominator) / YEAR) *
                PERIOD;
            // note: this might lead to leftover premium if project decreases APY, we will see what to do about that later
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
        if (stakersList.length > 0) {
            uint256 length = stakersList.length - 1;
            for (uint256 i; i < length; ) {
                address stakerAddress = stakersList[i];
                uint256 arraySize = staker[stakerAddress].length - 1;

                StakingInfo memory newInfo;
                // get last balance
                newInfo.stakeBalance = staker[stakerAddress][arraySize]
                    .stakeBalance;
                // update current time
                newInfo.balanceTimeStamp = block.timestamp;
                // push to array so user can claim it.
                staker[stakerAddress].push(newInfo);

                unchecked {
                    ++i;
                }
            }
        }
        // disable instant withdrawals
        APYdropped = false;

        return true;
    }

    function calculatePremiumOwed(
        uint256 _apy,
        uint256 _stakingLenght,
        uint256 _lastPaid,
        StakingInfo[] memory _stakersDeposits
    ) internal returns (uint256) {
        uint256 premiumOwed;
        for (uint256 i; i < _stakingLenght; ++i) {
            // see how many changes since lastPaid
            if (_stakersDeposits[i].balanceTimeStamp > _lastPaid) {
                stakeChanges.push(i);
                // premiumOwed = _stakersDeposits[1].balanceTimeStamp;
            }
        }

        uint256[] memory stakingChanges = stakeChanges;
        uint256 length = stakingChanges.length;
        uint256 duration;

        // if no staking happened since lastPaid
        if (length == 0) {
            duration = block.timestamp - _lastPaid;

            premiumOwed =
                ((
                    ((_stakersDeposits[_stakingLenght - 1].stakeBalance *
                        _apy) / denominator)
                ) / YEAR) *
                duration;

            // if only one change was made between lastPaid and now
        } else if (length == 1) {
            if (_lastPaid == 0) {
                duration =
                    block.timestamp -
                    _stakersDeposits[0].balanceTimeStamp;
                premiumOwed =
                    ((
                        ((_stakersDeposits[0].stakeBalance * _apy) /
                            denominator)
                    ) / YEAR) *
                    duration;
            } else {
                duration = (_stakersDeposits[stakingChanges[0]]
                    .balanceTimeStamp - _lastPaid);

                premiumOwed +=
                    ((
                        ((_stakersDeposits[stakingChanges[0] - 1].stakeBalance *
                            _apy) / denominator)
                    ) / YEAR) *
                    duration;

                uint256 duration2 = (block.timestamp -
                    _stakersDeposits[stakingChanges[0]].balanceTimeStamp);

                premiumOwed +=
                    ((
                        ((_stakersDeposits[stakingChanges[0]].stakeBalance *
                            _apy) / denominator)
                    ) / YEAR) *
                    duration2;
            }
            // if there were multiple changes in stake balance between lastPaid and now
        } else {
            for (uint256 i; i < length; ++i) {
                // calculate payout for every change in staking according to time

                if (_lastPaid == 0) {
                    if (i == length - 1) {
                        duration =
                            block.timestamp -
                            _stakersDeposits[stakingChanges[i]]
                                .balanceTimeStamp;
                    } else {
                        duration =
                            _stakersDeposits[stakingChanges[i + 1]]
                                .balanceTimeStamp -
                            _stakersDeposits[stakingChanges[i]]
                                .balanceTimeStamp;
                    }
                } else {
                    if (i == 0) {
                        // calculate duration from lastPaid with last value
                        duration =
                            _stakersDeposits[stakingChanges[i]]
                                .balanceTimeStamp -
                            _lastPaid;

                        premiumOwed +=
                            ((
                                ((_stakersDeposits[stakingChanges[i] - 1]
                                    .stakeBalance * _apy) / denominator)
                            ) / YEAR) *
                            duration;
                        // calculate duration from current i to next i with current value
                        uint256 duration2 = _stakersDeposits[
                            stakingChanges[i] + 1
                        ].balanceTimeStamp -
                            _stakersDeposits[stakingChanges[i]]
                                .balanceTimeStamp;

                        premiumOwed +=
                            ((
                                ((_stakersDeposits[stakingChanges[i]]
                                    .stakeBalance * _apy) / denominator)
                            ) / YEAR) *
                            duration2;
                    } else if (i == length - 1) {
                        duration =
                            block.timestamp -
                            _stakersDeposits[stakingChanges[i]]
                                .balanceTimeStamp;
                        premiumOwed +=
                            ((
                                ((_stakersDeposits[stakingChanges[i]]
                                    .stakeBalance * _apy) / denominator)
                            ) / YEAR) *
                            duration;
                    } else {
                        // if i is in between first and last
                        duration =
                            _stakersDeposits[stakingChanges[i + 1]]
                                .balanceTimeStamp -
                            _stakersDeposits[stakingChanges[i]]
                                .balanceTimeStamp;

                        premiumOwed +=
                            ((
                                ((_stakersDeposits[stakingChanges[i]]
                                    .stakeBalance * _apy) / denominator)
                            ) / YEAR) *
                            duration;
                    }
                }
            }
        }

        delete stakeChanges;
        return premiumOwed;
    }

    // PROJECT PAY weekly/monthly PREMIUM to this address
    // this address needs to be approved first
    function billPremium(address _token, address _projectWallet)
        public
        onlyManagerOrSelf
        returns (bool)
    {
        StakingInfo[] memory stakersDeposits = stakersDeposit;
        uint256 stakingLenght = stakersDeposits.length;
        uint256 lastPaid = lastTimePaid;
        uint256 apy = desiredAPY;

        // check when function was called last time and pay premium according to how much time has passed since then.
        /*
        - average variance since last paid
            - needs to take into account how long each variance is...
        - use that
        */
        // this is very granular and maybe not optimal...
        uint256 premiumOwed = calculatePremiumOwed(
            apy,
            stakingLenght,
            lastPaid,
            stakersDeposits
        );
        // note try/catch should handle both revert and fails from transferFrom;
        try
            IERC20(_token).transferFrom(
                _projectWallet,
                address(this),
                premiumOwed
            )
        returns (bool result) {
            // If return valid is 0 run same things on catch block
            if (result == false) {
                // if transfer fails APY is reset and premium is paid with new APY
                // register new APYperiod
                APYperiods memory newAPYperiod;
                newAPYperiod.timeStamp = block.timestamp;
                newAPYperiod.periodAPY = viewcurrentAPY();
                APYrecords.push(newAPYperiod);
                // set new APY
                uint256 newAPY = viewcurrentAPY();
                setDesiredAPY(_token, _projectWallet, newAPY);

                return false;
            }
        } catch {
            // if transfer fails APY is reset and premium is paid with new APY
            // register new APYperiod
            APYperiods memory newAPYperiod;
            newAPYperiod.timeStamp = block.timestamp;
            newAPYperiod.periodAPY = viewcurrentAPY();
            APYrecords.push(newAPYperiod);
            // set new APY
            uint256 newAPY = viewcurrentAPY();
            setDesiredAPY(_token, _projectWallet, newAPY);
            return false;
        }
        // Calculate saloon fee
        uint256 saloonFee = (premiumOwed * premiumCommission) / denominator;

        // update saloon claimable fee
        saloonPremiumFees += saloonFee;

        // update premiumBalance
        premiumBalance += premiumOwed;

        lastTimePaid = block.timestamp;

        // disable instant withdrawals
        APYdropped = false;

        return true;
    }

    function scheduleprojectDepositWithdrawal(uint256 _amount)
        external
        onlyManager
        returns (bool)
    {
        withdrawalTimelock.timelock = block.timestamp + PERIOD;
        withdrawalTimelock.timeLimit = block.timestamp + PERIOD + 3 days;
        withdrawalTimelock.amount = _amount;
        withdrawalTimelock.executed = false;
        // note timelock should have a limit window. Currently discussing how long that window should be
        return true;
    }

    // PROJECT DEPOSIT WITHDRAWAL
    function projectDepositWithdrawal(
        address _token,
        address _projectWallet,
        uint256 _amount
    ) external onlyManager returns (bool) {
        TimelockInfo memory withdrawalLock = withdrawalTimelock;
        // time lock check
        // Check If queued check time has passed && its hasnt been executed && timestamp cant be =0
        require(
            withdrawalLock.timelock < block.timestamp &&
                withdrawalLock.timeLimit > block.timestamp &&
                withdrawalLock.executed == false &&
                withdrawalLock.amount >= _amount &&
                withdrawalLock.timelock != 0,
            "Timelock not set or not completed"
        );
        withdrawalTimelock.executed = true;

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
        //check if initial post staking period has passed
        require(stakingPause < block.timestamp, "Staking not open just yet");
        // dont allow staking if stakerDeposit >= poolCap
        StakingInfo[] memory stakersDeposits = stakersDeposit;
        uint256 stakingLenght = stakersDeposits.length;

        if (stakingLenght == 0) {
            StakingInfo memory init;
            init.stakeBalance = 0;
            init.balanceTimeStamp = 0;
            stakersDeposit.push(init);
        }
        uint256 positioning = stakersDeposit.length - 1;

        require(
            stakersDeposit[positioning].stakeBalance + _amount <= poolCap,
            "Staking Pool already full"
        );

        uint256 arrayLength = staker[_staker].length;

        //  if array length is  == 0 we must push first
        if (arrayLength == 0) {
            StakingInfo memory init;
            init.stakeBalance = 0;
            init.balanceTimeStamp = 0;
            staker[_staker].push(init);
        }

        uint256 position = staker[_staker].length - 1;

        // Push to stakerList array if previous balance = 0
        if (staker[_staker][position].stakeBalance == 0) {
            stakerList.push(_staker);
        }

        // update StakingInfo struct
        StakingInfo memory newInfo;
        newInfo.balanceTimeStamp = block.timestamp;
        newInfo.stakeBalance = staker[_staker][position].stakeBalance + _amount;

        // if staker is new update array[0] created earlier
        if (arrayLength == 0) {
            staker[_staker][position] = newInfo;
        } else {
            // if staker is not new:
            // save info to storage
            staker[_staker].push(newInfo);
        }

        StakingInfo memory depositInfo;
        depositInfo.stakeBalance =
            stakersDeposit[positioning].stakeBalance +
            _amount;

        depositInfo.balanceTimeStamp = block.timestamp;

        if (stakingLenght == 0) {
            stakersDeposit[positioning] = depositInfo;
        } else {
            // push to global stakersDeposit
            stakersDeposit.push(depositInfo);
        }

        // transferFrom to this address
        IERC20(_token).safeTransferFrom(_staker, address(this), _amount);

        return true;
    }

    function scheduleUnstake(address _staker, uint256 _amount)
        external
        onlyManager
        returns (bool)
    {
        StakingInfo[] memory stakr = staker[_staker];
        uint256 arraySize = stakr.length - 1;

        require(
            stakr[arraySize].stakeBalance >= _amount,
            "Insuficcient balance"
        );

        stakerTimelock[_staker].timelock = block.timestamp + PERIOD;
        stakerTimelock[_staker].timeLimit = block.timestamp + PERIOD + 3 days;
        stakerTimelock[_staker].amount = _amount;
        stakerTimelock[_staker].executed = false;

        return true;
    }

    // UNSTAKING
    // otherwise have to wait for timelock period
    function unstake(
        address _token,
        address _staker,
        uint256 _amount
    ) external onlyManager returns (bool) {
        // note allow for immediate withdrawal if APY drops from desired APY ??
        // if (desiredAPY != 0 || APYdropped == true) {
        StakingInfo[] memory stakersDeposits = stakersDeposit;
        uint256 stakingLenght = stakersDeposits.length - 1;

        if (
            desiredAPY != 0 ||
            poolCap > stakersDeposits[stakingLenght].stakeBalance
        ) {
            TimelockInfo memory stakrTimelock = stakerTimelock[_staker];
            // time lock check
            // Check If queued check time has passed && its hasnt been executed && timestamp cant be =0
            require(
                stakrTimelock.timelock < block.timestamp &&
                    stakrTimelock.timeLimit > block.timestamp &&
                    stakrTimelock.executed == false &&
                    stakrTimelock.amount >= _amount &&
                    stakrTimelock.timelock != 0,
                "Timelock not set or not completed"
            );
            stakerTimelock[_staker].executed = true;
        }
        uint256 arraySize = staker[_staker].length - 1;

        // decrease staker balance
        // update StakingInfo struct
        StakingInfo memory newInfo;
        newInfo.balanceTimeStamp = block.timestamp;
        newInfo.stakeBalance =
            staker[_staker][arraySize].stakeBalance -
            _amount;

        address[] memory stakersList = stakerList;
        // delete from staker list
        // note if 18 decimals are not used properly at some stage this might never be true.
        if (newInfo.stakeBalance == 0) {
            // loop through stakerlist
            uint256 length = stakersList.length;
            for (uint256 i; i < length; ) {
                // find staker
                if (stakersList[i] == _staker) {
                    // get value in the last array position
                    address lastAddress = stakersList[length - 1];
                    // replace it to the current position
                    stakerList[i] = lastAddress;

                    // pop last array value
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

        StakingInfo memory depositInfo;
        depositInfo.stakeBalance =
            stakersDeposits[stakingLenght].stakeBalance -
            _amount;
        depositInfo.balanceTimeStamp = block.timestamp;

        // decrease global stakersDeposit
        stakersDeposit.push(depositInfo);

        // transfer it out
        IERC20(_token).safeTransfer(_staker, _amount);

        return true;
    }

    // claim premium

    function claimPremium(
        address _token,
        address _staker,
        address _projectWallet
    ) external onlyManager returns (uint256, bool) {
        // how many chunks of time (currently = 2 weeks) since lastclaimed?
        uint256 lastTimeClaimed = lastClaimed[_staker];
        // uint lastTimeClaimed = 0;

        StakingInfo[] memory stakerInfo = staker[_staker];
        uint256 stakerLength = stakerInfo.length;
        uint256 currentPremiumBalance = premiumBalance;

        uint256 totalPremiumToClaim = calculatePremiumToClaim(
            lastTimeClaimed,
            stakerInfo,
            stakerLength
        );
        // Calculate saloon fee
        uint256 saloonFee = (totalPremiumToClaim * premiumCommission) /
            denominator;
        // subtract saloon fee
        totalPremiumToClaim -= saloonFee;
        uint256 owedPremium = totalPremiumToClaim;

        // if premium belance < owedPremium
        //  call billpremium
        // transfer
        if (currentPremiumBalance < owedPremium) {
            billPremium(_token, _projectWallet);
        }
        IERC20(_token).transfer(_staker, owedPremium);

        // update premiumBalance
        premiumBalance -= totalPremiumToClaim;

        // update last time claimed
        lastClaimed[_staker] = block.timestamp;
        return (owedPremium, true);
    }

    function calculateBalancePerPeriod(
        uint256 _lastTimeClaimed,
        StakingInfo[] memory _stakerInfo,
        uint256 _stakerLength,
        APYperiods[] memory APYrecord
    ) internal returns (uint256) {
        uint256 length = APYrecord.length;
        uint256 totalPeriodClaim;
        uint256 periodStart;
        uint256 periodEnd;
        if (_lastTimeClaimed == 0) {
            for (uint256 i; i < length; ++i) {
                periodStart = APYrecord[i].timeStamp;

                // period end is equal NOW for last APY that has been set
                if (i == length - 1) {
                    periodEnd = block.timestamp;
                } else {
                    periodEnd = APYrecord[i + 1].timeStamp;
                }
                uint256 apy = APYrecord[i].periodAPY;
                // loop through stakers balance fluctiation during this period
                totalPeriodClaim += calculateBalance(
                    apy,
                    periodStart,
                    periodEnd,
                    _stakerInfo,
                    _stakerLength
                );
            }
        } else {
            for (uint256 i; i < length; ++i) {
                /* 
                - See what's the last one to be < lastTimeClaimed
                - calculate distance between last time claimed and 
                APYrecords.TimeStamp[i+1] period start 
                - judge distance in comparison with i+1 until last i that compares distance to block.timestamp
                */
                if (APYrecord[i].timeStamp > _lastTimeClaimed) {
                    APYChanges.push(i - 1);
                    // push last period too
                    if (i == length - 1) {
                        APYChanges.push(i);
                    }
                }
            }
            uint256[] memory APYChange = APYChanges;
            uint256 len = APYChange.length;

            for (uint256 i; i < len; ++i) {
                if (i == 0) {
                    periodStart = _lastTimeClaimed;
                } else {
                    periodStart = APYrecord[APYChange[i]].timeStamp;
                }

                // period end is equal NOW for last APY that has been set
                if (i == length - 1) {
                    periodEnd = block.timestamp;
                } else {
                    periodEnd = APYrecord[APYChange[i + 1]].timeStamp;
                }
                uint256 apy = APYrecord[APYChange[i]].periodAPY;
                // loop through stakers balance fluctiation during this period
                totalPeriodClaim += calculateBalance(
                    apy,
                    periodStart,
                    periodEnd,
                    _stakerInfo,
                    _stakerLength
                );
            }
        }
        return totalPeriodClaim;
    }

    function calculateBalance(
        uint256 apy,
        uint256 _periodStart,
        uint256 _periodEnd,
        StakingInfo[] memory _stakerInfo,
        uint256 _stakerLength
    ) internal returns (uint256) {
        uint256 balanceClaim;
        uint256 duration;
        {
            for (uint256 i; i < _stakerLength; ++i) {
                // check staker balance at that moment
                if (
                    _stakerInfo[i].balanceTimeStamp >= _periodStart &&
                    _stakerInfo[i].balanceTimeStamp < _periodEnd
                ) {
                    stakerChange.push(i);
                }
            }
        }
        {
            uint256[] memory stakrChange = stakerChange;
            uint256 len = stakrChange.length;
            for (uint256 i; i < len; ++i) {
                // check distance difference to period start

                if (i == len - 1) {
                    duration =
                        _periodEnd -
                        _stakerInfo[stakrChange[i]].balanceTimeStamp;
                } else {
                    duration =
                        _stakerInfo[stakrChange[i + 1]].balanceTimeStamp -
                        _stakerInfo[stakrChange[i]].balanceTimeStamp;
                }

                // calculate timestampClaim
                uint256 periodClaim = (((_stakerInfo[stakrChange[i]]
                    .stakeBalance * apy) / denominator) / YEAR) * duration;

                balanceClaim += periodClaim;
            }
        }
        delete stakerChange;
        return balanceClaim;
    }

    function calculatePremiumToClaim(
        uint256 _lastTimeClaimed,
        StakingInfo[] memory _stakerInfo,
        uint256 _stakerLength
    ) internal returns (uint256) {
        // cache APY records
        APYperiods[] memory APYregistries = APYrecords;
        // loop through APY periods  until last missed period is found
        uint256 claim;
        claim = calculateBalancePerPeriod(
            _lastTimeClaimed,
            _stakerInfo,
            _stakerLength,
            APYregistries
        );

        return claim;
    }

    ///// VIEW FUNCTIONS /////

    // View currentAPY
    function viewcurrentAPY() public view returns (uint256) {
        uint256 apy = (premiumBalance * PRECISION) / poolCap;
        return apy;
    }

    // View total balance
    function viewHackerPayout() external view returns (uint256) {
        StakingInfo[] memory stakersDeposits = stakersDeposit;
        uint256 stakingLenght = stakersDeposits.length;
        uint256 totalBalance;
        if (stakingLenght == 0) {
            totalBalance = projectDeposit;
        } else {
            totalBalance =
                projectDeposit +
                stakersDeposits[stakingLenght - 1].stakeBalance;
        }
        uint256 saloonCommission = (totalBalance * bountyCommission) /
            denominator;

        return totalBalance - saloonCommission;
    }

    function viewBountyBalance() external view returns (uint256) {
        StakingInfo[] memory stakersDeposits = stakersDeposit;
        uint256 stakingLenght = stakersDeposits.length;
        uint256 totalBalance;
        if (stakingLenght == 0) {
            totalBalance = projectDeposit;
        } else {
            totalBalance =
                projectDeposit +
                stakersDeposits[stakingLenght - 1].stakeBalance;
        }

        return totalBalance;
    }

    // View stakersDeposit balance
    function viewStakersDeposit() external view returns (uint256) {
        StakingInfo[] memory stakersDeposits = stakersDeposit;
        uint256 stakingLenght = stakersDeposits.length;
        if (stakingLenght == 0) {
            return 0;
        } else {
            return stakersDeposit[stakingLenght - 1].stakeBalance;
        }
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
        if (length == 0) {
            return (0, 0);
        } else {
            return (
                staker[_staker][length - 1].stakeBalance,
                staker[_staker][length - 1].balanceTimeStamp
            );
        }
    }

    function viewUserTimelock(address _staker)
        external
        view
        returns (
            uint256 timelock,
            uint256 amount,
            bool executed
        )
    {
        timelock = stakerTimelock[_staker].timelock;
        amount = stakerTimelock[_staker].amount;
        executed = stakerTimelock[_staker].executed;
    }

    //note view version function??

    ///// VIEW FUNCTIONS END /////
}
