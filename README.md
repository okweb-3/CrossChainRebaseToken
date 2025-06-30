# CrossChainRebaseToken
1. A protocol that allows user to desposit into a vault and in return, receiver rebase tokens that represent their underlying balance.
2. Rebase token -> balanceOf function is dynamic to show the changing balance with time.
- Balance increase linearly with time
- mint tokens to our users every time they perform an anction(minting,burning,transferring,or... bridging)
3. Interest rate
- Indivually set an interest rate or each user based on some global interest rate of the protocol at the time the user deposits into the value
- This global interest rate can only decrease to incetivise/reward early adopters