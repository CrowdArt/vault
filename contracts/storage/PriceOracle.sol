pragma solidity ^0.4.19;

import "../base/Owned.sol";
import "../base/Allowed.sol";
import "../base/ArrayHelper.sol";

/**
 * @title The Compound Price Oracle
 * @author Compound
 * @notice The Compound Price Oracle specifies the value of a set of assets
 *         as determined by Compound. These asset values are used to make
 *         fair terms for borrow contracts in Compound.
 */
contract PriceOracle is Owned, Allowed, ArrayHelper {
    int public assetMultiplier = 10 ** 9;
    uint64 constant discountRateScale = 10 ** 17;
    mapping(address => uint) public values;
    mapping(address => uint) public lastUpdatedAtBlock;
    address[] public assets;

    event NewAsset(address indexed asset);
    event AssetValueUpdate(address indexed asset, uint valueInWei);

    /**
     * @notice Constructs a new PriceOracle object
     */
    function PriceOracle() public {}

    /**
     * @dev `getSupportedAssets` returns assets which have PriceOracle values
     *
     * @return assets List of supported asset addresses
     */
    function getSupportedAssets() public view returns(address[]) {
        return assets;
    }

    /**
     * @dev `getAssetsLength` returns length of assets for iteration
     *
     * @return assetLength Length of list of supported asset addresses
     */
    function getAssetsLength() public view returns(uint256) {
        return assets.length;
    }

    /**
     * `getAssetValue` returns the PriceOracle's view of the current
     * value of a given asset, or zero if unknown.
     *
     * @param asset The address of the asset to query
     * @param amount The amount in base units of the asset
     *
     * @return value The value in wei of the asset, or zero.
     */
    function getAssetValue(address asset, uint amount) public view returns(uint) {
        return (values[asset] * amount) / uint(assetMultiplier);
    }

    /**
     * `getConvertedAssetValue` returns the PriceOracle's view of the current
     * value of srcAsset in terms of targetAsset, or 0 if either asset is unknown.
     *
     * @param srcAsset The address of the asset to query
     * @param srcAssetAmount The amount in base units of the asset
     * @param targetAsset The asset in which we want to value srcAsset
     *
     * @return value The value in wei of the asset, or zero.
     */
    function getConvertedAssetValue(address srcAsset, uint256 srcAssetAmount, address targetAsset) public view returns(uint) {
        return getConvertedAssetValueWithDiscount(srcAsset, srcAssetAmount, targetAsset, 0);
    }

    /**
     * `getConvertedAssetValueWithDiscount` returns the PriceOracle's view of the current
     * value of srcAsset in terms of targetAsset, after applying the specified discount to
     * the oracle's targetAsset value. Returns 0 if either asset is unknown.
     *
     * @param srcAsset The address of the asset to query
     * @param srcAssetAmount The amount in base units of the asset
     * @param targetAsset The asset in which we want to value srcAsset
     * @param targetDiscountRate the unscaled numerator for percentage discount to be applied to current PriceOracle
     * price of targetAsset (aka for a discount of 5% it should be 5)
     * @return value The value in wei of the asset, or zero.
     */
    function getConvertedAssetValueWithDiscount(address srcAsset, uint256 srcAssetAmount, address targetAsset, uint8 targetDiscountRate) public view returns(uint) {

        if(srcAsset == targetAsset) {
            return srcAssetAmount;
        }

        uint scaledSrcValue = scaledDiscountPrice(values[srcAsset], 0);
        uint scaledTargetValue = scaledDiscountPrice(values[targetAsset], targetDiscountRate);

        if (scaledSrcValue == 0 || scaledTargetValue == 0) {
            return 0; // not supported
        }

        return (scaledSrcValue * srcAssetAmount) / scaledTargetValue;
    }

    /**
      * @notice `scaledDiscountPrice`
      * @param price value from PriceOracle for an asset
      * @param unscaledDiscountRate the numerator of a percentage fraction, e.g for 5% it would be 5. 0 is a valid discount.
      * @return the scaled discount price after applying the discount rate
      */
    function scaledDiscountPrice(uint price, uint8 unscaledDiscountRate) public pure returns (uint) {

        return (( 100*discountRateScale - (unscaledDiscountRate * discountRateScale)) * price) / 100;
    }

    /**
     * `setAssetValue` sets the value of an asset in Compound.
     *
     * @param asset The address of the asset to set
     * @param valueInWei The value in wei of the asset per unit
     */
    function setAssetValue(address asset, uint valueInWei) public returns (bool) {
        if (!checkOwner()) {
            return false;
        }

        if (!arrayContainsAddress(assets, asset)) {
            assets.push(asset);
            NewAsset(asset);
        }

        // Emit log event
        AssetValueUpdate(asset, valueInWei);

        // Update asset type value
        values[asset] = valueInWei;
        lastUpdatedAtBlock[asset] = block.number;

        return true;
    }
}
