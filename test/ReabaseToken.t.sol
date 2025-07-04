// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {Vault} from "../src/Vault.sol";
import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";

contract RebaseTokenTest is Test {
    RebaseToken private rebaseToken;
    Vault private vault;

    address private owner = makeAddr("owner");
    address private user = makeAddr("user");
    function setUp() public {
        //Impersonate the 'owner' address for deployments and role granting
        vm.startPrank(owner);
        rebaseToken = new RebaseToken();

        //Deploy Vault with RebaseToken address
        //Deploy Vault: requires IRebaseToken
        //Direct casting(IRebaseToken(rebaseToken))is Invalid
        //Correct way : cast rebaseToken  to address , then to IRebaseToken.

        vault = new Vault(IRebaseToken(address(rebaseToken)));

        //Grant the MINT_AND_BURN_ROLE to the Vault contract
        //The grantMintAndBurnRole function expects an address.
        rebaseToken.grantMintAndBurnRole(address(vault));

        //send 1 ETH to the Vault to simulate intial funds
        //The target address must be cast to 'payable'
        (bool success, ) = payable(address(vault)).call{value: 1 ether}("");
        //It's good practice to handle the success flag,though omitted for brevity here

        //Stop impersonating the owner
        vm.stopPrank();
    }
    function testDepositLinear(uint256 amount) public {
        //Constrain the fuzzed 'amount' to a practical range
        //Mint: 0.00001ETH (1e15 wei) ,Max: type(uint96).max to avoid overflows
        amount = bound(amount, 1e15, type(uint96).max);

        //1.User deposits 'amount'ETH
        vm.startPrank(user);
        vm.deal(user, amount);
        //2.TODO:Implement deposit logic:
        vault.deposit{value: amount}();
        //3.TODO:Check initial rebase token balance for 'user
        uint256 timeDelta = 1 days;
        uint256 initialBalance = rebaseToken.balanceOf(user);
        vm.warp(block.timestamp + timeDelta);
        uint256 balanceAfterFirstWarp = rebaseToken.balanceOf(user);
        uint256 interestFirstPeriod = balanceAfterFirstWarp - initialBalance;

        //4.TODO:Warp time forward by the same amount and check balance again
        vm.warp(block.timestamp + timeDelta);
        uint256 balanceAfterSecondWarp = rebaseToken.balanceOf(user);
        uint256 interestSecondPeriod = balanceAfterSecondWarp -
            balanceAfterFirstWarp;

        //TODO: Assert that interestFirstPeriod == interestSecondPeriod for linear accrual
        assertEq(
            interestFirstPeriod,
            interestSecondPeriod,
            "interest accrual is not linear"
        );
        vm.stopPrank();
    }
}
