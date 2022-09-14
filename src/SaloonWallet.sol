//SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

contract SaloonWallet {
    uint256 public constant BOUNTY_COMMISSION = 12 * 1e18;
    uint256 public constant DENOMINATOR = 100 * 1e18;

    address public immutable manager;

    // premium fees to collect
    uint256 public premiumFees;
    uint256 public saloonTotalBalance;
    uint256 public cummulativeHackerPayouts;

    // hunter balance per token
    // hunter address => token address => amount
    mapping(address => mapping(address => uint256)) public hunterTokenBalance;

    // saloon balance per token
    // token address => amount
    mapping(address => uint256) public saloonTokenBalance;

    constructor(address _manager) {
        manager = _manager;
    }

    modifier onlyManager() {
        require(msg.sender == manager, "Only manager allowed");
        _;
    }

    // bountyPaid
    function bountyPaid(
        address _token,
        address _hunter,
        uint256 _amount
    ) external onlyManager {
        // calculate commision
        uint256 saloonCommission = (_amount * BOUNTY_COMMISSION) / DENOMINATOR;
        uint256 hunterPayout = _amount - saloonCommission;
        // update variables and mappings
        hunterTokenBalance[_hunter][_token] += hunterPayout;
        cummulativeHackerPayouts += hunterPayout;
        saloonTokenBalance[_token] += saloonCommission;
        saloonTotalBalance += saloonCommission;
        // set timelock for saloon to be able to withdraw hunters payout (1 year)
    }

    function premiumFeesCollected(address _token, uint256 _amount)
        external
        onlyManager
    {
        saloonTokenBalance[_token] += _amount;
        premiumFees += _amount;
        saloonTotalBalance += _amount;
    }

    //
    // WITHDRAW FUNDS TO ANY ADDRESS saloon admin
    function withdrawSaloonFunds(
        address _token,
        address _to,
        uint256 _amount
    ) external onlyManager returns (bool) {
        require(_amount <= saloonTokenBalance[_token], "not enough balance");
        // decrease saloon funds
        saloonTokenBalance[_token] -= _amount;
        saloonTotalBalance -= _amount;

        _token.safeTransfer(_to, _amount);

        return true;
    }

    // HUNTER WITHDRAW PAYOUT
    function withdrawHackerPayout(address _token, address _hunter)
        external
        onlyManager
        returns (bool)
    {
        uint256 payout = hunterTokenBalance[_hunter][_token];
        hunterTokenBalance[_hunter][_token] -= payout;
        _token.safeTransfer(_hunter, payout);
        return true;
    }

    // VIEW SALOON TOTAL BALANCE
    function viewSaloonBalance() external view returns (uint256) {
        return saloonTotalBalance;
    }

    // VIEW TOTAL HELD PAYOUTS - commission - fees

    // VIEW CUMMULATIVE HACKER PAYOUTS

    // VIEW TOTAL COMMISSION

    // VIEW TOTAL IN PREMIUMS
}
