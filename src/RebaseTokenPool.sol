//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TokenPool} from "@ccip/contracts/src/v0.8/ccip/pools/TokenPool.sol";
import {IERC20} from "@ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {IRebaseToken} from "./interfaces/IRebaseToken.sol";
// Adjust path if your interface is elsewhere
import {Pool} from "@ccip/contracts/src/v0.8/ccip/libraries/Pool.sol"; // For CCIP structs

contract RebaseTokenPool is TokenPool {
    constructor(
        IERC20 _token,
        address[] memory _allowlist,
        address _rmnProxy,
        address _router
    ) TokenPool(_token, 18, _allowlist, _rmnProxy, _router) {}

    function lockOrBurn(
        Pool.LockOrBurnInV1 calldata lockOrBurnIn
    ) external override returns (Pool.LockOrBurnInV1 memory lockOrBurnOut) {
        //It performs crucial security and configuration checks
        _validateLockOrBurn(lockOrBurnIn);

        //Decode the original sender's address
        address originalSender = abi.decode(
            lockOrBurnIn.originalSender,
            (address)
        );

        //Fetch the user's current interest rate from the base token
        uint256 userInterestRate = IRebaseToken(address(i_token))
            .getUserInterestRate(originalSender);

        //Burn the specified amount of tokens from this pool contract
        //CCIP transfers tokens to the pool before lockOrBurn is called
        IRebaseToken(address(i_token)).burn(address(this), lockOrBurnIn.amount);

        //Prepare the output data for CCIP
        lockOrBurnOut = Pool.lockOrBurnOutV1({
            destTokenAddress: getRemoteToken(lockOrBurnIn.remoteChainSelector),
            destPoolData: abi.encode(userInterestRate)
        });
    }

    function releaseOrMint(
        Pool.ReleaseOrMintInV1 calldata releaseOrMintIn
    ) external returns (Pool.ReleaseOrMintInV1 memory) {
        _validateReleaseOrMint(releaseOrMintIn);

        //Decode the user interest rate sent from the source pool
        uint256 userInterestRate = abi.decode(
            releaseOrMintIn.sourcePoolData,
            (uint256)
        );

        //The reciver address directly available
        address reciver = releaseOrMintIn.reciver;

        //Mint tokens to the reciver,applying the propageted interest rate
        IRebaseToken(address(i_token)).mint(
            reciver,
            releaseOrMintIn,
            userInterestRate
        );

        return
            Pool.ReleaseOrMintInV1({destinationamount: releaseOrMintIn.amount});
    }
}
