pragma solidity ^0.4.19;

import "./Ledger.sol";
import "./Supplier.sol";
import "./Borrower.sol";

/**
  * @title The Compound MoneyMarket Contract
  * @author Compound
  * @notice The Compound MoneyMarket Contract in the core contract governing
  *         all accounts in Compound.
  */
contract MoneyMarket is Ledger, Supplier, Borrower {

    /**
      * @notice `MoneyMarket` is the core Compound MoneyMarket contract
      */
    function MoneyMarket() public {
    }


    function foo() returns (uint8) {
        return 1;
    }

    /**
      * @notice Do not pay directly into MoneyMarket, please use `supply`.
      */
    function() payable public {
        revert();
    }
}
