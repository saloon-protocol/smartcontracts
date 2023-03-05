// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.7.0) (proxy/ERC1967/ERC1967Proxy.sol)

pragma solidity ^0.8.17;

import "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Upgrade.sol";
import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import "openzeppelin-contracts/contracts/proxy/Proxy.sol";
import "./lib/OwnableUpgradeable.sol";
import "./lib/DelegateCall.sol";
import "./SaloonStorage.sol";

contract SaloonRelay is SaloonStorage, OwnableUpgradeable, UUPSUpgradeable {
    using DelegateCall for address;

    function initialize(
        ISaloonManager _saloonManager,
        ISaloonProjectPortal _saloonProjectPortal,
        ISaloonBounty _saloonBounty,
        ISaloonView _saloonView
    ) public initializer {
        __Ownable_init();
        initManager(_saloonManager);
        setImplementations(
            _saloonManager,
            _saloonProjectPortal,
            _saloonBounty,
            _saloonView
        );
    }

    // NOTE SHOULD THIS FUNCTION ALSO BE INSIDE getRouterImplementation()????
    function initManager(ISaloonManager _saloonManager) public {
        address(_saloonManager).functionDelegateCall(
            abi.encodeWithSelector(ISaloonManager.initialize.selector)
        );
    }

    function _authorizeUpgrade(address _newImplementation)
        internal
        virtual
        override
        onlyOwner
    {}

    function setImplementations(
        ISaloonManager _saloonManager,
        ISaloonProjectPortal _saloonProjectPortal,
        ISaloonBounty _saloonBounty,
        ISaloonView _saloonView
    ) public onlyOwner {
        saloonManager = _saloonManager;
        saloonProjectPortal = _saloonProjectPortal;
        saloonBounty = _saloonBounty;
        saloonView = _saloonView;
    }

    //===========================================================================||
    //                               MANAGER                                     ||
    //===========================================================================||

    function getRouterImplementation(bytes4 sig) public view returns (address) {
        if (
            sig == ISaloonManager.setStrategyFactory.selector ||
            sig == ISaloonManager.updateTokenWhitelist.selector ||
            sig == ISaloonManager.addNewBountyPool.selector ||
            sig == ISaloonManager.extendReferralPeriod.selector ||
            sig == ISaloonManager.billPremium.selector ||
            sig == ISaloonManager.collectSaloonProfits.selector ||
            sig == ISaloonManager.collectAllSaloonProfits.selector ||
            sig == ISaloonManager.collectReferralProfit.selector ||
            sig == ISaloonManager.collectAllReferralProfits.selector
        ) {
            return address(saloonManager);
        } else if (
            sig == ISaloonBounty.payBounty.selector ||
            sig == ISaloonBounty.stake.selector ||
            sig == ISaloonBounty.scheduleUnstake.selector ||
            sig == ISaloonBounty.unstake.selector ||
            sig == ISaloonBounty.claimPremium.selector ||
            sig == ISaloonBounty.calculateEffectiveAPY.selector ||
            sig == ISaloonBounty.consolidate.selector ||
            sig == ISaloonBounty.consolidateAll.selector
        ) {
            return address(saloonBounty);
        } else if (
            sig == ISaloonProjectPortal.setAPYandPoolCapAndDeposit.selector ||
            sig == ISaloonProjectPortal.makeProjectDeposit.selector ||
            sig ==
            ISaloonProjectPortal.scheduleProjectDepositWithdrawal.selector ||
            sig == ISaloonProjectPortal.projectDepositWithdrawal.selector ||
            sig == ISaloonProjectPortal.withdrawProjectYield.selector ||
            sig == ISaloonProjectPortal.windDownBounty.selector ||
            sig == ISaloonProjectPortal.updateProjectWalletAddress.selector ||
            sig == ISaloonProjectPortal.receiveStrategyYield.selector ||
            sig == ISaloonProjectPortal.compoundYieldForPid.selector
        ) {
            return address(saloonProjectPortal);
        } else {
            return address(saloonView);
        }
        //TODO dont forget view function in Common
    }

    /// @notice Callback function from strategies upon converting yield to underlying
    /// @dev Anyone can call this but will result in lost funds for non-strategies. TODO ADD MODIFIER TO THIS?
    /// - Tokens are transferred from msg.sender to this contract and saloonStrategyProfit and/or
    ///   referralBalances are incremented.
    /// @param _token Token being received
    /// @param _amount Amount being received
    function receiveStrategyYield(address _token, uint256 _amount) external {
        address(saloonProjectPortal).functionDelegateCall(
            abi.encodeWithSelector(
                ISaloonProjectPortal.receiveStrategyYield.selector,
                _token,
                _amount
            )
        );
    }

    /// @dev Delegates the current call to `implementation`.
    /// This function does not return to its internal call site, it will return directly to the external caller.
    function _delegate(address implementation) private {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            // Copy msg.data. We take full control of memory in this inline assembly
            // block because it will not return to Solidity code. We overwrite the
            // Solidity scratch pad at memory position 0.
            calldatacopy(0, 0, calldatasize())

            // Call the implementation.
            // out and outsize are 0 because we don't know the size yet.
            let result := delegatecall(
                gas(),
                implementation,
                0,
                calldatasize(),
                0,
                0
            )

            // Copy the returned data.
            returndatacopy(0, 0, returndatasize())

            switch result
            // delegatecall returns 0 on error.
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }

    fallback() external payable {
        _delegate(getRouterImplementation(msg.sig));
    }
}
