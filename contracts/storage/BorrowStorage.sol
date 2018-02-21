pragma solidity ^0.4.19;

import "../base/Owned.sol";
import "../base/Allowed.sol";
import "../base/ArrayHelper.sol";
import "../base/Owned.sol";

/**
  * @title The Compound Borrow Storage Contract
  * @author Compound
  * @notice The Borrow Storage contract is a simple contract to
  *         keep track of borrower information: which assets can be
  *         borrowed and the global minimum collateral ratio.
  */
contract BorrowStorage is Owned, Allowed, ArrayHelper {
    address[] public borrowableAssets;

    event NewBorrowableAsset(address asset);

    /**
      * @notice `addBorrowableAsset` adds an asset to the list of borrowable assets
      * @param asset The address of the assets to add
      * @return success or failure
      */
    function addBorrowableAsset(address asset) public returns (bool) {
        if (!checkOwner()) {
            return false;
        }

        borrowableAssets.push(asset);

        NewBorrowableAsset(asset);

        return true;
    }

    /**
      * @notice `borrowableAsset` determines if the asset is borrowable
      * @param asset the assets to query
      * @return boolean true if the asset is borrowable, false if not
      */
    function borrowableAsset(address asset) public view returns (bool) {
        return arrayContainsAddress(borrowableAssets, asset);
    }
}