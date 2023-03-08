// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "./Base.sol";

contract ManagerFacet is Base {
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
    ) external onlyOwner returns (uint256) {
        require(s.tokenWhitelist[_token], "token not whitelisted");
        require(_referralFee <= 5000, "referral fee too high");
        // uint8 _tokenDecimals = IERC20(_token).decimals();
        (, bytes memory _decimals) = _token.staticcall(
            abi.encodeWithSignature("decimals()")
        );
        uint8 decimals = abi.decode(_decimals, (uint8));
        require(decimals >= 6, "Invalid decimal return");

        PoolInfo memory newBounty;
        newBounty.generalInfo.token = IERC20(_token);
        newBounty.generalInfo.tokenDecimals = decimals;
        newBounty.generalInfo.projectWallet = _projectWallet;
        newBounty.generalInfo.projectName = _projectName;
        newBounty.referralInfo.referrer = _referrer;
        newBounty.referralInfo.referralFee = _referralFee;
        newBounty.referralInfo.endTime = _referralEndTime;
        s.poolInfo.push(newBounty);
        // emit event
        return (s.poolInfo.length - 1);
    }

    //NOTE FIXME - Function only here for testing purposes, move to ViewFacet/DiamondLoupe or something
    function viewBountyBalance(uint256 _pid) public view returns (uint256) {
        PoolInfo memory pool = s.poolInfo[_pid];
        return (pool.generalInfo.totalStaked +
            (pool.depositInfo.projectDepositHeld +
                pool.depositInfo.projectDepositInStrategy));
    }
}
