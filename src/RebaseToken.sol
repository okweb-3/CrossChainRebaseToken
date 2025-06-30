// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title RebaseToken
 * @author okweb3
 * @notice This is a cross-chain rebase token that incentives user to deposit into a vault and gain interest in rewards.
 * @notice The interest rate in the smart contract can only decrease
 * @notice Each user will have their own interest rate that is the global interest rate at the time of deposit
 */

contract RebaseToken is ERC20 {
    uint256 private constant PRECISION_FACTOR = 1e18;
    uint256 private s_interestRate = 5e10;
    mapping(address => uint256) private s_userInterestRate;
    mapping(address => uint256) private s_userLastUpdateTimeStamp;

    error RebaseToken__InterestRateCanOnlyDecrease(
        uint256 oldInterestRate,
        uint256 newInterestRate
    );
    event InterestRateSet(uint256 newInterestRate);

    constructor() ERC20("RebaseToken", "RBT") {}
    /**
     *@notice Set the gobal interest rate for the contract.
     * @param _newInterestRate The new  interest rate to set.(Scaled by PRECISION_FACTOR basis points per second)
     * @dev The interest rate can only decrease . Access control (e.g.,OnlyOwner) should be added.
     */
    function setInterestRate(uint256 _newInterestRate) external {
        if (_newInterestRate > s_interestRate) {
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
    function mint(address _to, uint256 _amount) external {
        _mintAccuredInterest(_to);
        s_userInterestRate[_to] = s_interestRate;
        _mint(_to, _amount);
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
}
