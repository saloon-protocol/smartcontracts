// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "openzeppelin-contracts/contracts/utils/math/SafeMath.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/ISaloon.sol";
import "./interfaces/IStrategy.sol";
import "./interfaces/IStargateRouter.sol";
import "./interfaces/IStargateLPStaking.sol";
import "./interfaces/IStargateLPToken.sol";
import "./interfaces/IUniswapRouter.sol";

/* Implement:
- TODO add back ownable
- TODO Slippage control
- TODO remove unnecessary view functions
*/

contract StargateStrategy is IStrategy {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    ISaloon public saloon;
    address public pendingOwner;

    uint256 public lpDepositBalance;

    uint256 FEE = 1000; //10% fee on all yield
    uint256 BPS = 10000;

    IStargateRouter public stargateRouter;
    IStargateLPStaking public stargateLPStaking;
    IStargateLPToken public stargateLPToken;
    IUniswapRouter public uniswapRouter;
    IERC20 public constant USDC =
        IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 public constant STG =
        IERC20(0xAf5191B0De278C7286d6C7CC6ab6BB8A73bA2Cd6);
    address public constant WETH9 = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    uint24 public constant poolFee = 3000;

    modifier onlyOwner() {
        require(msg.sender == address(saloon), "Not authorized");
        _;
    }

    constructor(address _owner) {
        stargateRouter = IStargateRouter(
            0x8731d54E9D02c286767d56ac03e8037C07e01e98
        );
        stargateLPStaking = IStargateLPStaking(
            0xB0D502E938ed5f4df2E681fE6E419ff29631d62b
        );
        stargateLPToken = IStargateLPToken(
            0xdf0770dF86a8034b3EFEf0A1Bb3c889B8332FF56
        ); //S*USDC
        uniswapRouter = IUniswapRouter(
            0xE592427A0AEce92De3Edee1F18E0157C05861564
        );

        USDC.approve(_owner, type(uint256).max);
        saloon = ISaloon(_owner);
    }

    function setPendingOwner(address _pendingOwner) external onlyOwner {
        pendingOwner = _pendingOwner;
    }

    function acceptOwnershipTransfer() external {
        require(msg.sender == pendingOwner, "Not pending owner");
        saloon = ISaloon(pendingOwner);
        pendingOwner = address(0);
    }

    function updateStargateAddresses(
        address _stargateRouter,
        address _stargateLPStaking,
        address _stargateLPToken
    ) external onlyOwner {
        if (_stargateRouter != address(0))
            stargateRouter = IStargateRouter(_stargateRouter);
        if (_stargateLPStaking != address(0))
            stargateLPStaking = IStargateLPStaking(_stargateLPStaking);
        if (_stargateLPToken != address(0))
            stargateLPToken = IStargateLPToken(_stargateLPToken);
    }

    function updateUniswapRouterAddress(address _uniswapRouter)
        external
        onlyOwner
    {
        if (_uniswapRouter != address(0))
            uniswapRouter = IUniswapRouter(_uniswapRouter);
    }

    function depositToStrategy(uint256 _poolId)
        public
        onlyOwner
        returns (uint256)
    {
        uint256 USDCBalance = USDC.balanceOf(address(this));
        USDC.approve(address(stargateRouter), USDCBalance);

        stargateRouter.addLiquidity(1, USDCBalance, address(this)); // 1 = Harcode for USDC LP
        uint256 lpBalanceAdded = stargateLPToken.balanceOf(address(this));

        stargateLPToken.approve(address(stargateLPStaking), lpBalanceAdded);
        stargateLPStaking.deposit(0, lpBalanceAdded); // PID 0 is S*USDC
        lpDepositBalance += lpBalanceAdded;

        return lpBalanceAdded;
    }

    function withdrawFromStrategy(uint256 _poolId, uint256 _amount)
        external
        onlyOwner
        returns (uint256)
    {
        require(_amount <= lpDepositBalance, "Not enough lp");
        lpDepositBalance -= _amount;
        stargateLPStaking.withdraw(0, _amount);
        uint256 lpBalanceAvailable = stargateLPToken.balanceOf(address(this));
        uint256 amountReturned = stargateRouter.instantRedeemLocal(
            uint16(_poolId),
            lpBalanceAvailable,
            address(this)
        );
        convertReward(address(this));
        uint256 fundsToReturn = USDC.balanceOf(address(this));
        USDC.safeTransfer(msg.sender, fundsToReturn);

        return fundsToReturn;
    }

    function compound() external onlyOwner returns (uint256) {
        stargateLPStaking.deposit(0, 0);
        convertReward(address(this));
        uint256 lpAdded = depositToStrategy(1);

        return lpAdded;
    }

    function withdrawYield() external onlyOwner returns (uint256) {
        stargateLPStaking.deposit(0, 0);
        uint256 returnedAmount = convertReward(msg.sender);

        return returnedAmount;
    }

    function convertReward(address _receiver) internal returns (uint256) {
        uint256 availableSTG = rewardBalance();
        if (availableSTG == 0) return 0;
        STG.approve(address(uniswapRouter), availableSTG);

        IUniswapRouter.ExactInputParams memory params = IUniswapRouter
            .ExactInputParams({
                path: abi.encodePacked(
                    address(STG),
                    poolFee,
                    WETH9,
                    poolFee,
                    address(USDC)
                ),
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: availableSTG,
                amountOutMinimum: 0
            });

        uint256 returnedAmount = uniswapRouter.exactInput(params);
        uint256 saloonFee = (returnedAmount * FEE) / BPS;
        uint256 amountMinusFee = returnedAmount - saloonFee;

        saloon.receiveStrategyYield(address(USDC), saloonFee);

        // Only transfer if receiver is not this contract. Otherwise, keep underlying here for compound.
        if (_receiver != address(this)) {
            USDC.safeTransfer(_receiver, amountMinusFee);
        }

        return returnedAmount;
    }

    function rewardBalance() public view returns (uint256) {
        return STG.balanceOf(address(this));
    }

    function pendingRewardBalance() external view returns (uint256) {
        return stargateLPStaking.pendingStargate(0, address(this)); // PID 0 is S*USDC
    }

    function userInfo() external view returns (uint256, uint256) {
        (uint256 amount, uint256 rewardDebt) = stargateLPStaking.userInfo(
            0,
            address(this)
        );
        return (amount, rewardDebt);
    }

    function poolInfo()
        external
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        (
            uint256 lpToken,
            uint256 allocPoint,
            uint256 lastRewardBlock,
            uint256 accStargatePerShare
        ) = stargateLPStaking.poolInfo(0);
        return (lpToken, allocPoint, lastRewardBlock, accStargatePerShare);
    }
}
