pragma solidity ^0.8.10;

interface IManagerFacet {
    event NewBountyDeployed(
        uint256 indexed pid,
        address indexed token,
        uint256 tokenDecimals
    );
    event PremiumBilled(uint256 indexed pid, uint256 amount);
    event referralPaid(address indexed referrer, uint256 amount);
    event tokenWhitelistUpdated(
        address indexed token,
        bool indexed whitelisted
    );

    function addNewBountyPool(
        address _token,
        address _projectWallet,
        string memory _projectName,
        address _referrer,
        uint256 _referralFee,
        uint256 _referralEndTime
    ) external returns (uint256);

    function billPremium(uint256 _pid) external returns (bool);

    function collectAllReferralProfits() external returns (bool);

    function collectAllSaloonProfits(
        address _saloonWallet
    ) external returns (bool);

    function collectReferralProfit(address _token) external returns (bool);

    function collectSaloonProfits(
        address _token,
        address _saloonWallet
    ) external returns (bool);

    function extendReferralPeriod(uint256 _pid, uint256 _endTime) external;

    function setStrategyFactory(address _strategyFactory) external;

    function startAssessmentPeriod(uint256 _pid) external;

    function updateTokenWhitelist(
        address _token,
        bool _whitelisted,
        uint256 _minStakeAmount
    ) external returns (bool);
}
