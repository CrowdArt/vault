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

    // WARNING DOES NOTHING BUT RETURNS TRUE
    function increaseAccountBalance(address asset, uint8 ledgerAccount, uint256 amount) public returns (bool) {
        return true;
    }

    // WARNING DOES NOTHING BUT RETURNS TRUE
    function decreaseAccountBalance(address asset, uint8 ledgerAccount, uint256 amount) public returns (bool) {
        return true;
    }
}