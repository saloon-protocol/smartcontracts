// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IStrategy {
    function depositToStrategy() external returns (uint256);

    function withdrawFromStrategy(uint256 _amount) external returns (uint256);

    function compound() external returns (uint256);

    function withdrawYield() external returns (uint256);

    function lpDepositBalance() external returns (uint256);
}
