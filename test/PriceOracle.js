"use strict";

const PriceOracle = artifacts.require("./storage/PriceOracle.sol");

const utils = require('./utils');

const tokenAddrs = utils.tokenAddrs;
const toAssetValue = (value) => (value * 10 ** 9);

contract('PriceOracle', function(accounts) {
  var priceOracle;

  beforeEach(async () => {
    priceOracle = await PriceOracle.new();
    await priceOracle.allow(web3.eth.accounts[0]);
  });

  describe('#setAssetValue', () => {
    it("should set the asset's given value and emit events", async () => {
      await priceOracle.setAssetValue(tokenAddrs.OMG, toAssetValue(15) , {from: web3.eth.accounts[0]});
      const balance = await priceOracle.getAssetValue.call(tokenAddrs.OMG, 1);
      assert.equal(balance.valueOf(), 15);

      await utils.assertEvents(priceOracle, [
        {
          event: "NewAsset",
          args: {
            asset: tokenAddrs.OMG
          }
        },
        {
          event: "AssetValueUpdate",
          args: {
            asset: tokenAddrs.OMG,
            valueInWei: web3.toBigNumber('15000000000')
          }
        },
      ]);

      await priceOracle.setAssetValue(tokenAddrs.OMG, toAssetValue(0.01) , {from: web3.eth.accounts[0]});
      assert.equal(await utils.toNumber(priceOracle.getAssetValue.call(tokenAddrs.OMG, 1000)), 10);
      assert.equal(await utils.toNumber(priceOracle.lastUpdatedAtBlock.call(tokenAddrs.OMG)), web3.eth.blockNumber);

      const supportedAssetsArray = await priceOracle.getSupportedAssets.call();
      assert.equal(supportedAssetsArray.length, 1);
      assert.equal(supportedAssetsArray[0], tokenAddrs.OMG);
    });

    it("should only allow owner to set asset value", async () => {
      await utils.assertOnlyOwner(priceOracle, priceOracle.setAssetValue.bind(null, tokenAddrs.OMG, web3.toWei(15, "ether")), web3);
    });
  });

  describe('#getAssetValue', async () => {
    describe('before it is set', () => {
      it("returns 0", async () => {
        const balance = await priceOracle.getAssetValue.call(tokenAddrs.BAT, 1);
        assert.equal(balance.valueOf(), 0);
      });
    });

    describe('after it is set', async () => {
      it("returns amount", async () => {
        await priceOracle.setAssetValue(tokenAddrs.OMG, toAssetValue(15) , {from: web3.eth.accounts[0]});
        const balance = await priceOracle.getAssetValue.call(tokenAddrs.OMG, 1);
        assert.equal(balance.valueOf(), 15);
      });
    });
  });

  describe('#getSupportedAssets', async () => {
    it('lists supported assets', async () => {
      await priceOracle.setAssetValue(tokenAddrs.OMG, toAssetValue(15) , {from: web3.eth.accounts[0]});
      const assets = await priceOracle.getSupportedAssets.call();
      assert.equal(assets.valueOf().length, 1);
      assert.equal(assets.valueOf()[0], tokenAddrs.OMG);
    });
  });

  describe('#getAssetsLength', async () => {
    describe('after it is set', async () => {
      it("returns the length", async () => {
        await priceOracle.setAssetValue(tokenAddrs.OMG, toAssetValue(15) , {from: web3.eth.accounts[0]});
        await priceOracle.setAssetValue(tokenAddrs.BAT, toAssetValue(17) , {from: web3.eth.accounts[0]});
        const length = await priceOracle.getAssetsLength.call();
        assert.equal(length.valueOf(), 2);
      });
    })
  });

  describe('#getConvertedAssetValue', async () => {
    describe('before either asset is set', () => {
      it("returns 0", async () => {
        const balance = await priceOracle.getConvertedAssetValue.call(tokenAddrs.BAT, 1, tokenAddrs.OMG);
        assert.equal(balance.valueOf(), 0);
      });
    });

    describe('before target asset value is set', () => {
      it("returns 0", async () => {
        await priceOracle.setAssetValue(tokenAddrs.BAT, toAssetValue(17) , {from: web3.eth.accounts[0]});
        const balance = await priceOracle.getConvertedAssetValue.call(tokenAddrs.BAT, 1, tokenAddrs.OMG);
        assert.equal(balance.valueOf(), 0);
      });
    });

    describe('before src asset value is set', () => {
      it("returns 0", async () => {
        await priceOracle.setAssetValue(tokenAddrs.OMG, toAssetValue(15) , {from: web3.eth.accounts[0]});
        const balance = await priceOracle.getConvertedAssetValue.call(tokenAddrs.BAT, 1, tokenAddrs.OMG);
        assert.equal(balance.valueOf(), 0);
      });
    });


    describe('conversion in terms of a more valuable asset', async () => {
      it("returns amount", async () => {
        await priceOracle.setAssetValue(tokenAddrs.BAT, toAssetValue(2) , {from: web3.eth.accounts[0]});
        await priceOracle.setAssetValue(tokenAddrs.OMG, toAssetValue(5) , {from: web3.eth.accounts[0]});
        const balance = await priceOracle.getConvertedAssetValue.call(tokenAddrs.BAT, (10 ** 18), tokenAddrs.OMG);
        assert.equal(balance.valueOf(), 400000000000000000); // (1 * 10^18)*2/5 or 0.4E18
      });
    });

    describe('conversion in terms of a less valuable asset', async () => {
      it("returns expected amount", async() => {
       // Asset1 = 5 * 10E18 (aka 5 Eth)
       // Asset2 = 2 * 10E18 (aka 2 Eth)
        await priceOracle.setAssetValue(tokenAddrs.BAT, toAssetValue(5) , {from: web3.eth.accounts[0]});
        await priceOracle.setAssetValue(tokenAddrs.OMG, toAssetValue(2) , {from: web3.eth.accounts[0]});
        const balance = await priceOracle.getConvertedAssetValue.call(tokenAddrs.BAT, (10 ** 18), tokenAddrs.OMG);
        assert.equal(balance.valueOf(), 2500000000000000000); // (1 * 10^18)*5/2 or 2.5E18
    });
    });
  });
});
