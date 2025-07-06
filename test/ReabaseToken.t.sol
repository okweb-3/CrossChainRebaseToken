// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {Vault} from "../src/Vault.sol";
import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

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
    function addRewardToVault(uint256 rewardAmount) public {
        (bool success, ) = payable(address(vault)).call{value: rewardAmount}(
            ""
        );
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
        uint256 startBalance = rebaseToken.balanceOf(user);
        console.log("======startBalance======:", startBalance);
        assertEq(startBalance, amount);

        //3.TODO:Check initial rebase token balance for 'user
        uint256 timeDelta = 1 hours;
        vm.warp(block.timestamp + timeDelta);
        uint256 middleBalance = rebaseToken.balanceOf(user);
        console.log("======middleBalance======:", middleBalance);
        assertGt(middleBalance, startBalance);
        // uint256 balanceAfterFirstWarp = rebaseToken.balanceOf(user);
        // uint256 interestFirstPeriod = balanceAfterFirstWarp - initialBalance;

        //4.TODO:Warp time forward by the same amount and check balance again
        vm.warp(block.timestamp + timeDelta);
        uint256 endBalance = rebaseToken.balanceOf(user);
        console.log("======endBalance======:", endBalance);
        assertGt(endBalance, middleBalance);

        // uint256 interestSecondPeriod = balanceAfterSecondWarp -
        //     balanceAfterFirstWarp;

        //TODO: Assert that interestFirstPeriod == interestSecondPeriod for linear accrual
        assertApproxEqAbs(
            endBalance - middleBalance,
            middleBalance - startBalance,
            1
        );
        // assertEq(
        //     interestFirstPeriod,
        //     interestSecondPeriod,
        //     "interest accrual is not linear"
        // );
        vm.stopPrank();
    }
    function testRedeemStraightAway(uint256 amount) public {
        amount = bound(amount, 1e15, type(uint96).max);
        //1.User deposits 'amount'ETH
        vm.startPrank(user);
        vm.deal(user, amount);
        vault.deposit{value: amount}();
        assertEq(rebaseToken.balanceOf(user), amount);

        vault.redeem(type(uint256).max);
        assertEq(rebaseToken.balanceOf(user), 0);
        assertEq(address(user).balance, amount);
        vm.stopPrank();
    }
    function testRedeemAfterTimePassed(
        uint256 depositAmount,
        uint256 time
    ) public {
        time = bound(time, 1000, type(uint96).max);
        depositAmount = bound(depositAmount, 1e5, type(uint96).max);
        //1.deposit
        vm.deal(user, depositAmount);
        vm.prank(user);
        vault.deposit{value: depositAmount}();

        //2.warp time
        vm.warp(time);
        uint256 balanceAfterSomeTime = rebaseToken.balanceOf(user);
        //Add the reward to the vault
        vm.deal(owner, balanceAfterSomeTime - depositAmount);
        vm.prank(owner);
        addRewardToVault(balanceAfterSomeTime - depositAmount);

        vm.prank(user);
        vault.redeem(type(uint256).max);

        //3. Redeem
        uint256 ethBalance = address(user).balance;
        assertEq(ethBalance, balanceAfterSomeTime);
        assertGt(ethBalance, depositAmount);
    }

    function testTransfer(uint256 amount, uint256 amountToSend) public {
        amount = bound(amount, 1e15 + 1e15, type(uint96).max);
        amountToSend = bound(amountToSend, 1e15, amount - 1e15);
        //1.User deposits 'amount'ETH
        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();

        address user2 = makeAddr("user2");
        uint256 userBalance = rebaseToken.balanceOf(user);
        uint256 user2BalanceBefore = rebaseToken.balanceOf(user2);

        assertEq(userBalance, amount);
        assertEq(user2BalanceBefore, 0);

        //owner reduces the interest rate
        vm.prank(owner);
        rebaseToken.setInterestRate(4e10);

        //transfer some tokens to user2
        vm.prank(user);
        rebaseToken.transfer(user2, amountToSend);
        uint256 userBalanceAfter = rebaseToken.balanceOf(user);
        uint256 user2BalanceAfter = rebaseToken.balanceOf(user2);
        assertEq(userBalanceAfter, userBalance - amountToSend);
        assertEq(user2BalanceAfter, amountToSend);
        //check the user interest rate has been inherited
        assertEq(rebaseToken.getUserInterestRate(user), 5e10);
    }
    function testCannotSetInterestRateIfNotOwner(
        uint256 newInterestRate
    ) public {
        //1.User tries to set interest rate
        vm.prank(user);
        vm.expectPartialRevert(Ownable.OwnableUnauthorizedAccount.selector);
        rebaseToken.setInterestRate(newInterestRate);
    }
    function testCannotMintIfNotVault(uint256 amount) public {
        //1.User tries to mint tokens
        vm.prank(user);
        vm.expectPartialRevert(
            IAccessControl.AccessControlUnauthorizedAccount.selector
        );
        rebaseToken.mint(user, amount);
    }
    function testCannotBurnIfNotVault(uint256 amount) public {
        //1.User tries to burn tokens
        vm.prank(user);
        vm.expectPartialRevert(
            IAccessControl.AccessControlUnauthorizedAccount.selector
        );
        rebaseToken.burn(user, amount);
    }
    function testGetPrincipleBalanceOf(uint256 amount) public {
        amount = bound(amount, 1e15, type(uint96).max);
        //1.User deposits 'amount'ETH
        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();
        assertEq(rebaseToken.principleBalanceOf(user), amount);

        vm.warp(block.timestamp + 1 hours);
        assertEq(rebaseToken.principleBalanceOf(user), amount);
    }
    function testGetRebaseToken() public view {
        assertEq(vault.getRebaseToken(), address(rebaseToken));
    }

    function testInterestRateCanOnlyDecrease(uint256 newInterestRate) public {
        uint256 currentInterestRate = rebaseToken.getInterestRate();
        newInterestRate = bound(
            newInterestRate,
            currentInterestRate,
            type(uint96).max
        );
        vm.prank(owner);
        vm.expectPartialRevert(
            RebaseToken.RebaseToken__InterestRateCanOnlyDecrease.selector
        );
        rebaseToken.setInterestRate(newInterestRate);
        assertEq(rebaseToken.getInterestRate(), currentInterestRate);
    }
}
