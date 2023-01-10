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

/* Implement:
- TODO add back ownable
*/

contract StargateStrategy is OwnableUpgradeable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IStargateRouter public stargateRouter;
    IStargateLPStaking public stargateLPStaking;
    IStargateLPToken public stargateLPToken;
    IERC20 public constant USDC =
        IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

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
        // __Ownable_init();
    }

    function despositToStrategy(uint256 _poolId, uint256 _amount)
        external
        returns (
            // onlyOwner
            uint256
        )
    {
        USDC.safeTransferFrom(msg.sender, address(this), _amount);
        USDC.approve(address(stargateRouter), _amount);
        stargateRouter.addLiquidity(_poolId, _amount, address(this));
        uint256 lpBalance = stargateLPToken.balanceOf(address(this));

        return lpBalance;
    }
}
