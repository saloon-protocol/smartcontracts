// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IStrategy {
    function depositToStrategy(uint256 _poolId) external returns (uint256);

    function withdrawFromStrategy(uint256 _poolId, uint256 _amount)
        external
        returns (uint256);

    function compound() external returns (uint256);

    function withdrawYield() external returns (uint256);
}
