"use strict";

const Ledger = artifacts.require("./Ledger.sol");
const WETH9 = artifacts.require("./tokens/WETH9.sol");
const TestLedgerStorage = artifacts.require("./test/TestLedgerStorage.sol");
const TestInterestModel = artifacts.require("./test/TestInterestModel.sol");
const TestBalanceSheet = artifacts.require("./test/TestBalanceSheet.sol");

const utils = require('./utils');

const customer = web3.eth.accounts[2];
const otherCustomer = web3.eth.accounts[3];
const asset = web3.eth.accounts[4];
const secondAsset = web3.eth.accounts[5];

const ledgerAccount = {
  Cash: 0,
  Borrow: 1,
  Supply: 2,
  InterestExpense: 3,
  InterestIncome: 4,
  Trading: 5
};

contract('Ledger', function(accounts) {
  var ledger;
  var etherToken;
  var testLedgerStorage;
  var testInterestModel;
  var testBalanceSheet;

  before(async () => {
    testLedgerStorage = await TestLedgerStorage.new();
    testInterestModel = await TestInterestModel.new();
    testBalanceSheet = await TestBalanceSheet.new();

    [ledger, etherToken] = await Promise.all([Ledger.new(), WETH9.new()]);

    await ledger.setLedgerStorage(testLedgerStorage.address);
    await ledger.setBalanceSheet(testBalanceSheet.address);
    await ledger.setInterestModel(testInterestModel.address);
  });

  /*
   * Most ledger functions require having a proper supplier set-up
   * and are internal, so we leave the tests in `test/Supplier.js`.
   */

  describe('#getBalance', async () => {
    it('returns account balance', async () => {
      await testLedgerStorage.setAccountBalance(customer, ledgerAccount.Supply, asset, 5);

      assert.equal(await utils.toNumber(ledger.getCustomerBalance.call(customer, ledgerAccount.Supply, asset)), 5);
      assert.equal(await utils.toNumber(ledger.getCustomerBalance.call(customer, ledgerAccount.Supply, secondAsset)), 0);
      assert.equal(await utils.toNumber(ledger.getCustomerBalance.call(otherCustomer, ledgerAccount.Supply, asset)), 0);
      assert.equal(await utils.toNumber(ledger.getCustomerBalance.call(otherCustomer, ledgerAccount.Borrow, asset)), 0);
    });
  });

  describe('#getInterestRate', async () => {
    it('should return correct supply rate', async () => {
      await testBalanceSheet.setBalanceSheetBalance(asset, ledgerAccount.Supply, 5);
      await testBalanceSheet.setBalanceSheetBalance(asset, ledgerAccount.Borrow, 10);

      assert.equal(await utils.toNumber(ledger.getInterestRate(asset, ledgerAccount.Supply)), 50010);
    });

    it('should return correct borrow rate', async () => {
      await testBalanceSheet.setBalanceSheetBalance(asset, ledgerAccount.Supply, 5);
      await testBalanceSheet.setBalanceSheetBalance(asset, ledgerAccount.Borrow, 10);

      assert.equal(await utils.toNumber(ledger.getInterestRate(asset, ledgerAccount.Borrow)), 100005);
    });

    it('should return correct other rate', async () => {
      await testBalanceSheet.setBalanceSheetBalance(asset, ledgerAccount.Supply, 5);
      await testBalanceSheet.setBalanceSheetBalance(asset, ledgerAccount.Borrow, 10);

      assert.equal(await utils.toNumber(ledger.getInterestRate(asset, ledgerAccount.Trading)), 0);
    });
  });

});
