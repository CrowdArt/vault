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
      await collateralCalculator.setScaledMinimumCollateralRatio(30000, {from: web3.eth.accounts[0]});

      assert.equal((await collateralCalculator.scaledMinCollateralToBorrowRatio.call()).valueOf(), 30000);
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

    it("should be owner only", async () => {
      await utils.assertOnlyOwner(collateralCalculator, collateralCalculator.setScaledMinimumCollateralRatio.bind(null, 50000), web3);
    });
  });
});