pragma solidity ^0.4.19;

import "../FaucetToken.sol";

/**
  * @title The Compound OMG Faucet Test Token
  * @author Compound
  * @notice A simple token for test that follows faucet rules.
  */
contract FaucetTokenOMG is FaucetToken("OMG Faucet Token", "OMG", 18) {
    string constant public name = "OMG Faucet Token";
    string constant public symbol = "OMG";
    uint8 constant public decimals = 18;
}
