pragma solidity ^0.4.18;

import "./Ledger.sol";
import "./base/Owned.sol";

/**
  * @title The Compound Savings Account
  * @author Compound
  * @notice A Savings account allows functions for customer deposits and withdrawals.
  */
contract Savings is Owned, Ledger {

	/**
      * @notice `customerDeposit` deposits a given asset in a customer's savings account.
      * @param asset Asset to deposit
      * @param amount The amount of asset to deposit
      * @param from The customer's account which is pre-authorized for transfer
      */
    function customerDeposit(address asset, uint256 amount, address from) public {
        // TODO: Should we verify that from matches `msg.sender` or `msg.originator`?

        // Transfer ourselves the asset from `from`
        if (!Token(asset).transferFrom(from, address(this), amount)) {
            return revert();
        }

        accrueDepositInterest(from, asset);

        debit(LedgerAction.CustomerDeposit, LedgerAccount.Cash, from, asset, amount);
        credit(LedgerAction.CustomerDeposit, LedgerAccount.Deposit, from, asset, amount);
    }

    /**
      * @notice `customerWithdraw` withdraws a given amount from an customer's balance.
      * @param asset Asset type to withdraw
      * @param amount amount to withdraw
      * @param to address to withdraw to
      */
    function customerWithdraw(address asset, uint256 amount, address to) public {
        uint256 balance = accrueDepositInterest(msg.sender, asset);
        assert(amount <= balance);

        debit(LedgerAction.CustomerWithdrawal, LedgerAccount.Deposit, msg.sender, asset, amount);
        credit(LedgerAction.CustomerWithdrawal, LedgerAccount.Cash, msg.sender, asset, amount);

        // Transfer asset out to `to` address
        if (!Token(asset).transfer(to, amount)) {
            revert();
        }
    }

    /**
      * @notice `getDepositBalance` returns the balance (with interest) for
      *         the given account in the given asset (e.g. W-Eth or OMG)
      * @param customer The customer
      * @param asset The asset to check the balance of
      */
    function getDepositBalance(address customer, address asset) public view returns (uint256) {
        return getDepositBalanceAt(
            customer,
            asset,
            now);
    }

    /**
      * @notice `getDepositBalanceAt` returns the balance (with interest) for
      *         the given customer in the given asset (e.g. W-Eth or OMG)
      * @param customer The customer
      * @param asset The asset to check the balance of
      * @param timestamp The timestamp at which to check the value.
      */
    function getDepositBalanceAt(address customer, address asset, uint256 timestamp) public view returns (uint256) {
        return balanceWithInterest(
            balanceCheckpoints[customer][uint8(LedgerAccount.Deposit)][asset].balance,
            balanceCheckpoints[customer][uint8(LedgerAccount.Deposit)][asset].timestamp,
            timestamp,
            rates[asset]);
    }

    /**
      * @notice `accrueDepositInterest` accrues any current interest on an
      *         savings account.
      * @param customer The customer
      * @param asset The asset to accrue savings interest on
      */
    function accrueDepositInterest(address customer, address asset) public returns (uint256) {
        return accrueInterestAndSaveCheckpoint(LedgerAccount.Deposit, customer, asset);
    }
}
