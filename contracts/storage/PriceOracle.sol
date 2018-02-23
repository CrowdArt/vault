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
      *
      * @return the scaled value of asset. divide by `assetMultiplier` to de-scale
      */
    function getScaledValue(address asset) public view returns (uint) {
        return values[asset];
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

        if(srcAsset == targetAsset) {
            return srcAssetAmount;
        }

        uint srcValue = values[srcAsset];
        uint targetValue = values[targetAsset];

        if (srcValue == 0 || targetValue == 0) {
            return 0; // not supported
        }

        return (srcValue * srcAssetAmount) / targetValue;
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
