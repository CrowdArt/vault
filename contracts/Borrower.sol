pragma solidity ^0.4.19;

import "./Ledger.sol";
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
contract Borrower is Graceful, Owned, Ledger {
    PriceOracle public priceOracle;
    BorrowStorage public borrowStorage;

    uint16 public liquidationDiscountRateBPS = 200;

    function Borrower () public {}

    /**
      * @notice `setPriceOracle` sets the priceOracle storage location for this contract
      * @dev This is for long-term data storage (TODO: Test)
      * @param priceOracleAddress The contract which acts as the long-term PriceOracle store
      * @return Success of failure of operation
      */
    function setPriceOracle(address priceOracleAddress) public returns (bool) {
        if (!checkOwner()) {
            return false;
        }

        priceOracle = PriceOracle(priceOracleAddress);

        return true;
    }

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
      * @param basisPoints will be divided by 10000 to calculate the discount rate.  Must be <= 3000.
      * @return Success or failure of operation
      */
    function setLiquidationDiscountRateBPS(uint16 basisPoints) public returns (bool) {
        if (!checkOwner()) {
            return false;
        }
        if(basisPoints > 3000) {
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
            failure("Borrower::InvalidCollateralRatio", uint256(asset), uint256(amount),
                uint256(priceOracle.getAssetValue(asset, amount)), uint256(getValueEquivalent(msg.sender)));
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
            failure("Borrower::CollateralSameAsBorrow", uint256(assetToLiquidate), uint256(borrowedAsset));
            return 0;
        }

        if (borrowedAssetAmount == 0) {
            failure("Borrower::ZeroBorrowDeliveryAmount", uint256(borrowedAsset));
            return 0;
        }

        // Make sure msg.sender has as much of the borrowed asset as they are claiming to deliver
        // NOTE: liquidator is responsible for truing up their balance with any accrued interest, if that is necessary
        // to support the liquidation amount. Not truing up here avoids excess gas consumption for liquidators with a
        // large balance of borrowedAsset who wish to liquidate multiple under-collateralized borrows.
        uint256 liquidatorBalance = getBalance(msg.sender, LedgerAccount.Supply, borrowedAsset);
        if (liquidatorBalance < borrowedAssetAmount) {
            failure("Borrower::InsufficientReplacementBalance", liquidatorBalance, uint256(borrowedAssetAmount));
            return 0;
        }

        // true up borrow balance first
        if (!accrueBorrowInterest(borrower, borrowedAsset)) {
            return 0;
        }

        uint256 borrowBalance = getBalance(borrower, LedgerAccount.Borrow, borrowedAsset);

        // Only check shortfall after truing up borrow balance.
        int256 shortfall = collateralShortfall(borrower);
        // Only allow conversion if there is a non-zero shortfall
        if (shortfall == 0) {
            failure("Borrower::ValidCollateralRatio", uint256(borrower));
            return 0;
        }

        // Disallow liquidation that exceeds current balance
        if (borrowedAssetAmount > borrowBalance) {
            failure("Borrower::ExcessReplacementAmount", uint256(borrowedAssetAmount), uint(borrowBalance));
            return 0;
        }

        // TODO Later: We can use shortfall calculated above to limit amount of collateral seized.
        // We probably will want to allow the seizure to be slightly more than the shortfall to
        // increase the chance of the borrower staying within the valid collateral ratio after the
        // current liquidation is completed.

        // How much collateral should the liquidator receive?
        uint256 seizeCollateralAmount =
            priceOracle.getConvertedAssetValueWithDiscount(borrowedAsset, borrowedAssetAmount,
                assetToLiquidate, liquidationDiscountRateBPS);

        // Make sure borrower has enough of the requested collateral
        uint256 collateralBalance = getBalance(borrower, LedgerAccount.Supply, assetToLiquidate);
        if(collateralBalance < seizeCollateralAmount) {
            failure("Borrower::InsufficientCollateral", collateralBalance, seizeCollateralAmount);
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
      * @notice `getMaxBorrowAvailable` gets the maximum borrow available
      * @param account the address of the account
      * @return uint256 the maximum borrow amount available
      */
    function getMaxBorrowAvailable(address account) public returns (uint256) {
        int256 valueEquivalent = getValueEquivalent(account);
        if(valueEquivalent <= 0) {
            return 0;
        }
        return uint256(valueEquivalent) * borrowStorage.minimumCollateralRatio();
    }

    /**
      * @notice `validCollateralRatio` determines if a the requested amount is valid based on the minimum collateral ratio
      * @param borrowAmount the requested borrow amount
      * @param borrowAsset denomination of borrow
      * @return boolean true if the requested amount is valid and false otherwise
      */
    function validCollateralRatio(uint256 borrowAmount, address borrowAsset) internal returns (bool) {
        // TODO valid if borrower has loans for multiple assets?
        return validCollateralRatioNotSender(msg.sender, borrowAmount, borrowAsset);
    }

    /**
      *
      * @notice `validCollateralRatioNotSender` determines if a the requested amount is valid for the specified borrower based on the minimum collateral ratio
      * @param borrower the borrower whose collateral should be examined
      * @param borrowAmount the requested (or current) borrow amount
      * @param borrowAsset denomination of borrow
      * @return boolean true if the requested amount is valid and false otherwise
      */
    function validCollateralRatioNotSender(address borrower, uint256 borrowAmount, address borrowAsset) internal returns (bool) {
        int256 valueEquivalent = getValueEquivalent(borrower);
        if(valueEquivalent <= 0) {
            return false;
        }
        // TODO valid if borrower has loans for multiple assets?
        return (uint256(valueEquivalent) * borrowStorage.minimumCollateralRatio()) >= priceOracle.getAssetValue(borrowAsset, borrowAmount);
    }

    /**
      * @notice `collateralShortfall` returns eth equivalent value of collateral needed to bring borrower to a valid collateral ratio,
      * or 0 if the borrower is already at or above valid collateral ratio
      * @param borrower account to check
      * @return the collateral shortfall value, or 0 if borrower has enough collateral
      */
    function collateralShortfall(address borrower) public returns (int256) {
        ValueEquivalents memory ve = getValueEquivalents(borrower);
        int256 netValueEquivalent = int256(ve.supplyValue - ve.borrowValue);

        int256 requiredValue = int256(ve.borrowValue / borrowStorage.minimumCollateralRatio());
        if(netValueEquivalent >= requiredValue) {
            return 0;
        }
        return requiredValue - netValueEquivalent;
    }

    // There are places where it is useful to have both total supplyValue and total borrowValue.
    // This struct lets us get both at once in one loop over assets.
    struct ValueEquivalents {
        uint256 supplyValue;
        uint256 borrowValue;
    }

    function getValueEquivalents(address acct) internal returns (ValueEquivalents memory) {
        uint256 assetCount = priceOracle.getAssetsLength(); // from PriceOracle
        uint256 supplyValue = 0;
        uint256 borrowValue = 0;

        for (uint64 i = 0; i < assetCount; i++) {
            address asset = priceOracle.assets(i);
            supplyValue += priceOracle.getAssetValue(asset, getBalance(acct, LedgerAccount.Supply, asset));
            borrowValue += priceOracle.getAssetValue(asset, getBalance(acct, LedgerAccount.Borrow, asset));
        }
        return ValueEquivalents({supplyValue: supplyValue, borrowValue: borrowValue});
    }

    /**
     * @notice `getValueEquivalent` returns the value of the account based on
     * PriceOracle prices of assets. Note: this includes the Eth value itself.
     * @param acct The account to view value balance
     * @return value The value of the acct in Eth equivalency
     */
    function getValueEquivalent(address acct) public returns (int256) {
        ValueEquivalents memory ve = getValueEquivalents(acct);
        return int256(ve.supplyValue - ve.borrowValue);
    }
}
