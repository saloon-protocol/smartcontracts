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

    address public depositToken;
    uint256 public depositPoolId;
    uint256 public stakingPoolId;

    uint256 public lpDepositBalance;

    uint256 FEE = 1000; //10% fee on all yield
    uint256 BPS = 10000;

    IStargateRouter public stargateRouter;
    IStargateLPStaking public stargateLPStaking;
    IStargateLPToken public stargateLPToken;
    IUniswapRouter public uniswapRouter;
    IERC20 public constant USDC =
        IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 public constant DAI =
        IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    IERC20 public constant STG =
        IERC20(0xAf5191B0De278C7286d6C7CC6ab6BB8A73bA2Cd6);
    address public constant WETH9 = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    uint24 public constant poolFee = 3000;

    modifier onlyOwner() {
        require(msg.sender == address(saloon), "Not authorized");
        _;
    }

    /// @notice Constructs the strategy contract. Sets proper addresses and approvals.
    /// @dev Initiated by Saloon._deployStrategyIfNeeded() => StrategyFactory.deployStrategy()
    /// @dev Includes Saloon commission + hunter payout
    /// @param _owner Owner of this contract. Contracts deployed through pipeline will be owned by Saloon.sol
    constructor(address _owner, address _depositToken) {
        require(_owner != address(0), "invalid owner");
        require(_depositToken != address(0), "invalid deposit token");

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

        saloon = ISaloon(_owner);
        depositToken = _depositToken;
        IERC20(depositToken).approve(_owner, type(uint256).max);

        if (depositToken == address(USDC)) {
            depositPoolId = 1;
            stakingPoolId = 0;
        } else if (depositToken == address(DAI)) {
            depositPoolId = 1;
            stakingPoolId = 0;
        }
    }

    /// @notice Update any or all of the necessary stargate addresses.
    /// @param _stargateRouter The router contract used for adding and removing liquidity.
    /// @param _stargateLPToken The LP Token that is provided as a result of adding liquidity.
    /// @param _stargateLPStaking The staking contract used to stake Stargate LP tokens.
    function updateStargateAddresses(
        address _stargateRouter,
        address _stargateLPToken,
        address _stargateLPStaking
    ) external onlyOwner {
        if (_stargateRouter != address(0))
            stargateRouter = IStargateRouter(_stargateRouter);
        if (_stargateLPToken != address(0))
            stargateLPToken = IStargateLPToken(_stargateLPToken);
        if (_stargateLPStaking != address(0))
            stargateLPStaking = IStargateLPStaking(_stargateLPStaking);
    }

    /// @notice Update the Uniswap router address used to swap STG for deposit token.
    /// @param _uniswapRouter The router contract used for swapping tokens.
    function updateUniswapRouterAddress(address _uniswapRouter)
        external
        onlyOwner
    {
        if (_uniswapRouter != address(0))
            uniswapRouter = IUniswapRouter(_uniswapRouter);
    }

    /// @notice Put all deposit tokens held in this contract to work.
    /// @dev Add liquidity to stargate router => receive LP tokens => deposit LP tokens into stargate LPStaking
    function depositToStrategy() public onlyOwner returns (uint256) {
        uint256 USDCBalance = USDC.balanceOf(address(this));
        USDC.approve(address(stargateRouter), USDCBalance);

        stargateRouter.addLiquidity(depositPoolId, USDCBalance, address(this)); // 1 = Harcode for USDC LP
        uint256 lpBalanceAdded = stargateLPToken.balanceOf(address(this));

        stargateLPToken.approve(address(stargateLPStaking), lpBalanceAdded);
        stargateLPStaking.deposit(stakingPoolId, lpBalanceAdded); // PID 0 is S*USDC
        lpDepositBalance += lpBalanceAdded;

        return lpBalanceAdded;
    }

    /// @notice Withdraw deposited LP from staking contract, remove liquidity, and send to caller
    /// @dev Automatically converts pending yield to deposit token and sends entire contract balance.
    /// @param _amount Amount of LP tokens to withdraw from strategy.
    function withdrawFromStrategy(uint256 _amount)
        external
        onlyOwner
        returns (uint256)
    {
        require(_amount <= lpDepositBalance, "Not enough lp");
        lpDepositBalance -= _amount;
        stargateLPStaking.withdraw(stakingPoolId, _amount);
        uint256 lpBalanceAvailable = stargateLPToken.balanceOf(address(this));
        uint256 amountReturned = stargateRouter.instantRedeemLocal(
            uint16(depositPoolId),
            lpBalanceAvailable,
            address(this)
        );
        _convertReward(address(this));
        uint256 fundsToReturn = USDC.balanceOf(address(this));
        USDC.safeTransfer(msg.sender, fundsToReturn);

        return fundsToReturn;
    }

    /// @notice Convert pending reward into deposit token and deposit.
    function compound() external onlyOwner returns (uint256) {
        stargateLPStaking.deposit(0, 0);
        _convertReward(address(this));
        uint256 lpAdded = depositToStrategy();

        return lpAdded;
    }

    /// @notice Withdraw all pending yield from strategy to caller.
    /// @dev 10% Saloon fee automatically taken when converting yield to deposit token.
    function withdrawYield() external onlyOwner returns (uint256) {
        stargateLPStaking.deposit(0, 0);
        uint256 returnedAmount = _convertReward(msg.sender);

        return returnedAmount;
    }

    /// @notice Convert all pending yield into deposit token.
    /// @dev 10% Saloon fee automatically taken when converting yield to deposit token.
    function _convertReward(address _receiver) internal returns (uint256) {
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

    /// @notice The balance of yield tokens currently in the contract.
    function rewardBalance() public view returns (uint256) {
        return STG.balanceOf(address(this));
    }

    /// @notice The amount of pending token owed to this contract due to deposit.
    function pendingRewardBalance() external view returns (uint256) {
        return stargateLPStaking.pendingStargate(0, address(this)); // PID 0 is S*USDC
    }
}
