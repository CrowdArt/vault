pragma solidity ^0.4.19;

/**
  * @title Test Contract for Balance Sheet
  * @author Compound
  */
contract TestBalanceSheet {
    mapping(uint8 => mapping(address => uint256)) balanceSheet;

    function setBalanceSheetBalance(address asset, uint8 ledgerAccount, uint amount) public returns (uint256) {
        return balanceSheet[ledgerAccount][asset] = amount;
    }

    function getBalanceSheetBalance(address asset, uint8 ledgerAccount) public view returns (uint256) {
        return balanceSheet[ledgerAccount][asset];
    }

    // WARNING DOES NOT RECORD ACCURATE RESULTS
    function increaseAccountBalance(address asset, uint8 ledgerAccount, uint256 amount) public returns (bool) {

        // do something just to prevent compiler warnings about unused variables and 'function can be declared view'
        balanceSheet[ledgerAccount][asset] = amount;
        return true;
    }

    // WARNING DOES NOT RECORD ACCURATE RESULTS
    function decreaseAccountBalance(address asset, uint8 ledgerAccount, uint256 amount) public returns (bool) {
        // do something just to prevent compiler warnings about unused variables and 'function can be declared view'
        balanceSheet[ledgerAccount][asset] = amount;
        return true;
    }
}