pragma solidity ^0.4.18;

import "./Ledger.sol";
import "./base/Owned.sol";
import "./base/Graceful.sol";
import "./base/Token.sol";
import "./storage/TokenStore.sol";

/**
  * @title The Compound Supplier Account
  * @author Compound
  * @notice A Supplier account allows functions for customer supplies and withdrawals.
  */
contract Supplier is Graceful, Owned, Ledger {
    TokenStore public tokenStore;

    /**
      * @notice `setTokenStore` sets the token store contract
      * @dev This is for long-term token storage
      * @param tokenStoreAddress The contract which acts as the long-term token store
      * @return Success of failure of operation
      */
    function setTokenStore(address tokenStoreAddress) public returns (bool) {
        if (!checkOwner()) {
            return false;
        }

        tokenStore = TokenStore(tokenStoreAddress);

        return true;
    }

    /**
      * @notice `checkTokenStore` verifies token store has been set
      * @return True if token store is initialized, false otherwise
      */
    function checkTokenStore() internal returns (bool) {
        if (tokenStore == address(0)) {
            failure("Supplier::TokenStoreUninitialized");
            return false;
        }

        return true;
    }

    /**
      * @notice `setSupplyInterestRateStorage` sets the interest rate storage location for this supply contract
      * @dev This is for long-term data storage
      * @param supplyInterestRateStorage_ The contract which acts as the long-term data store
      * @return Success of failure of operation
      */
    function setSupplyInterestRateStorage(InterestRateStorage supplyInterestRateStorage_) public returns (bool) {
        if (!checkOwner()) {
            return false;
        }

        supplyInterestRateStorage = supplyInterestRateStorage_;

        return true;
    }

    /**
      * @notice `checkSupplierInterestRateStorage` verifies interest rate store has been set
      * @return True if interest rate store is initialized, false otherwise
      */
    function checkSupplierInterestRateStorage() internal returns (bool) {
        if (supplyInterestRateStorage == address(0)) {
            failure("Supplier::InterestRateStorageUnitialized");
            return false;
        }

        return true;
    }

    /**
      * @notice `customerSupply` supplies a given asset in a customer's supplier account.
      * @param asset Asset to supply
      * @param amount The amount of asset to supply
      * @return success or failure
      */
    function customerSupply(address asset, uint256 amount) public returns (bool) {
        if (!checkTokenStore()) {
            return false;
        }

        if (!checkSupplierInterestRateStorage()) {
            return false;
        }

        if (!accrueSupplyInterest(msg.sender, asset)) {
            return false;
        }

        // Transfer `tokenStore` the asset from `msg.sender`
        if (!Token(asset).transferFrom(msg.sender, address(tokenStore), amount)) {
            failure("Supplier::TokenTransferFromFail", uint256(asset), uint256(amount), uint256(msg.sender));
            return false;
        }

        debit(LedgerReason.CustomerSupply, LedgerAccount.Cash, msg.sender, asset, amount);
        credit(LedgerReason.CustomerSupply, LedgerAccount.Supply, msg.sender, asset, amount);

        return true;
    }

    /**
      * @notice `customerWithdraw` withdraws the given amount from a customer's balance of the specified asset
      * @param asset Asset type to withdraw
      * @param amount amount to withdraw
      * @param to address to withdraw to
      * @return success or failure
      */
    function customerWithdraw(address asset, uint256 amount, address to) public returns (bool) {
        if (!checkTokenStore()) {
            return false;
        }

        if (!checkSupplierInterestRateStorage()) {
            return false;
        }

        // accrue interest, which is likely to increase the balance, before checking balance.
        if (!accrueSupplyInterest(msg.sender, asset)) {
            return false;
        }

        // TODO: Use collateral-adjusted balance.  If a customer has borrows, we shouldn't let them
        // withdraw below their minimum collateral value.
        uint256 balance = getBalance(msg.sender, LedgerAccount.Supply, asset);
        if (amount > balance) {
            failure("Supplier::InsufficientBalance", uint256(asset), uint256(amount), uint256(to), uint256(balance));
            return false;
        }

        debit(LedgerReason.CustomerWithdrawal, LedgerAccount.Supply, msg.sender, asset, amount);
        credit(LedgerReason.CustomerWithdrawal, LedgerAccount.Cash, msg.sender, asset, amount);

        // Transfer asset out to `to` address
        if (!tokenStore.transferAssetOut(asset, to, amount)) {
            // TODO: We've marked the debits and credits, maybe we should reverse those?
            // Can we just do the following?
            // credit(LedgerReason.CustomerWithdrawal, LedgerAccount.Supply, msg.sender, asset, amount);
            // debit(LedgerReason.CustomerWithdrawal, LedgerAccount.Cash, msg.sender, asset, amount);
            // We probably ought to add LedgerReason.CustomerWithdrawalFailed and use that instead of LedgerReason.CustomerWithdrawal.
            // Either way, we'll likely need changes in Farmer and/or Data to process the resulting logs.
            failure("Supplier::TokenTransferToFail", uint256(asset), uint256(amount), uint256(to), uint256(balance));
            return false;
        }

        return true;
    }

    /**
      * @notice `getSupplyBalance` returns the balance (with interest) for
      *         the given account in the given asset (e.g. W-Eth or OMG)
      * @param customer The customer
      * @param asset The asset to check the balance of
      * @return The balance (with interest)
      */
    function getSupplyBalance(address customer, address asset) public view returns (uint256) {
        return supplyInterestRateStorage.getCurrentBalance(
            asset,
            ledgerStorage.getBalanceBlockNumber(customer, uint8(LedgerAccount.Supply), asset),
            ledgerStorage.getBalance(customer, uint8(LedgerAccount.Supply), asset)
        );
    }

    /**
      * @notice `accrueSupplyInterest` accrues any current interest on an
      *         supply account.
      * @param customer The customer
      * @param asset The asset to accrue supply interest on
      * @return success or failure
      */
    function accrueSupplyInterest(address customer, address asset) public returns (bool) {
        if (!checkSupplierInterestRateStorage()) {
            return false;
        }

        uint blockNumber = ledgerStorage.getBalanceBlockNumber(customer, uint8(LedgerAccount.Supply), asset);

        if (blockNumber != block.number) {
            // We need to true up balance

            uint balanceWithInterest = getSupplyBalance(customer, asset);
            uint balanceLessInterest = ledgerStorage.getBalance(customer, uint8(LedgerAccount.Supply), asset);

            if (balanceWithInterest - balanceLessInterest > balanceWithInterest) {
                // Interest should never be negative
                failure("Supplier::InterestUnderflow", uint256(asset), uint256(customer), balanceWithInterest, balanceLessInterest);
                return false;
            }

            uint interest = balanceWithInterest - balanceLessInterest;

            if (interest != 0) {
                debit(LedgerReason.Interest, LedgerAccount.InterestExpense, customer, asset, interest);
                credit(LedgerReason.Interest, LedgerAccount.Supply, customer, asset, interest);
                if (!ledgerStorage.saveCheckpoint(customer, uint8(LedgerAccount.Supply), asset)) {
                    revert();
                }
          }
        }

        return true;
    }
}
