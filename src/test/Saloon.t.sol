// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../Saloon.sol";
import "../SaloonProxy.sol";

import "ds-test/test.sol";
import "forge-std/Script.sol";

contract SaloonTest is DSTest, Script {
    Saloon saloonImplementation;
    SaloonProxy saloonProxy;
    Saloon saloon;
    bytes data = "";

    function setUp() external {
        string memory mumbai = vm.envString("MUMBAI_RPC_URL");
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        uint256 forkId = vm.createFork(mumbai);
        vm.selectFork(forkId);

        saloonImplementation = new Saloon();

        saloonProxy = new SaloonProxy(address(saloonImplementation), data);

        saloon = Saloon(address(saloonProxy));

        saloon.initialize();
    }

    // ============================
    // Test Implementation Update
    // ============================
    function testUpdate() public {
        Saloon NewSaloon = new Saloon();
        saloon.upgradeTo(address(NewSaloon));
    }

    // ============================
    // Test setAPYandPoolCapAndDeposit
    // ============================

    // ============================
    // Test makeProjectDeposit
    // ============================

    // ============================
    // Test scheduleProjectDepositWithdrawal
    // ============================

    // ============================
    // Test projectDepositWithdrawal
    // ============================

    // ============================
    // Test stake
    // ============================

    // ============================
    // Test scheduleUnstake
    // ============================

    // ============================
    // Test unstake
    // ============================

    // ============================
    // Test claimPremium - stake multiple times in a row and then claim, test with different time frames between actions
    // ============================

    // ============================
    // Test billPremium
    // ============================

    // ============================
    // Test payBounty
    // ============================

    // ============================
    // Test collectSaloonProfits
    // ============================
}
