pragma solidity ^0.4.19;

import "../FaucetToken.sol";

/**
  * @title The Compound ZRX Faucet Test Token
  * @author Compound
  * @notice A simple token for test that follows faucet rules.
  */
contract FaucetTokenZRX is FaucetToken("ZRX Faucet Token", "ZRX", 18) {
    string constant public name = "ZRX Faucet Token";
    string constant public symbol = "ZRX";
    uint8 constant public decimals = 18;
}
