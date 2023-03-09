pragma solidity ^0.8.17;

interface IProjectFacet {
    event BountyBalanceChanged(
        uint256 indexed pid,
        uint256 oldAmount,
        uint256 newAmount
    );

    event WithdrawalOrUnstakeScheduled(uint256 indexed pid, uint256 amount);

    function compoundYieldForPid(uint256 _pid) external;

    function makeProjectDeposit(
        uint256 _pid,
        uint256 _deposit,
        string memory _strategyName
    ) external;

    function projectDepositWithdrawal(
        uint256 _pid,
        uint256 _amount
    ) external returns (bool);

    function receiveStrategyYield(address _token, uint256 _amount) external;

    function setAPYandPoolCapAndDeposit(
        uint256 _pid,
        uint256 _poolCap,
        uint16 _apy,
        uint256 _deposit,
        string memory _strategyName
    ) external;

    function updateProjectWalletAddress(
        uint256 _pid,
        address _projectWallet
    ) external;

    function viewBountyBalance(uint256 _pid) external view returns (uint256);

    function windDownBounty(uint256 _pid) external returns (bool);

    function withdrawProjectYield(
        uint256 _pid
    ) external returns (uint256 returnedAmount);
}
