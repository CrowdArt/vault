pragma solidity ^0.4.19;

import "../base/Allowed.sol";
import "../base/Owned.sol";
import "../eip20/EIP20Interface.sol";

/**
  * @title The Compound Token Store Contract
  * @author Compound
  * @notice The Token Store contract holds all tokens.
  */
contract TokenStore is Owned, Allowed {

    event TransferOut(address indexed asset, address indexed to, uint256 amount);

    /**
     * @notice Constructs a new TokenStore object
     */
    function TokenStore() public {}

    /**
      * @notice `transferAssetOut` transfer an asset from this contract to a destination
      * @param asset Asset to transfer
      * @param to Address to transfer to
      * @param amount Amount to transfer of asset
      * @return success or failure of operation
      */
    function transferAssetOut(address asset, address to, uint256 amount) public returns (bool) {
        if (!checkAllowed()) {
            return false;
        }

        // EIP20Interface reverts if balance too low.  We do a pre-check to enable a graceful failure message instead.
        EIP20Interface token = EIP20Interface(asset);
        uint256 balance = token.balanceOf(address(this));

        if(balance < amount) {
            failure("TokenStore::TokenTransferToFail", uint256(asset), uint256(amount), uint256(to));
            return false;
        }

        if(!token.transfer(to, amount)) {
            failure("TokenStore::TokenTransferToFail2");
            return false;
        }
        TransferOut(asset, to, amount);
        return true;
    }
}