// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.17;

interface IStrategyFactory {
    function deployStrategy(string memory _strategyName, address _depositToken)
        external
        returns (address);
}
