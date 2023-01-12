// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "openzeppelin-contracts/contracts/utils/math/SafeMath.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import "./lib/OwnableUpgradeable.sol";
import "./IStargateRouter.sol";
import "./IStargateLPStaking.sol";
import "./IStargateLPToken.sol";
import "./IUniswapRouter.sol";

/* Implement:
- TODO add back ownable
- TODO Slippage control
*/

contract StargateStrategy is OwnableUpgradeable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint256 public lpDepositBalance;

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

    constructor() {
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
        // __Ownable_init();
    }

    function despositToStrategy(uint256 _poolId, uint256 _amount)
        public
        returns (
            // onlyOwnerOrThis
            uint256
        )
    {
        if (msg.sender != address(this)) {
            USDC.safeTransferFrom(msg.sender, address(this), _amount);
        }
        USDC.approve(address(stargateRouter), _amount);

        stargateRouter.addLiquidity(_poolId, _amount, address(this));
        uint256 lpBalanceAdded = stargateLPToken.balanceOf(address(this));

        stargateLPToken.approve(address(stargateLPStaking), lpBalanceAdded);
        stargateLPStaking.deposit(0, lpBalanceAdded); // PID 0 is S*USDC
        lpDepositBalance += lpBalanceAdded;

        return lpBalanceAdded;
    }

    // Needs onlyOwner
    function withdrawFromStrategy(uint256 _poolId, uint256 _amount)
        external
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
        convertReward();
        uint256 USDCBalance = USDC.balanceOf(address(this));
        USDC.safeTransfer(msg.sender, USDCBalance);

        return USDCBalance;
    }

    // Needs onlyOwner
    function compound() external returns (uint256) {
        stargateLPStaking.deposit(0, 0);
        uint256 returnedAmount = convertReward();

        uint256 lpAdded = this.despositToStrategy(1, returnedAmount);

        return lpAdded;
    }

    function convertReward() public returns (uint256) {
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
