"use strict";

const Borrower = artifacts.require("./Borrower.sol");

contract('Borrower', function(accounts) {
  /*
   * Most borrower functions require having a proper
   * supplier set-up, so we leave the tests in `MoneyMarket.js`,
   * which has both set.
   *
   * In the future, we may decide to create a mock for `Supplier`,
   * in which case we could properly unit-test `Borrower`.
   *
   * For now, only test pure functions here and see `test/MoneyMarket.js` for non-pure function tests
   */

  var borrower;

  beforeEach(async () => {
    borrower = await Borrower.new();
  });

  describe('#scaledDiscountPrice', async () => {

    it("returns expected amount", async () => {
      const discountedPrice = await borrower.scaledDiscountPrice.call(10, 500);
      assert.equal(discountedPrice.valueOf(), 9500000000);
    });
  });
});
