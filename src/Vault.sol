//SPDX-License-Identifier:MIT
pragma solidity ^0.8.24;

import {IRebaseToken} from "./interfaces/IRebaseToken.sol";

contract Vault {
    //Core Requirements:
    //2.Implement a deposit function:
    // -Accepts ETH from the user
    // -Mints RebaseTokens to the user, equivalent to the ETH sent(1:1 peg initially).
    //3.Implement a redeem function:
    // -Burns the user's RebaseTokens.
    // -Sends the corresponding amount of ETH back to the user.
    //4.Implement a  mechanism to add ETH rewards to the vault.

    IRebaseToken private immutable i_rebaseToken; //Type will be interface
    event Deposit(address indexed user, uint256 amount);
    event Redeem(address indexed user, uint256 amount);

    error Vault_RedeemFailed();
    error Vault_DepositAmountIsZero();

    constructor(IRebaseToken _rebaseToken) {
        i_rebaseToken = _rebaseToken;
    }

    /**
     *@notice Fallback function to accept ETH rewards sent directly to the contract.
     *@dev Any ETH sent to this contract's address without data will be accepted.
     */
    receive() external payable {}
    //..(deposit, redeem,)
    /**
     *@notice Allows a user to deposit ETH and receive an equivalent amount of RebaseTokens.
     *@dev The amount of ETH sent with the transaction (msg.value) determines the amount of tokens minted.
     *Assume a 1:1 peg for ETH to RebaseTokens for Simplicity in this vision
     */
    function deposit() external payable {
        //The amount of ETH sent is msg.value
        //The user making the call is msg.sender
        uint256 amountToMint = msg.value;

        //Ensure some ETH is actually sent
        if (amountToMint == 0) {
            revert("Vault_DepositAmountIsZero");
        }

        //call the mint function on the RebaseToken Contract
        i_rebaseToken.mint(msg.sender, amountToMint);

        //Emit an event to log the deposit
        emit Deposit(msg.sender, amountToMint);
    }
    /**
    *@notice Gets the address of the RebaseToken contract associated with this vault.

    *@return True The address of the RebaseToken
     */
    function getRebaseToken() external view returns (address) {
        return address(i_rebaseToken); //Cast to address for return
    }
    /**
     *@notice Allows a user to burn their RebaseTokens and receive a corresponding amount of ETH.
     *@param _amount The amount of RebaseTokens to redeem.
     *@dev Follows Check-Effects-Interactions pattern. Uses low-level .call for ETH transfer.
     */
    function redeem(uint256 _amount) external {
        if (_amount == type(uint256).max) {
            _amount = i_rebaseToken.balanceOf(msg.sender); // Set amount to full current balance
        }
        //1.Effects(State changes occur first)
        //Burn the specified amount of tokens from the caller(msg.sender)
        //The RebaseToken's burn function should handle checks for sufficient balance.
        i_rebaseToken.burn(msg.sender, _amount);
        //3.Interactions(External calls/ETH transfer last)
        //send the equivalent amount of ETH back to the user
        (bool success, ) = payable(msg.sender).call{value: _amount}("");

        //check if the ETH transfer succeded
        if (!success) {
            revert Vault_RedeemFailed();
        }
        //Emit an event to logging the redemption
        emit Redeem(msg.sender, _amount);
    }
}
