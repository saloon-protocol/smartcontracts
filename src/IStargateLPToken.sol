// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;
pragma abicoder v2;

interface IStargateLPToken {
    function balanceOf(address) external returns (uint256);

    function approve(address, uint256) external;
}
