pragma solidity ^0.8.10;

interface IBountyFacet {
    event BountyBalanceChanged(
        uint256 indexed pid,
        uint256 oldAmount,
        uint256 newAmount
    );
    event BountyPaid(
        address indexed hunter,
        address indexed token,
        uint256 amount
    );
    event PremiumBilled(uint256 indexed pid, uint256 amount);
    event Staked(address indexed user, uint256 indexed pid, uint256 amount);
    event Unstaked(address indexed user, uint256 indexed pid, uint256 amount);
    event WithdrawalOrUnstakeScheduled(uint256 indexed pid, uint256 amount);

    function calculateEffectiveAPY(
        uint256 _pid,
        uint256 _stake,
        uint256 _x
    ) external view returns (uint256 scaledAPY);

    function claimPremium(uint256 _tokenId) external;

    function consolidate(uint256 _pid) external;

    function consolidateAll() external;

    function getCurrentAPY(
        uint256 _pid
    ) external view returns (uint256 currentAPY);

    function payBounty(
        uint256 __pid,
        address _hunter,
        uint16 _payoutBPS,
        uint16 _hunterBonusBPS
    ) external;

    function payBountyDuringAssessment(
        uint256 _pid,
        address _hunter,
        uint16 _payoutBPS,
        uint16 _hunterBonusBPS
    ) external;

    function scheduleUnstake(uint256 _tokenId) external returns (bool);

    function stake(uint256 _pid, uint256 _amount) external returns (uint256);

    function unstake(
        uint256 _tokenId,
        bool _shouldHarvest
    ) external returns (bool);

    function viewBountyBalance(uint256 _pid) external view returns (uint256);

    function withdrawRemainingAPY(uint256 _pid) external;
}
