"use strict";

const TokenStore = artifacts.require("./storage/TokenStore.sol");
const WETH9 = artifacts.require("./tokens/WETH9.sol");

const utils = require('./utils');

contract('TokenStore', function(accounts) {
  var tokenStore;
  var etherToken;

  var holder;
  var recipient;

  beforeEach(async () => {

    holder = web3.eth.accounts[0];
    recipient = web3.eth.accounts[1];

    [tokenStore, etherToken] = await Promise.all([TokenStore.new(), WETH9.new()]);
    await tokenStore.allow(holder);
  });

  describe('#transferAssetOut', () => {
    it("should transfer tokens out", async () => {
      await utils.createAndTransferWeth(tokenStore.address, etherToken, 100, web3.eth.accounts[0]);

      await tokenStore.transferAssetOut(etherToken.address, web3.eth.accounts[1], 20, {from: holder});

      // verify balances in W-Eth
      assert.equal(await utils.tokenBalance(etherToken, tokenStore.address), 80);
      assert.equal(await utils.tokenBalance(etherToken, web3.eth.accounts[1]), 20);
    });

    it("should fail if no tokens available", async () => {
      await utils.awaitGracefulFailureCollectMissing(assert, tokenStore, "TokenStore::TokenTransferToFail", async () => {
        await tokenStore.transferAssetOut(etherToken.address, web3.eth.accounts[1], 200);
      });
    });

    it("should emit event", async () => {
      // deposit WETH into holder and then transfer to tokenStore.
      await utils.createAndTransferWeth(tokenStore.address, etherToken, 100, holder);

      // transfer
      await tokenStore.transferAssetOut(etherToken.address, recipient, 20, {from: holder});

      await utils.awaitAssertEventsCollectMissing(assert, tokenStore, [
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