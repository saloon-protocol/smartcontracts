// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../Saloon.sol";
import "../SaloonProxy.sol";
import "../lib/ERC20.sol";
import "ds-test/test.sol";
import "forge-std/Script.sol";

// import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract SaloonTest is DSTest, Script {
    Saloon saloonImplementation;
    SaloonProxy saloonProxy;
    Saloon saloon;
    bytes data = "";

    ERC20 usdc;
    address project = address(0xDEF1);
    address hunter = address(0xD0);
    address staker = address(0x5ad);

    uint256 pid;

    function setUp() external {
        string memory mumbai = vm.envString("MUMBAI_RPC_URL");
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        uint256 forkId = vm.createFork(mumbai);
        vm.selectFork(forkId);

        saloonImplementation = new Saloon();

        saloonProxy = new SaloonProxy(address(saloonImplementation), data);

        saloon = Saloon(address(saloonProxy));

        saloon.initialize();

        usdc = new ERC20("USDC", "USDC");

        usdc.mint(project, 500 ether);
        usdc.mint(staker, 500 ether);

        vm.deal(project, 500 ether);
    }

    // ============================
    // Test Implementation Update
    // ============================
    function testUpdate() public {
        Saloon NewSaloon = new Saloon();
        saloon.upgradeTo(address(NewSaloon));
    }

    // ============================
    // Test addNewBountyPool
    // ============================
    function testaddNewBountyPool() public {
        pid = saloon.addNewBountyPool(address(usdc), 18, project);
    }

    // ============================
    // Test setAPYandPoolCapAndDeposit
    // ============================
    function testsetAPYandPoolCapAndDeposit() public {
        pid = saloon.addNewBountyPool(address(usdc), 18, project);
        vm.startPrank(project);
        usdc.approve(address(saloon), 1000 ether);
        saloon.setAPYandPoolCapAndDeposit(pid, 100 ether, 1000, 1 ether);

        // Test if APY and PoolCap can be set again (should revert)
    }

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
