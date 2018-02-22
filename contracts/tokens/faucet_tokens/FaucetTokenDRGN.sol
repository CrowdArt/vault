pragma solidity ^0.4.19;

import "../FaucetToken.sol";

/**
  * @title The Compound DRGN Faucet Test Token
  * @author Compound
  * @notice A simple token for test that follows faucet rules.
  */
contract FaucetTokenDRGN is FaucetToken("DRGN Faucet Token", "DRGN", 10) {
    string constant public name = "DRGN Faucet Token";
    string constant public symbol = "DRGN";
    uint8 constant public decimals = 10;
}
