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
    uint256 public bountyBalance = projectDeposit + stakerDeposits;
    uint256 public APY;
    uint256 public insuranceCap;
    uint256 public lastTimePremiumWasPaid;
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

    // PROJECT SET APY
    // project must approve this address first.
    function setPremiumAPY(uint256 _amount) external onlyManager {
        // ensure there is enough premium balance to pay stakers new APY for a month
        // make sure APY has right amount of decimals
    }

    // PROJECT SET CAP
    // PROJECT WITHDRAWAL
    // PROJECT PAY PREMIUM
    // Current issue: if function doesnt get called in a month, premiuns wont be paid for that month.
    // could fix it to pay retroactively seeing how long since last time it has been paid... but seems like a waist of gas
    // we should be calling this every month in the manager collectPremiumForAll() function
    function payPremium() external onlyManager returns (bool) {
        // if premium has been paid less than a month ago, skip
        if (block.timestamp - lastTimePremiumWasPaid < 30 days) {
            return false;
        }
        // calculate monthly premium based on APY and insuranceCAP
        uint256 monthlyPremiumPayment = insuranceCap / APY;
        // do transfer
        token.safeTransferFrom(
            projectWallet,
            address(this, monthlyPremiumPayment)
        );
        // update premiumBalance
        token.premiumBalance += monthlyPremiumPayment;
        // update last time paid
        lastTimePremiumWasPaid = block.timestamp;
    }

    // STAKING
    // STAKING WITHDRAWAL
    // claim premium
    function claimPremium() {
        // update premiumBalance
    }

    ///// VIEW FUNCTIONS /////

    // View total balance
    // View staking balance
    // View deposit balance
    // View APY
    // View Cap
    // View user staking balance

    ///// VIEW FUNCTIONS END /////
}
