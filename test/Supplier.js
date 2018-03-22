"use strict";

const BigNumber = require('bignumber.js');

const BalanceSheet = artifacts.require("./storage/BalanceSheet.sol");
const WETH9 = artifacts.require("./tokens/WETH9.sol");
const LedgerStorage = artifacts.require("./storage/LedgerStorage.sol");
const InterestModel = artifacts.require("./InterestModel.sol");
const InterestRateStorage = artifacts.require("./storage/InterestRateStorage.sol");
const Supplier = artifacts.require("./MoneyMarket.sol");
const TokenStore = artifacts.require("./storage/TokenStore.sol");
const PriceOracle = artifacts.require("./storage/PriceOracle.sol");

const utils = require('./utils');

const interestRateScale = (10 ** 16); // InterestRateStorage.sol interestRateScale
const blockUnitsPerYear = 210240; // Tied to test set up in which InterestRateStorage.sol blockScale is 10. 2102400 blocks per year / 10 blocks per unit = 210240 units per year

const LedgerType = {
  Debit: web3.toBigNumber(0),
  Credit: web3.toBigNumber(1)
};

const LedgerReason = {
  CustomerSupply: web3.toBigNumber(0),
  CustomerWithdrawal: web3.toBigNumber(1),
  Interest: web3.toBigNumber(2)
};

const LedgerAccount = {
  Cash: web3.toBigNumber(0),
  Borrow: web3.toBigNumber(1),
  Supply: web3.toBigNumber(2),
  InterestExpense: web3.toBigNumber(3),
  InterestIncome: web3.toBigNumber(4)
};

contract('Supplier', function(accounts) {
  var supplierContract;
  var etherToken;
  var tokenStore;
  var priceOracle;
  var restores;
  var customerAccount;

  before(async () => {
    const balanceSheet = await BalanceSheet.deployed();
    const interestRateStorage = await InterestRateStorage.deployed();
    const interestModel = await InterestModel.deployed();
    const ledgerStorage = await LedgerStorage.deployed();

    supplierContract = await Supplier.new();
    await supplierContract.setBalanceSheet(balanceSheet.address);
    await supplierContract.setInterestRateStorage(interestRateStorage.address);
    await supplierContract.setInterestModel(interestModel.address);
    await supplierContract.setLedgerStorage(ledgerStorage.address);

    customerAccount = web3.eth.accounts[1];

    restores = await utils.allowAll([balanceSheet, interestRateStorage, ledgerStorage], supplierContract);
  });

  beforeEach(async () => {
    etherToken = await WETH9.new();
    tokenStore = await TokenStore.new();

    await supplierContract.setTokenStore(tokenStore.address);
    await tokenStore.allow(supplierContract.address);

    priceOracle = await PriceOracle.new();
    await supplierContract.setPriceOracle(priceOracle.address);
    await utils.setAssetValue(priceOracle, etherToken, 1, web3);

  });

  after(async() => {
    await utils.restoreAll(restores);
  });

  describe('#customerSupply', () => {
    it("should increase the user's balance", async () => {
      // first supply assets into W-Eth contract
      await utils.createAndApproveWeth(supplierContract, etherToken, 100, customerAccount, 100);

      // verify initial state

      assert.equal(await utils.tokenBalance(etherToken, supplierContract.address), 0);
      assert.equal(await utils.tokenBalance(etherToken, customerAccount), 100);

      // commit supply in supplier
      assert.equal(await supplierContract.customerSupply.call(etherToken.address, 100, {from: customerAccount}), true);
      await supplierContract.customerSupply(etherToken.address, 100, {from: customerAccount});

      // verify balance in supplier
      assert.equal(await utils.ledgerAccountBalance(supplierContract, customerAccount, etherToken.address), 100);

      // verify balances in W-Eth
      assert.equal(await utils.tokenBalance(etherToken, tokenStore.address), 100);
      assert.equal(await utils.tokenBalance(etherToken, customerAccount), 0);
    });

    it("should create debit and credit ledger entries", async () => {
      await utils.supplyEth(supplierContract, etherToken, 100, customerAccount);

      await utils.awaitAssertEventsCollectMissing(assert, supplierContract, [
      {
        event: "LedgerEntry",
        args: {
          ledgerReason: LedgerReason.CustomerSupply,
          ledgerType: LedgerType.Debit,
          ledgerAccount: LedgerAccount.Cash,
          customer: customerAccount,
          asset: etherToken.address,
          amount: web3.toBigNumber('100'),
          balance: web3.toBigNumber('0'),
          interestRateBPS: web3.toBigNumber('0'),
          nextPaymentDate: web3.toBigNumber('0')
        }
      },
      {
        event: "LedgerEntry",
        args: {
          ledgerReason: LedgerReason.CustomerSupply,
          ledgerType: LedgerType.Credit,
          ledgerAccount: LedgerAccount.Supply,
          customer: customerAccount,
          asset: etherToken.address,
          amount: web3.toBigNumber('100'),
          balance: web3.toBigNumber('100'),
          interestRateBPS: web3.toBigNumber('0'),
          nextPaymentDate: web3.toBigNumber('0')
        }
      }
      ]);
    });

    it("should only work if ERC20 properly authorized amount", async () => {
      const approvedAmount = 99;
      const balance = approvedAmount + 1;
      await utils.createAndApproveWeth(supplierContract, etherToken, balance, customerAccount, approvedAmount);

      await utils.awaitGracefulFailureCollectMissing(assert, supplierContract, "Supplier::TokenTransferFromFail", [null, approvedAmount + 1, approvedAmount, null], async () => {
        await supplierContract.customerSupply(etherToken.address, approvedAmount + 1, {from: customerAccount});
      });

      // verify it works for the approved amount
      const supplied = await supplierContract.customerSupply(etherToken.address, approvedAmount, {from: customerAccount});
      assert(supplied, "supply of approved amount failed");
    });

    it("should fail for unknown assets", async () => {
      try {
        await supplierContract.customerSupply(0, 100, {from: customerAccount});
        assert.fail('should have thrown');
      } catch(error) {
        assert.equal(error.message, "VM Exception while processing transaction: revert")
      }
    });
  });

  describe('#customerWithdraw', () => {
    describe('if you have enough funds', () => {
      it("should decrease the account's balance", async () => {
        await utils.supplyEth(supplierContract, etherToken, 100, customerAccount);

        assert.equal(await utils.ledgerAccountBalance(supplierContract, customerAccount, etherToken.address), 100);

        await supplierContract.customerWithdraw(etherToken.address, 40, customerAccount, {from: customerAccount});
        assert.equal(await utils.ledgerAccountBalance(supplierContract, customerAccount, etherToken.address), 60);

        // verify balances in W-Eth
        assert.equal(await utils.tokenBalance(etherToken, customerAccount), 40);
        assert.equal(await utils.tokenBalance(etherToken, tokenStore.address), 60);
      });

      it("should update the user's balance with interest since the last checkpoint", async () => {
        const supplyAmount = 20000000000000000;
        const withdrawAmount = 10000000000000000;
        const supplyAmountBigNumber = new BigNumber(supplyAmount);
        const withdrawalAmountBigNumber = new BigNumber(withdrawAmount);
        const startingBlockNumber = web3.eth.blockNumber;

        await utils.supplyEth(supplierContract, etherToken, supplyAmount, customerAccount);

        await utils.mineBlocks(web3, 30);

        await supplierContract.customerWithdraw(etherToken.address, withdrawAmount, customerAccount, {from: customerAccount});

        await utils.awaitAssertEventsCollectMissing(assert, supplierContract, [
        // Supply
        {
          event: "LedgerEntry",
          args: {
              ledgerReason: LedgerReason.CustomerSupply,
              ledgerType: LedgerType.Debit,
              ledgerAccount: LedgerAccount.Cash,
              customer: customerAccount,
              asset: etherToken.address,
              amount: supplyAmountBigNumber,
              balance: web3.toBigNumber('0'),
              interestRateBPS: web3.toBigNumber('0'),
              nextPaymentDate: web3.toBigNumber('0')
            }
          },
          {
            event: "LedgerEntry",
            args: {
              ledgerReason: LedgerReason.CustomerSupply,
              ledgerType: LedgerType.Credit,
              ledgerAccount: LedgerAccount.Supply,
              customer: customerAccount,
              asset: etherToken.address,
              amount: supplyAmountBigNumber,
              balance: supplyAmountBigNumber,
              interestRateBPS: web3.toBigNumber('0'),
              nextPaymentDate: web3.toBigNumber('0')
            }
          },
          // There are no borrows, therefore, no interest
          // InterestExpense
          // {
          // event: "LedgerEntry",
          // args: {
          //     ledgerReason: LedgerReason.Interest,
          //     ledgerType: LedgerType.Debit,
          //     ledgerAccount: LedgerAccount.InterestExpense,
          //     customer: customerAccount,
          //     asset: etherToken.address,
          //     amount: web3.toBigNumber('29490101600'),
          //     balance: web3.toBigNumber('0'),
          //     interestRateBPS: web3.toBigNumber('0'),
          //     nextPaymentDate: web3.toBigNumber('0')
          //   }
          // },
          // {
          //   event: "LedgerEntry",
          //   args: {
          //     ledgerReason: LedgerReason.Interest,
          //     ledgerType: LedgerType.Credit,
          //     ledgerAccount: LedgerAccount.Supply,
          //     customer: customerAccount,
          //     asset: etherToken.address,
          //     amount: web3.toBigNumber('29490101600'),
          //     balance: web3.toBigNumber('20000029490101600'),
          //     interestRateBPS: web3.toBigNumber('0'),
          //     nextPaymentDate: web3.toBigNumber('0')
          //   }
          // },
          // Withdrawal
          {
          event: "LedgerEntry",
          args: {
              ledgerReason: LedgerReason.CustomerWithdrawal,
              ledgerType: LedgerType.Debit,
              ledgerAccount: LedgerAccount.Supply,
              customer: customerAccount,
              asset: etherToken.address,
              amount: withdrawalAmountBigNumber,
              balance: withdrawalAmountBigNumber,
              interestRateBPS: web3.toBigNumber('0'),
              nextPaymentDate: web3.toBigNumber('0')
            }
          },
          {
            event: "LedgerEntry",
            args: {
              ledgerReason: LedgerReason.CustomerWithdrawal,
              ledgerType: LedgerType.Credit,
              ledgerAccount: LedgerAccount.Cash,
              customer: customerAccount,
              asset: etherToken.address,
              amount: withdrawalAmountBigNumber,
              balance: web3.toBigNumber('0'),
              interestRateBPS: web3.toBigNumber('0'),
              nextPaymentDate: web3.toBigNumber('0')
            }
          }
        ], {fromBlock: startingBlockNumber, toBlock: 'latest'});
      });

      it("should create debit supplys and credit cash", async () => {
        const initialBalance = 100;
        const initialBalanceBigNumber = web3.toBigNumber(initialBalance);
        const withdrawalAmount = 40;
        const withdrawalAmountBigNumber = web3.toBigNumber(withdrawalAmount);

        await utils.supplyEth(supplierContract, etherToken, initialBalance, customerAccount);

        assert.equal(await utils.ledgerAccountBalance(supplierContract, customerAccount, etherToken.address), initialBalance);

        await supplierContract.customerWithdraw(etherToken.address, withdrawalAmount, customerAccount, {from: customerAccount});

        await utils.awaitAssertEventsCollectMissing(assert, supplierContract, [
        {
          event: "LedgerEntry",
          args: {
              ledgerReason: LedgerReason.CustomerWithdrawal,
              ledgerType: LedgerType.Debit,
              ledgerAccount: LedgerAccount.Supply,
              customer: customerAccount,
              asset: etherToken.address,
              amount: withdrawalAmountBigNumber,
              balance: initialBalanceBigNumber.minus(withdrawalAmountBigNumber),
              interestRateBPS: web3.toBigNumber('0'),
              nextPaymentDate: web3.toBigNumber('0')
            }
          },
          {
            event: "LedgerEntry",
            args: {
              ledgerReason: LedgerReason.CustomerWithdrawal,
              ledgerType: LedgerType.Credit,
              ledgerAccount: LedgerAccount.Cash,
              customer: customerAccount,
              asset: etherToken.address,
              amount: withdrawalAmountBigNumber,
              balance: web3.toBigNumber('0'),
              interestRateBPS: web3.toBigNumber('0'),
              nextPaymentDate: web3.toBigNumber('0')
            }
          }
        ]);
      });
    });

    describe("if you don't have sufficient funds", () => {
      it("generates a graceful error message for InsufficientBalance", async () => {
        await utils.supplyEth(supplierContract, etherToken, 100, customerAccount);

        // Withdrawing 101 is an error
        await utils.awaitGracefulFailureCollectMissing(assert, supplierContract, "Supplier::InsufficientBalance", [null, 101, null, 100], async () => {
          await supplierContract.customerWithdraw(etherToken.address, 101, customerAccount, {from: customerAccount});
        });

        // but withdrawing 100 is okay
        await supplierContract.customerWithdraw(etherToken.address, 100, customerAccount, {from: customerAccount});

        // Withdrawing any more is an error
        await utils.awaitGracefulFailureCollectMissing(assert, supplierContract, "Supplier::InsufficientBalance", [null, 1, null, 0], async () => {
          await supplierContract.customerWithdraw(etherToken.address, 1, customerAccount, {from: customerAccount});
        });
      });
    });
  });

});
