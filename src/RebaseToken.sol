// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title RebaseToken
 * @author okweb3
 * @notice This is a cross-chain rebase token that incentives user to deposit into a vault and gain interest in rewards.
 * @notice The interest rate in the smart contract can only decrease
 * @notice Each user will have their own interest rate that is the global interest rate at the time of deposit
 */

contract RebaseToken is ERC20, Ownable, AccessControl {
    uint256 private constant PRECISION_FACTOR = 1e18;
    uint256 private s_interestRate = (5 * PRECISION_FACTOR) / 1e8; //10^ -8 is 0.00000005 1/10^8
    mapping(address => uint256) private s_userInterestRate;
    mapping(address => uint256) private s_userLastUpdateTimeStamp;
    bytes32 public constant MINT_AND_BURN_ROLE =
        keccak256("MINT_AND_BURN_ROLE");

    error RebaseToken__InterestRateCanOnlyDecrease(
        uint256 oldInterestRate,
        uint256 newInterestRate
    );
    event InterestRateSet(uint256 newInterestRate);

    constructor() ERC20("RebaseToken", "RBT") Ownable(msg.sender) {}
    /**
     *@notice Set the gobal interest rate for the contract.
     * @param _newInterestRate The new  interest rate to set.(Scaled by PRECISION_FACTOR basis points per second)
     * @dev The interest rate can only decrease . Access control (e.g.,OnlyOwner) should be added.
     */
    function setInterestRate(uint256 _newInterestRate) external onlyOwner {
        if (_newInterestRate >= s_interestRate) {
            revert RebaseToken__InterestRateCanOnlyDecrease(
                s_interestRate,
                _newInterestRate
            );
        }
        s_interestRate = _newInterestRate;
        emit InterestRateSet(_newInterestRate);
    }
    /**
     * @notice Gets the locked-in interest rate for a specific user.
     * @param _user The address of the user.
     * @return The user's specific interest rate.
     */
    function getUserInterestRate(
        address _user
    ) external view returns (uint256) {
        return s_userInterestRate[_user];
    }

    /**
     * @notice Mints token to a user, typically upon deposit.
     * @dev Also mints accrued interest and locks in the current global rate for the user.
     * @param _to The address to mint tokens to.
     * @param _amount The principal amount of tokens to mint.
     */
    function mint(
        address _to,
        uint256 _amount
    ) external onlyRole(MINT_AND_BURN_ROLE) {
        _mintAccuredInterest(_to);
        s_userInterestRate[_to] = s_interestRate;
        _mint(_to, _amount);
    }

    /**
     * @notice Burn the user tokens, e.g., when they withdraw from a vault or for cross-chain transfers.
     * Handles burning the entire balance if _amount is type(uint256).max.
     * @param _from The user address from which to burn tokens.
     * @param _amount The amount of tokens to burn. Use type(uint256).max to burn all tokens.
     */
    function burn(
        address _from,
        uint256 _amount
    ) external onlyRole(MINT_AND_BURN_ROLE) {
        // Access control to be added as needed
        // uint256 currentTotalBalance = balanceOf(_from); // Calculate this once for efficiency if needed for checks

        // if (_amount == type(uint256).max) {
        //     _amount = currentTotalBalance; // Set amount to full current balance
        // }

        // Ensure _amount does not exceed actual balance after potential interest accrual
        // This check is important especially if _amount wasn't type(uint256).max
        // _mintAccruedInterest will update the super.balanceOf(_from)
        // So, after _mintAccruedInterest, super.balanceOf(_from) should be currentTotalBalance.
        // The ERC20 _burn function will typically revert if _amount > super.balanceOf(_from)

        _mintAccruedInterest(_from); // Mint any accrued interest first

        // At this point, super.balanceOf(_from) reflects the balance including all interest up to now.
        // If _amount was type(uint256).max, then _amount == super.balanceOf(_from)
        // If _amount was specific, super.balanceOf(_from) must be >= _amount for _burn to succeed.

        _burn(_from, _amount);
    }
    /**
     * @dev Internal function to calculate and mint accurued interest for a user.
     * @dev Updates the user's last updated timestamp.
     * @param _user The address of the user.
     */
    function _mintAccuredInterest(address _user) internal {
        //TODO: Implement full logic to calculate and mint actual interest token.
        //The amount of interest to mint would be:
        //current_dynamic_balance - current_stored_principal_balbace
        //Then, _mint(_user,interest_amount_to_mint);

        s_userLastUpdateTimeStamp[_user] = block.timestamp;
    }

    /**
     * @notice Returns the current balance of an account, including accrued insterest
     * @param _user The address of the account
     * @return The total balbance including interest.
     */
    function balanceOf(address _user) public view override returns (uint256) {
        //Get the user's stored principal balance (tokens actually minted to them)
        uint256 principalBalance = super.balanceOf(_user);

        //Calculate the growth factor based on accurued interest.
        uint256 growthFactor = _calculateUserAccumulatedInterestSinceLastUpdate(
            _user
        );

        //Apply the growth factor to the principal balance.
        //Remember PRECISION_FACTOR is used for scaling, so we divide by it here.
        return (principalBalance * growthFactor) / PRECISION_FACTOR;
    }

    /**
     * @dev Calculates the growth factor due to accumulated interest since the user's last update.
     * @param _user The address of the user.
     * @return linearInterestFactor  growth factor, scaled by PRESISION_FACTOR.(e.g.,1.05x growth is 1.05 *1e18).
     */
    function _calculateUserAccumulatedInterestSinceLastUpdate(
        address _user
    ) internal view returns (uint256 linearInterestFactor) {
        //Caculate the time elapsed since the user's balance was last effectively updated.

        uint256 timeElapsed = block.timestamp -
            s_userLastUpdateTimeStamp[_user];

        //If no time has passed or if the user has no locked rate(never interacted)
        //the growth factor is simply 1(scale by PRECISION_FACTOR).

        if (timeElapsed == 0 || s_userInterestRate[_user] == 0) {
            return PRECISION_FACTOR;
        }
        //2. Calculate the total fractional interest accrued : UserInterestRate * TimeElapsed
        //s_userInterestRate[_user] is the rate per second
        //This product is already scale appropriately if s_userInterestRate is stored.
        uint256 fractionalInterest = s_userInterestRate[_user] * timeElapsed;

        //3. The growth  factor is (1 +  fractional_interest_part).
        //Since '1' is represented as PRECISION_FACTOR,and fractionalInterest is already scaled, we add them
        linearInterestFactor = PRECISION_FACTOR + fractionalInterest;
        return linearInterestFactor;
    }
    function _mintAccruedInterest(address _user) internal {
        //find their current balance of rebase tokens that have been minted to the user -> principle balance
        uint256 previousPrincipleBalance = super.balanceOf(_user);

        //calculate their  current balance including any interest -> balanceOf
        uint256 currentBalance = balanceOf(_user);

        //calculate the number of tokens that need to be minted to the user (2)-(1)
        uint256 balanceIncrease = currentBalance - previousPrincipleBalance;

        //set the user's last update timestamp (Effect)
        s_userLastUpdateTimeStamp[_user] = block.timestamp;

        //Mint the accrued interest(Interaction)
        _mint(_user, balanceIncrease);
        if (balanceIncrease > 0) {
            _mint(_user, balanceIncrease);
        }
    }
    /**
     * @notice Transfers tokens from the caller to a recipient.
     * Accrued interest for both the sender and recipient is minted before the transfer.
     * if the recipient is new, they inherit the sender's interest rate.
     * @param _recipient The address to transfer tokens to.
     * @param _amount The amount of tokens to transfer. Can be type(uint256). max to transfer full balance.
     * @return True A boolean indicating whether the operation succeeded.
     */
    function transfer(
        address _recipient,
        uint256 _amount
    ) public override returns (bool) {
        //1. Mint accrued interest for both sender and recipient
        _mintAccruedInterest(msg.sender);
        _mintAccruedInterest(_recipient);

        //2.handle request to transfer maximum balance
        if (_amount == type(uint256).max) {
            _amount = balanceOf(msg.sender);
        }
        //3. Set recipient's interest rate if they are new(balance is checked *before* super.transfer)
        //we use balanceOf here to check the effective balance including any just minted interest.
        //If _mintAccruedInterest made their balance non-zero, but they had 0 principle, this still means they are "new" for rate setting.
        //A more robust check for "newness" for rate setting might be super.balanceOf(recipient) ==0 before any interest minting. for the recipient.
        //However, the current logic is: if their *effective* balance is 0 before the main transfer part, they get the sender's rate.
        if (balanceOf(_recipient) == 0 && _amount > 0) {
            s_userInterestRate[_recipient] = s_userInterestRate[msg.sender];
        }
        //4.Execute the base ERC20 transfer
        return super.transfer(_recipient, _amount);
    }
    /**
     * @notice Transfer tokens from one address to another, on behalf of the sender,
     * provider an allowance is in place.
     * Accrued interest for both the sender and recipient is minted before the transfer.
     * If the recipient is new, they inherit the sender's interest rate.
     * @param _sender The address to transfer tokens from transfer.
     * @param _recipient The address to transfer tokens to.
     * @param _amount The amount of tokens to transfer. Can be type(uint256) max to transfer full balance.
     * @return True A boolean indicating whether the operation succeeded.
     */
    function transferFrom(
        address _sender,
        address _recipient,
        uint256 _amount
    ) public override returns (bool) {
        _mintAccruedInterest(_sender);
        _mintAccruedInterest(msg.sender);

        if (_amount == type(uint256).max) {
            _amount = balanceOf(_sender); //use the interest-inclusive balance of the _sender
        }
        //Set recipient's interest rate if they are new
        if (balanceOf(_recipient) == 0 && _amount > 0) {
            s_userInterestRate[_recipient] = s_userInterestRate[_sender];
        }
        return super.transferFrom(_sender, _recipient, _amount);
    }
    /**
     *@notice Gets the principle balance of a user(tokens actually minted to them),excluding any accrued interest.
     *@param _user The address of the user.
     *@return The  principle balance of the user.
     */
    function principleBalanceOf(address _user) external view returns (uint256) {
        return super.balanceOf(_user); // Call ERC20.balanceOf, Which returns _balances[_user]
    }
    /**
     * @notice Gets the current global interest rate of the token.
     * @return The current global interest rate.
     */
    function getInterestRate() external view returns (uint256) {
        return s_interestRate;
    }

    function grantMintAndBurnRole(address _account) external onlyOwner {
        _grantRole(MINT_AND_BURN_ROLE, _account);
    }
}
