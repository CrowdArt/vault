pragma solidity ^0.4.19;

/**
  * @title Test Contract for Ledger Storage
  * @author Compound
  */
contract TestLedgerStorage {
    // customer -> ledgerAccount -> asset -> amount
    mapping(address => mapping(uint8 => mapping(address => uint256))) balances;

    function setAccountBalance(address customer, uint8 ledgerAccount, address asset, uint256 balance) public returns (uint256) {
        return balances[customer][ledgerAccount][asset] = balance;
    }

    function getBalance(address customer, uint8 ledgerAccount, address asset) public view returns (uint256) {
        return balances[customer][ledgerAccount][asset];
    }

    function getBalanceBlockNumber(address customer, uint8 ledgerAccount, address asset) public view returns (uint256) {
        if(customer != 255 && ledgerAccount != 255 && asset != 255) {
            return block.number;
        } else {
            return block.number;
        }

    }
}