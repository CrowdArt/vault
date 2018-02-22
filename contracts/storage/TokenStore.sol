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

		if (!EIP20Interface(asset).transfer(to, amount)) {
			failure("TokenStore::TokenTransferToFail", uint256(asset), uint256(amount), uint256(to));
            return false;
		}

		TransferOut(asset, to, amount);

		return true;
	}
}