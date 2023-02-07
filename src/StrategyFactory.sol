// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.17;

import "./interfaces/IStrategy.sol";
import "./StargateStrategy.sol";

contract StrategyFactory {
    function deployStrategy(
        string memory _strategyName, //"Stargate"
        address _depositToken
    ) public returns (address) {
        IStrategy strategy;

        bytes32 strategyHash = keccak256(abi.encode(_strategyName));
        if (strategyHash == keccak256(abi.encode("Stargate"))) {
            strategy = new StargateStrategy(msg.sender, _depositToken);
        } else {
            return address(0);
        }

        return address(strategy);
    }
}
