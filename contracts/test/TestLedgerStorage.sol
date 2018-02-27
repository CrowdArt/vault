pragma solidity ^0.4.19;

/**
  * @title Test Contract for Ledger Storage
  * @author Compound
  */
contract TestLedgerStorage {
    // customer -> ledgerAccount -> asset -> amount
    mapping(address => mapping(uint8 => mapping(address => uint256))) balances;

    mapping(address => uint8) notRealBalanceCheckpoints;

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

    function increaseBalanceByAmount(address customer, uint8 ledgerAccount, address asset, uint256 amount) public returns (bool) {

        uint256 current = balances[customer][ledgerAccount][asset];
        uint256 newBalance = current + amount;
        if(newBalance < current) {
            revert();
        }
        setAccountBalance(customer, ledgerAccount, asset, newBalance);
        return true;
    }

    function decreaseBalanceByAmount(address customer, uint8 ledgerAccount, address asset, uint256 amount) public returns (bool) {
        uint256 current = balances[customer][ledgerAccount][asset];
        uint256 newBalance = current - amount;
        if(newBalance > current) {
            revert();
        }
        setAccountBalance(customer, ledgerAccount, asset, newBalance);
        return true;
    }

    // WARNING: DOES NOTHING BUT RETURNS TRUE
    function saveCheckpoint(address customer, uint8 ledgerAccount, address asset) public returns (bool) {

        // all the nonsense here is to avoid compiler warnings about unused variables and 'function can be declared view'
        notRealBalanceCheckpoints[customer] = ledgerAccount;
        if(customer != asset && ledgerAccount != 100000000) {
            return true;
        }
        return true;

    }


}