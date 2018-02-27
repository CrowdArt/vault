pragma solidity ^0.4.19;

import "./../base/Owned.sol";
import "./../eip20/EIP20.sol";

/**
  * @title The Compound Faucet Test Token
  * @author Compound
  * @notice A simple token that lets anyone get more of it, with a cap on the amount that can be allocated per request
  */
contract FaucetToken is EIP20, Owned {

    uint256 public perRequestTokenAmount;

    function FaucetToken(string name_, string symbol_, uint8 decimals_) EIP20(2**128 - 1, name_, decimals_, symbol_) public { }

    /**
      * @notice Arbitrarily adds configured quantity of tokens to account of msg.sender
      * @dev This is for automated testing and for convenience on the alpha test net
      * @return Success or failure of operation
      */
    function allocate() public returns (bool) {

        if (perRequestTokenAmount == 0) {
            return failure("FaucetToken::AssetNotDisbursable");
        }

        return doAllocation(msg.sender, perRequestTokenAmount);
    }

    /**
      * @notice Arbitrarily adds tokens to account
      * @dev This is for automated testing and for convenience on the alpha test net
      * @param recipient Account to add tokens to.
      * @param value Amount to add
      * @return Success or failure of operation
    */
    function allocateTo(address recipient, uint256 value) public returns (bool) {
        if (!checkOwner()) {
            return false;
        }

        return doAllocation(recipient, value);
    }

    /**
      * @notice Internal function to actually preform token allocation
      * @dev This is for automated testing and for convenience on the alpha test net
      * @param _owner Account to add tokens to.
      * @param value Amount to add.
      * @return Success or failure of operation
    */
    function doAllocation(address _owner, uint256 value) internal returns (bool) {
        balances[_owner] += value;
        totalSupply += value;
        Transfer(address(this), _owner, value);

        return true;
    }

    /**
      * @notice `setPerRequestTokenAmount` allows the contract owner to set/update the amount given for each request of the specified token
      * @dev This is for convenience on alpha test net
      * @param amount How much of the token should be given out? Set to 0 to disallow allocations
      * @return Success of failure of operation
      */
    function setPerRequestTokenAmount(uint256 amount) public returns (bool) {
        if (!checkOwner()) {
            return false;
        }

        perRequestTokenAmount = amount;
        return true;
    }

}