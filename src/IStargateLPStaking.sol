// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;
pragma abicoder v2;

interface IStargateLPStaking {
    function deposit(uint256 _pid, uint256 _amount) external;

    function withdraw(uint256 _pid, uint256 _amount) external;

    function pendingStargate(uint256 _pid, address _user)
        external
        view
        returns (uint256);
}
