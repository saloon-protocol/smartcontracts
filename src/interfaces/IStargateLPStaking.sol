// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;
pragma abicoder v2;

interface IStargateLPStaking {
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
    }

    function deposit(uint256 _pid, uint256 _amount) external;

    function withdraw(uint256 _pid, uint256 _amount) external;

    function pendingStargate(uint256 _pid, address _user)
        external
        view
        returns (uint256);

    function userInfo(uint256 _pid, address _user)
        external
        view
        returns (uint256, uint256);

    function poolInfo(uint256 _pid)
        external
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256
        );

    function stargatePerBlock() external view returns (uint256);
}
