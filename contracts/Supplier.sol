pragma solidity ^0.4.19;

import "./CollateralCalculator.sol";
import "./base/Owned.sol";
import "./base/Graceful.sol";
import "./eip20/EIP20.sol";
import "./eip20/EIP20Interface.sol";
import "./storage/TokenStore.sol";

/**
  * @title The Compound Supplier Account
  * @author Compound
  * @notice A Supplier account allows functions for customer supplies and withdrawals.
  */
contract Supplier is Graceful, Owned, CollateralCalculator {
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
      * @notice `customerSupply` supplies a given asset in a customer's supplier account.
      * @param asset Asset to supply
      * @param amount The amount of asset to supply
      * @return success or failure
      */
    function customerSupply(address asset, uint256 amount) public returns (bool) {

        if (!checkTokenStore()) {
            return false;
        }

        if (!saveBlockInterest(asset, LedgerAccount.Supply)) {
            failure("Supplier::FailedToSaveBlockInterest", uint256(asset), uint256(LedgerAccount.Supply));
            return false;
        }

        if (!accrueSupplyInterest(msg.sender, asset)) {
            return false;
        }

        // EIP20 reverts if not allowed or balance too low.  We do a pre-check to enable a graceful failure message instead.
        EIP20 token = EIP20(asset);
        uint256 allowance = token.allowance(msg.sender, address(this));
        uint256 balance = token.balanceOf(msg.sender);
        bool allowed = (balance >= amount && allowance >= amount);

        if(!allowed) {
            failure("Supplier::TokenTransferFromFail", uint256(asset), uint256(amount), uint256(msg.sender));
            return false;
        }

        token.transferFrom(msg.sender, address(tokenStore), amount);

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

        if (!saveBlockInterest(asset, LedgerAccount.Supply)) {
            failure("Supplier::FailedToSaveBlockInterest", uint256(asset), uint256(LedgerAccount.Supply));
            return false;
        }

        // accrue interest, which is likely to increase the balance, before checking balance.
        if (!accrueSupplyInterest(msg.sender, asset)) {
            return false;
        }

        // Make sure account holds enough of asset
        uint256 balance = getBalance(msg.sender, LedgerAccount.Supply, asset);
        if (amount > balance) {
            failure("Supplier::InsufficientBalance", uint256(asset), uint256(amount), uint256(to), uint256(balance));
            return false;
        }

        // make sure asset is not encumbered as collateral. requires eth-equivalent value calculation
        if(!canWithdrawCollateral(msg.sender, asset, amount)) {
            return false; // canWithdrawCollateral generates a graceful failure when it returns false
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
    function getSupplyBalance(address customer, address asset) public returns (uint256) {
        if (!saveBlockInterest(asset, LedgerAccount.Supply)) {
            revert();
        }

        return interestRateStorage.getCurrentBalance(
            uint8(LedgerAccount.Supply),
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
        uint256 blockNumber = ledgerStorage.getBalanceBlockNumber(customer, uint8(LedgerAccount.Supply), asset);

        if (blockNumber != 0 && blockNumber != block.number) {
            // We need to true up balance

            uint256 balanceWithInterest = getSupplyBalance(customer, asset);
            uint256 balanceLessInterest = ledgerStorage.getBalance(customer, uint8(LedgerAccount.Supply), asset);

            if (balanceWithInterest - balanceLessInterest > balanceWithInterest) {
                // Interest should never be negative
                failure("Supplier::InterestUnderflow", uint256(asset), uint256(customer), balanceWithInterest, balanceLessInterest);
                return false;
            }

            uint256 interest = balanceWithInterest - balanceLessInterest;

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
