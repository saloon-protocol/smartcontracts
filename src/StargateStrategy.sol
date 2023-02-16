// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "openzeppelin-contracts/contracts/utils/math/SafeMath.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/ISaloon.sol";
import "./interfaces/IStrategy.sol";
import "./interfaces/IStargateRouter.sol";
import "./interfaces/IStargateLPStaking.sol";
import "./interfaces/IStargateLPToken.sol";
import "./interfaces/IUniswapV2Router.sol";

/* Implement:
- TODO Slippage control
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
    IUniswapV2Router public swapRouter;

    IERC20 public constant USDC =
        IERC20(0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174);
    IERC20 public constant USDT =
        IERC20(0xc2132D05D31c914a87C6611C10748AEb04B58e8F);
    IERC20 public constant DAI =
        IERC20(0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063);
    address public constant WETH9 = 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619;
    IERC20 public STG;

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
            0x45A01E4e04F14f7A4a6702c74187c5F6222033cd
        );
        stargateLPStaking = IStargateLPStaking(
            0x8731d54E9D02c286767d56ac03e8037C07e01e98
        );
        swapRouter = IUniswapV2Router(
            0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506
        );
        STG = IERC20(0x2F6F07CDcf3588944Bf4C42aC74ff24bF56e7590);

        saloon = ISaloon(_owner);
        depositToken = _depositToken;
        IERC20(depositToken).approve(_owner, type(uint256).max);

        if (depositToken == address(USDC)) {
            depositPoolId = 1;
            stakingPoolId = 0;
            stargateLPToken = IStargateLPToken(
                0x1205f31718499dBf1fCa446663B532Ef87481fe1
            ); //S*USDC
        } else if (depositToken == address(USDT)) {
            depositPoolId = 2;
            stakingPoolId = 1;
            stargateLPToken = IStargateLPToken(
                0x29e38769f23701A2e4A8Ef0492e19dA4604Be62c
            ); //S*USDC
        } else if (depositToken == address(DAI)) {
            depositPoolId = 3;
            stakingPoolId = 2;
            stargateLPToken = IStargateLPToken(
                0x1c272232Df0bb6225dA87f4dEcD9d37c32f63Eea
            ); //S*USDC
        }
    }

    /// @notice Update any or all of the necessary stargate addresses.
    /// @param _STG The STG token contract. There is currently a governance proposal to redeploy STG token due to Alameda connection.
    /// @param _stargateRouter The router contract used for adding and removing liquidity.
    /// @param _stargateLPToken The LP Token that is provided as a result of adding liquidity.
    /// @param _stargateLPStaking The staking contract used to stake Stargate LP tokens.
    function updateStargateAddresses(
        address _STG,
        address _stargateRouter,
        address _stargateLPToken,
        address _stargateLPStaking
    ) external onlyOwner {
        if (_STG != address(0)) STG = IERC20(_STG);
        if (_stargateRouter != address(0))
            stargateRouter = IStargateRouter(_stargateRouter);
        if (_stargateLPToken != address(0))
            stargateLPToken = IStargateLPToken(_stargateLPToken);
        if (_stargateLPStaking != address(0))
            stargateLPStaking = IStargateLPStaking(_stargateLPStaking);
    }

    /// @notice Update the Uniswap router address used to swap STG for deposit token.
    /// @param _swapRouter The router contract used for swapping tokens.
    function updateSwapRouterAddress(address _swapRouter) external onlyOwner {
        if (_swapRouter != address(0))
            swapRouter = IUniswapV2Router(_swapRouter);
    }

    /// @notice Put all deposit tokens held in this contract to work.
    /// @dev Add liquidity to stargate router => receive LP tokens => deposit LP tokens into stargate LPStaking
    function depositToStrategy() public onlyOwner returns (uint256) {
        uint256 tokenBalance = IERC20(depositToken).balanceOf(address(this));
        USDC.approve(address(stargateRouter), tokenBalance);

        stargateRouter.addLiquidity(depositPoolId, tokenBalance, address(this)); // 1 = Harcode for USDC LP
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
        uint256 fundsToReturn = IERC20(depositToken).balanceOf(address(this));
        IERC20(depositToken).safeTransfer(msg.sender, fundsToReturn);

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
    /// @param _receiver The receiver of the yield after Saloon fees are taken.
    function _convertReward(address _receiver) internal returns (uint256) {
        uint256 availableSTG = rewardBalance();
        if (availableSTG == 0) return 0;
        STG.approve(address(swapRouter), availableSTG);

        address[] memory path = new address[](2);
        path[0] = address(STG);
        path[1] = depositToken;

        uint256[] memory returnedAmounts = swapRouter.swapExactTokensForTokens(
            availableSTG,
            0, // Don't worry about slippage for yield conversion
            path,
            address(this),
            block.timestamp
        );

        // [inputAmount, outputAmount]
        uint256 returnedAmount = returnedAmounts[1];
        uint256 saloonFee = (returnedAmount * FEE) / BPS;
        uint256 amountMinusFee = returnedAmount - saloonFee;

        saloon.receiveStrategyYield(depositToken, saloonFee);

        // Only transfer if receiver is not this contract. Otherwise, keep underlying here for compound.
        if (_receiver != address(this)) {
            IERC20(depositToken).safeTransfer(_receiver, amountMinusFee);
        }

        return amountMinusFee;
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
