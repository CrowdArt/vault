pragma solidity ^0.4.19;

import "./Ledger.sol";
import "./CollateralCalculator.sol";
import "./base/Owned.sol";
import "./base/Graceful.sol";
import "./base/Token.sol";
import "./storage/PriceOracle.sol";
import "./storage/BorrowStorage.sol";

/**
  * @title The Compound Borrow Account
  * @author Compound
  * @notice A borrow account allows customer's to borrow assets, holding other assets as collateral.
  */
contract Borrower is Graceful, Owned, Ledger, CollateralCalculator {
    BorrowStorage public borrowStorage;

    uint64 public constant discountRateScale = 10 ** 9;
    // Given a real number decimal, to convert it to basis points you multiply by 10000.
    // For example, we know 100 basis points = 1% = .01.  We get the basis points from the decimal: .01 * 10000 = 100
    uint16 constant basisPointMultiplier = 10000;

    uint16 public liquidationDiscountRateBPS = 200;
    uint16 public constant maxLiquidationDiscountRateBPS = 3000;

    function Borrower () public {}

    /**
      * @notice `setBorrowStorage` sets the borrow storage location for this contract
      * @dev This is for long-term data storage (TODO: Test)
      * @param borrowStorageAddress The contract which acts as the long-term store
      * @return Success of failure of operation
      */
    function setBorrowStorage(address borrowStorageAddress) public returns (bool) {
        if (!checkOwner()) {
            return false;
        }

        borrowStorage = BorrowStorage(borrowStorageAddress);

        return true;
    }

    /**
      * @notice `setLiquidationDiscountNumeratorBPS` sets the discount rate on price of borrowed asset when liquidating a loan
      * @param basisPoints will be divided by 10000 to calculate the discount rate.  Must be <= maxLiquidationDiscountRateBPS.
      * @return Success or failure of operation
      */
    function setLiquidationDiscountRateBPS(uint16 basisPoints) public returns (bool) {
        if (!checkOwner()) {
            return false;
        }
        if(basisPoints > maxLiquidationDiscountRateBPS) {
            return failure("Borrower::InvalidLiquidationDiscount", uint256(basisPoints));
        }

        liquidationDiscountRateBPS = basisPoints;
        return true;
    }

    /**
      * @notice `customerBorrow` creates a new borrow and supplies the requested asset into the user's account.
      * @param asset The asset to borrow
      * @param amount The amount to borrow
      * @return success or failure
      */
    function customerBorrow(address asset, uint256 amount) public returns (bool) {
        if (!borrowStorage.borrowableAsset(asset)) {
            failure("Borrower::AssetNotBorrowable", uint256(asset));
            return false;
        }

        if (!validCollateralRatio(amount, asset)) {
            // validCollateralRatio generates a graceful failure message on failure
            return false;
        }

        if (!saveBlockInterest(asset, LedgerAccount.Borrow)) {
            failure("Borrower::FailedToSaveBlockInterest", uint256(asset), uint256(LedgerAccount.Borrow));
            return false;
        }

        // Check that we have a sufficient amount of cash to give to the customer
        uint256 assetCash = balanceSheet.getBalanceSheetBalance(asset, uint8(LedgerAccount.Cash));

        if (assetCash < amount) {
            failure("Borrower::InsufficientAssetCash", uint256(asset), assetCash);
            return false;
        }

        // TODO: If customer already has a borrow of asset, we need to make sure we can handle the change.
        // Before adding the new amount we will need to either calculate interest on existing borrow amount or snapshot
        // the current borrow balance.
        // Alternatively: Block additional borrow for same asset.

        debit(LedgerReason.CustomerBorrow, LedgerAccount.Borrow, msg.sender, asset, amount);
        credit(LedgerReason.CustomerBorrow, LedgerAccount.Supply, msg.sender, asset, amount);

        return true;
    }

    /**
      * @notice `customerPayBorrow` customer makes a borrow payment
      * @param asset The asset to pay down
      * @param amount The amount to pay down
      * @return success or failure
      */
    function customerPayBorrow(address asset, uint256 amount) public returns (bool) {
        if (!accrueBorrowInterest(msg.sender, asset)) {
            return false;
        }

        if (!saveBlockInterest(asset, LedgerAccount.Borrow)) {
            failure("Borrower::FailedToSaveBlockInterest", uint256(asset), uint256(LedgerAccount.Borrow));
            return false;
        }

        credit(LedgerReason.CustomerPayBorrow, LedgerAccount.Borrow, msg.sender, asset, amount);
        debit(LedgerReason.CustomerPayBorrow, LedgerAccount.Supply, msg.sender, asset, amount);

        return true;
    }

    /**
      * @notice `previewLiquidateCollateral` returns how much of the specified collateral a liquidator would receive
      * AT CURRENT PriceOracle PRICES by calling `liquidateCollateral` with the same parameters. See `liquidateCollateral`
      * for more information.
      * @param borrower the account whose borrow would be reduced
      * @param borrowedAsset the type of asset that was borrowed and that would be supplied by the msg.sender
      * @param borrowedAssetAmount how much of the borrowed asset msg.sender plans to supply; it will be applied to reduce
      * the balance of the borrow. NOTE: sender should first true up their balance if interest must be accrued in order
      * to supply borrowedAssetAmount
      * @param assetToLiquidate what asset msg.sender should receive in exchange- note that this will be
      * transferred from the borrower, so the borrower must have enough of the asset to support the amount resulting
      * from the borrowedAssetAmount and the discounted conversion price
      * @return the amount of collateral that would be received AT CURRENT PRICES. If 0 is returned, no liquidation
      * would occur. Check logs for failure reason.
      */
    function previewLiquidateCollateral(address borrower, address borrowedAsset, uint borrowedAssetAmount, address assetToLiquidate) public returns (uint256) {

        // Do basic checks first before running up gas costs.
        if (borrowedAsset == assetToLiquidate) {
            failure("Liquidation::CollateralSameAsBorrow", uint256(assetToLiquidate), uint256(borrowedAsset));
            return 0;
        }

        if (borrowedAssetAmount == 0) {
            failure("Liquidation::ZeroBorrowDeliveryAmount", uint256(borrowedAsset));
            return 0;
        }

        // Make sure msg.sender has as much of the borrowed asset as they are claiming to deliver
        // NOTE: liquidator is responsible for truing up their balance with any accrued interest, if that is necessary
        // to support the liquidation amount. Not truing up here avoids excess gas consumption for liquidators with a
        // large balance of borrowedAsset who wish to liquidate multiple under-collateralized borrows.
        uint256 liquidatorBalance = getBalance(msg.sender, LedgerAccount.Supply, borrowedAsset);
        if (liquidatorBalance < borrowedAssetAmount) {
            failure("Liquidation::InsufficientReplacementBalance", liquidatorBalance, uint256(borrowedAssetAmount));
            return 0;
        }

        // true up borrow balance first
        if (!accrueBorrowInterest(borrower, borrowedAsset)) {
            return 0;
        }

        uint256 borrowBalance = getBalance(borrower, LedgerAccount.Borrow, borrowedAsset);

        // Only check shortfall after truing up borrow balance.
        uint256 shortfall = collateralShortfall(borrower);
        // Only allow conversion if there is a non-zero shortfall
        if (shortfall == 0) {
            failure("Liquidation::ValidCollateralRatio", uint256(borrower));
            return 0;
        }

        // Disallow liquidation that exceeds current balance
        if (borrowedAssetAmount > borrowBalance) {
            failure("Liquidation::ExcessReplacementAmount", uint256(borrowedAssetAmount), uint(borrowBalance));
            return 0;
        }

        // TODO Later: We can use shortfall calculated above to limit amount of collateral seized.
        // We probably will want to allow the seizure to be slightly more than the shortfall to
        // increase the chance of the borrower staying within the valid collateral ratio after the
        // current liquidation is completed.

        // How much collateral should the liquidator receive?
        uint256 seizeCollateralAmount =
            getConvertedAssetValueWithDiscount(borrowedAsset, borrowedAssetAmount,
                assetToLiquidate, liquidationDiscountRateBPS);

        // Make sure borrower has enough of the requested collateral
        uint256 collateralBalance = getBalance(borrower, LedgerAccount.Supply, assetToLiquidate);
        if(collateralBalance < seizeCollateralAmount) {
            failure("Liquidation::InsufficientCollateral", collateralBalance, seizeCollateralAmount);
            return 0;
        }

        return seizeCollateralAmount;
    }

    /**
      * @notice `liquidateCollateral` enables a 3rd party to reduce a loan balance and receive the specified collateral
      * from the borrower.  It can only be used if the borrower is under the minimum collateral ratio.  As an incentive
      * to the liquidator, the collateral asset is priced at a small discount to its current price in the PriceOracle.
      * @param borrower the account whose borrow will be reduced
      * @param borrowedAsset the type of asset that was borrowed and that will be supplied by the msg.sender. msg.sender
      * must hold asset in the Compound Money Market.
      * @param borrowedAssetAmount how much of the borrowed asset msg.sender is supplying; it will be applied to reduce
      * the balance of the borrow
      * @param assetToLiquidate what asset msg.sender should receive in exchange- note that this will be
      * transferred from the borrower, so the borrower must have enough of the asset to support the amount resulting
      * from the borrowedAssetAmount and the discounted conversion price
      * @return the amount of collateral that was delivered to msg.sender. If 0 is returned, no liquidation occurred.
      * Check logs for failure reason.
      */
    function liquidateCollateral(address borrower, address borrowedAsset, uint borrowedAssetAmount, address assetToLiquidate) public returns (uint256) {

        uint256 liquidationAmount = previewLiquidateCollateral(borrower, borrowedAsset, borrowedAssetAmount, assetToLiquidate);
        if(liquidationAmount == 0) {
            return 0; // previewLiquidateCollateral should have generated a graceful failure message
        }

        // seize collateral
        credit(LedgerReason.CollateralPayBorrow, LedgerAccount.Supply, msg.sender, assetToLiquidate, liquidationAmount);
        debit(LedgerReason.CollateralPayBorrow, LedgerAccount.Supply, borrower, assetToLiquidate, liquidationAmount);

        // reduce borrow balance
        credit(LedgerReason.CollateralPayBorrow, LedgerAccount.Borrow, borrower, borrowedAsset, borrowedAssetAmount);
        debit(LedgerReason.CollateralPayBorrow, LedgerAccount.Supply, msg.sender, borrowedAsset, borrowedAssetAmount);

        return liquidationAmount;
    }

    /**
      * @notice `getBorrowBalance` returns the balance (with interest) for
      *         the given customers's borrow of the given asset (e.g. W-Eth or OMG)
      * @param customer The customer
      * @param asset The asset to check the balance of
      * @return The borrow balance of given account
      */
    function getBorrowBalance(address customer, address asset) public returns (uint256) {
        if (!saveBlockInterest(asset, LedgerAccount.Borrow)) {
            revert();
        }

        return interestRateStorage.getCurrentBalance(
            uint8(LedgerAccount.Borrow),
            asset,
            ledgerStorage.getBalanceBlockNumber(customer, uint8(LedgerAccount.Borrow), asset),
            ledgerStorage.getBalance(customer, uint8(LedgerAccount.Borrow), asset)
        );
    }

    /**
      * @notice `accrueBorrowInterest` accrues any current interest on a given borrow.
      * @param customer The customer
      * @param asset The asset to accrue borrow interest on
      * @return success or failure
      */
    function accrueBorrowInterest(address customer, address asset) public returns (bool) {
        uint256 blockNumber = ledgerStorage.getBalanceBlockNumber(customer, uint8(LedgerAccount.Borrow), asset);

        if (blockNumber != block.number) {
            uint256 balanceWithInterest = getBorrowBalance(customer, asset);
            uint256 balanceLessInterest = ledgerStorage.getBalance(customer, uint8(LedgerAccount.Borrow), asset);

            if (balanceWithInterest - balanceLessInterest > balanceWithInterest) {
                // Interest should never be negative
                failure("Borrower::InterestUnderflow", uint256(asset), uint256(customer), balanceWithInterest, balanceLessInterest);
                return false;
            }

            uint256 interest = balanceWithInterest - balanceLessInterest;

            if (interest != 0) {
                credit(LedgerReason.Interest, LedgerAccount.InterestIncome, customer, asset, interest);
                debit(LedgerReason.Interest, LedgerAccount.Borrow, customer, asset, interest);
                if (!ledgerStorage.saveCheckpoint(customer, uint8(LedgerAccount.Borrow), asset)) {
                    revert();
                }
          }
        }

        return true;
    }


    /**
      * @notice `validCollateralRatio` determines if a the requested amount is valid based on the minimum collateral ratio
      * @param borrowAmount the requested borrow amount
      * @param borrowAsset denomination of borrow
      * @return boolean true if the requested amount is valid and false otherwise
      */
    function validCollateralRatio(uint256 borrowAmount, address borrowAsset) internal returns (bool) {
        return validCollateralRatioBorrower(msg.sender, borrowAmount, borrowAsset);
    }


    /**
     * `getConvertedAssetValueWithDiscount` returns the PriceOracle's view of the current
     * value of srcAsset in terms of targetAsset, after applying the specified discount to
     * the oracle's targetAsset value. Returns 0 if either asset is unknown.
     *
     * @param srcAsset The address of the asset to query
     * @param srcAssetAmount The amount in base units of the asset
     * @param targetAsset The asset in which we want to value srcAsset
     * @param targetDiscountRateBPS the unscaled numerator for basis points discount to be applied to current PriceOracle
     * price of targetAsset (aka for a discount of 5% it should be 500)
     * @return value The value in wei of the asset, or zero.
     */
    function getConvertedAssetValueWithDiscount(address srcAsset, uint256 srcAssetAmount, address targetAsset, uint16 targetDiscountRateBPS) public view returns(uint) {

        if(srcAsset == targetAsset) {
            return srcAssetAmount;
        }

        // We get scaled value from oracle and add discount scaling on top.
        uint scaledSrcValue = scaledDiscountPrice(priceOracle.getScaledValue(srcAsset), 0);
        uint scaledTargetValue = scaledDiscountPrice(priceOracle.getScaledValue(targetAsset), targetDiscountRateBPS);

        if (scaledSrcValue == 0 || scaledTargetValue == 0) {
            return 0; // not supported
        }

        // since we have discount scaling in both the numerator and the denominator, they cancel each other out
        // and we do not need an explicit de-scale operation.
        return (scaledSrcValue * srcAssetAmount) / scaledTargetValue;
    }

    /**
      * @notice `scaledDiscountPrice`
      * @param price value from PriceOracle for an asset
      * @param unscaledDiscountRateBPS the numerator of a basis points fraction, e.g it should be 500 to represent 5%. 0 is a valid discount.
      * @return the scaled discount price after applying the discount rate
      */
    function scaledDiscountPrice(uint price, uint16 unscaledDiscountRateBPS) public pure returns (uint) {

        return (( basisPointMultiplier*discountRateScale - (unscaledDiscountRateBPS * discountRateScale)) * price) / basisPointMultiplier;
    }

}
