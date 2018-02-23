"use strict";

const CollateralCalculator = artifacts.require("./storage/CollateralCalculator.sol");
const utils = require('./utils');

contract('CollateralCalculator', function(accounts) {

  var collateralCalculator;

  beforeEach(async () => {
    [collateralCalculator] = await Promise.all([CollateralCalculator.new()]);
    // await collateralCalculator.allow(web3.eth.accounts[0]);
  });

  describe('#setScaledMinimumCollateralRatio', () => {
    it("should change minimumCollateralRatio", async () => {
      await collateralCalculator.setScaledMinimumCollateralRatio(10001, {from: web3.eth.accounts[0]});

      assert.equal((await collateralCalculator.scaledMinCollateralToBorrowRatio.call()).valueOf(), 10001);
    });

    it("should emit event", async () => {
      await collateralCalculator.setScaledMinimumCollateralRatio(40000, {from: web3.eth.accounts[0]});

      await utils.awaitAssertEventsCollectMissing(assert, collateralCalculator, [
        {
          event: "MinimumCollateralRatioChange",
          args: {
            newScaledMinimumCollateralRatio: web3.toBigNumber('40000')
          }
        }]);
    });

    // minimumCollateralRatio <= scale represents a collateral to borrow ratio <= 1, which is not allowed
    it("should reject minimumCollateralRatio < scale", async () => {
      const accepted = await collateralCalculator.setScaledMinimumCollateralRatio.call(10000, {from: web3.eth.accounts[0]});

      assert.equal(accepted, false);

      assert.equal((await collateralCalculator.scaledMinCollateralToBorrowRatio.call()).valueOf(), 20000);
    });

    it("should be owner only", async () => {
      await utils.assertOnlyOwner(collateralCalculator, collateralCalculator.setScaledMinimumCollateralRatio.bind(null, 50000), web3);
    });
  });
});