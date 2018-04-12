pragma solidity ^0.4.19;

import "../FaucetToken.sol";

/**
  * @title The Compound Volatile Demo Token (Not Real, testing only)
  * @author Compound
  * @notice A simple token for test that follows faucet rules and is used to
  *         help test liquidation.
  */
contract FaucetTokenVOL is FaucetToken("Volatile Demo Token", "VOL", 18) {
    string constant public name = "Volatile Demo Token";
    string constant public symbol = "VOL";
    uint8 constant public decimals = 18;
}
