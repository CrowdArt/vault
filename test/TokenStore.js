"use strict";

const TokenStore = artifacts.require("./storage/TokenStore.sol");
const WETH9 = artifacts.require("./tokens/WETH9.sol");

const utils = require('./utils');

contract('TokenStore', function(accounts) {
  var tokenStore;
  var etherToken;

  beforeEach(async () => {
    [tokenStore, etherToken] = await Promise.all([TokenStore.new(), WETH9.new()]);
    await tokenStore.allow(web3.eth.accounts[0]);
  });

  describe('#transferAssetOut', () => {
    it("should transfer tokens out", async () => {
      await utils.createAndTransferWeth(tokenStore.address, etherToken, 100, web3.eth.accounts[0]);

      const result = await tokenStore.transferAssetOut.call(etherToken.address, web3.eth.accounts[1], 50);

      // Should exit "true"
      assert.equal(result, true);

      await tokenStore.transferAssetOut(etherToken.address, web3.eth.accounts[1], 20);

      // verify balances in W-Eth
      assert.equal(await utils.tokenBalance(etherToken, tokenStore.address), 80);
      assert.equal(await utils.tokenBalance(etherToken, web3.eth.accounts[1]), 20);
    });

    it("should fail if no tokens available", async () => {
      await utils.assertGracefulFailure(tokenStore, "TokenStore::TokenTransferToFail", async () => {
        await tokenStore.transferAssetOut(etherToken.address, web3.eth.accounts[1], 200);
      });
    });

    it("should emit event", async () => {
      await utils.createAndTransferWeth(tokenStore.address, etherToken, 100, web3.eth.accounts[0]);
      await tokenStore.transferAssetOut(etherToken.address, web3.eth.accounts[1], 20);

      await utils.assertEvents(tokenStore, [
      {
        event: "TransferOut",
        args: {
          amount: web3.toBigNumber('20')
        }
      }]);
    });

    it("should be allowed only", async () => {
      await utils.createAndTransferWeth(tokenStore.address, etherToken, 100, web3.eth.accounts[0]);
      await utils.assertOnlyAllowed(tokenStore, tokenStore.transferAssetOut.bind(null, etherToken.address, web3.eth.accounts[1], 20), web3);
    });
  });
});