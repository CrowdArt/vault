"use strict";

const BigNumber = require('bignumber.js');
const MoneyMarket = artifacts.require("./MoneyMarket.sol");
const LedgerStorage = artifacts.require("./storage/LedgerStorage.sol");
const BalanceSheet = artifacts.require("./storage/BalanceSheet.sol");
const TestLedgerStorage = artifacts.require("./test/TestLedgerStorage.sol");
const TestBalanceSheet = artifacts.require("./test/TestBalanceSheet.sol");
const BorrowStorage = artifacts.require("./storage/BorrowStorage.sol");
const InterestRateStorage = artifacts.require("./storage/InterestRateStorage.sol");
const InterestModel = artifacts.require("./InterestModel.sol");
const TokenStore = artifacts.require("./storage/TokenStore.sol");
const PriceOracle = artifacts.require("./storage/PriceOracle.sol");
const FaucetToken = artifacts.require("./token/FaucetToken.sol");
const EtherToken = artifacts.require("./tokens/EtherToken.sol");
const utils = require('./utils');
const moment = require('moment');
const toAssetValue = (value) => (value * 10 ** 9);
const interestRateScale = (10 ** 16); // InterestRateStorage.sol interestRateScale
const blockUnitsPerYear = 210240; // Tied to test set up in which InterestRateStorage.sol blockScale is 10. 2102400 blocks per year / 10 blocks per unit = 210240 units per year

const LedgerType = {
  Debit: web3.toBigNumber(0),
  Credit: web3.toBigNumber(1)
};

const LedgerReason = {
  CustomerSupply: web3.toBigNumber(0),
  CustomerWithdrawal: web3.toBigNumber(1),
  Interest: web3.toBigNumber(2),
  CustomerBorrow: web3.toBigNumber(3),
  CustomerPayBorrow: web3.toBigNumber(4),
  CollateralPayBorrow: web3.toBigNumber(5),
};

const LedgerAccount = {
  Cash: web3.toBigNumber(0),
  Borrow: web3.toBigNumber(1),
  Supply: web3.toBigNumber(2),
  InterestExpense: web3.toBigNumber(3),
  InterestIncome: web3.toBigNumber(4),
  Trading: web3.toBigNumber(5),
};

contract('MoneyMarket', function(accounts) {
  var moneyMarket;
  var etherToken;
  var faucetToken;
  var interestRateStorage;
  var borrowStorage;
  var priceOracle;
  var tokenStore;

  beforeEach(async () => {
    moneyMarket = await MoneyMarket.new();
    faucetToken = await FaucetToken.new();
    etherToken = await EtherToken.new();

    priceOracle = await PriceOracle.new();
    moneyMarket.setPriceOracle(priceOracle.address);

    borrowStorage = await BorrowStorage.new();
    borrowStorage.allow(moneyMarket.address);
    moneyMarket.setBorrowStorage(borrowStorage.address);

    tokenStore = await TokenStore.new();
    tokenStore.allow(moneyMarket.address);
    moneyMarket.setTokenStore(tokenStore.address);

    const ledgerStorage = await LedgerStorage.new();
    ledgerStorage.allow(moneyMarket.address);
    moneyMarket.setLedgerStorage(ledgerStorage.address);

    const interestModel = await InterestModel.new();
    moneyMarket.setInterestModel(interestModel.address);

    interestRateStorage = await InterestRateStorage.new();
    interestRateStorage.allow(moneyMarket.address);
    moneyMarket.setInterestRateStorage(interestRateStorage.address);

    const balanceSheet = await BalanceSheet.new();
    balanceSheet.allow(moneyMarket.address);
    moneyMarket.setBalanceSheet(balanceSheet.address);

    await utils.setAssetValue(priceOracle, etherToken, 1, web3);
    await borrowStorage.setMinimumCollateralRatio(2);
    await borrowStorage.addBorrowableAsset(etherToken.address);
  });

  describe('#customerBorrow', () => {
    it("pays out the amount requested", async () => {
      await utils.supplyEth(moneyMarket, etherToken, 100, web3.eth.accounts[1]);
      await moneyMarket.customerBorrow(etherToken.address, 20, {from: web3.eth.accounts[1]});
      await utils.assertEvents(moneyMarket, [
        {
          event: "LedgerEntry",
          args: {
            ledgerReason: LedgerReason.CustomerBorrow,
            ledgerType: LedgerType.Debit,
            ledgerAccount: LedgerAccount.Borrow,
            customer: web3.eth.accounts[1],
            asset: etherToken.address,
            amount: web3.toBigNumber('20'),
            balance: web3.toBigNumber('20'),
            interestRateBPS: web3.toBigNumber('0'),
            nextPaymentDate: web3.toBigNumber('0')
          }
        },
        {
          event: "LedgerEntry",
          args: {
            ledgerReason: LedgerReason.CustomerBorrow,
            ledgerType: LedgerType.Credit,
            ledgerAccount: LedgerAccount.Supply,
            customer: web3.eth.accounts[1],
            asset: etherToken.address,
            amount: web3.toBigNumber('20'),
            balance: web3.toBigNumber('120'),
            interestRateBPS: web3.toBigNumber('0'),
            nextPaymentDate: web3.toBigNumber('0')
          }
        }
      ]);
    });
  });

  describe('#customerPayBorrow', () => {
    it("accrues interest and reduces the balance", async () => {
      await utils.supplyEth(moneyMarket, etherToken, 1000000000000, web3.eth.accounts[1]);
      await moneyMarket.customerBorrow(etherToken.address, 200000000000, {from: web3.eth.accounts[1]});
      await utils.mineBlocks(web3, 20);
      await moneyMarket.customerPayBorrow(etherToken.address, 180000000000, {from: web3.eth.accounts[1]});
      await utils.assertEvents(moneyMarket, [
        {
          event: "LedgerEntry",
          args: {
            ledgerReason: LedgerReason.Interest,
            ledgerType: LedgerType.Credit,
            ledgerAccount: LedgerAccount.InterestIncome,
            customer: web3.eth.accounts[1],
            asset: etherToken.address,
            amount: web3.toBigNumber('199771'),
            balance: web3.toBigNumber('0'),
            interestRateBPS: web3.toBigNumber('0'),
            nextPaymentDate: web3.toBigNumber('0')
          }
        },
        {
          event: "LedgerEntry",
          args: {
            ledgerReason: LedgerReason.Interest,
            ledgerType: LedgerType.Debit,
            ledgerAccount: LedgerAccount.Borrow,
            customer: web3.eth.accounts[1],
            asset: etherToken.address,
            amount: web3.toBigNumber('199771'),
            balance: web3.toBigNumber('200000199771'),
            interestRateBPS: web3.toBigNumber('0'),
            nextPaymentDate: web3.toBigNumber('0')
          }
        },
        {
          event: "LedgerEntry",
          args: {
            ledgerReason: LedgerReason.CustomerPayBorrow,
            ledgerType: LedgerType.Credit,
            ledgerAccount: LedgerAccount.Borrow,
            customer: web3.eth.accounts[1],
            asset: etherToken.address,
            amount: web3.toBigNumber('180000000000'),
            balance: web3.toBigNumber('20000199771'),
            interestRateBPS: web3.toBigNumber('0'),
            nextPaymentDate: web3.toBigNumber('0')
          }
        },
        {
          event: "LedgerEntry",
          args: {
            ledgerReason: LedgerReason.CustomerPayBorrow,
            ledgerType: LedgerType.Debit,
            ledgerAccount: LedgerAccount.Supply,
            customer: web3.eth.accounts[1],
            asset: etherToken.address,
            amount: web3.toBigNumber('180000000000'),
            balance: web3.toBigNumber('1020000000000'),
            interestRateBPS: web3.toBigNumber('0'),
            nextPaymentDate: web3.toBigNumber('0')
          }
        }
      ]);
    });
  });

  describe('#setMinimumCollateralRatio', () => {
    it('only can be called by the contract owner', async () => {
      await utils.assertOnlyOwner(borrowStorage, borrowStorage.setMinimumCollateralRatio.bind(null, 1), web3);
    });
  });

  describe('#addBorrowableAsset', () => {
    it('only can be called by the contract owner', async () => {
      await utils.assertOnlyOwner(borrowStorage, borrowStorage.addBorrowableAsset.bind(null, 1), web3);
    });
  });

  describe('#customerBorrow', () => {
    describe('when the borrow is valid', () => {
      it("pays out the amount requested", async () => {
        await utils.supplyEth(moneyMarket, etherToken, 100, web3.eth.accounts[1]);
        await moneyMarket.customerBorrow(etherToken.address, 20, {from: web3.eth.accounts[1]});
        await moneyMarket.customerWithdraw(etherToken.address, 20, web3.eth.accounts[1], {from: web3.eth.accounts[1]});

        // verify balances in W-Eth
        assert.equal(await utils.tokenBalance(etherToken, tokenStore.address), 80);
        assert.equal(await utils.tokenBalance(etherToken, web3.eth.accounts[1]), 20);
      });
    });

    describe("when the user doesn't have enough collateral supplied", () => {
      it("fails", async () => {
        await utils.supplyEth(moneyMarket, etherToken, 100, web3.eth.accounts[0]);

        await utils.assertGracefulFailure(moneyMarket, "Borrower::InvalidCollateralRatio", [null, 201, 201, 100], async () => {
          await moneyMarket.customerBorrow(etherToken.address, 201, {from: web3.eth.accounts[0]});
        });
      });
    });
  });

  describe("when the user tries to take a borrow out of an unsupported asset", () => {
    it("fails when insufficient cash", async () => {
      await utils.supplyEth(moneyMarket, etherToken, 100, web3.eth.accounts[0]);

      const testBalanceSheet = await TestBalanceSheet.new();
      await testBalanceSheet.setBalanceSheetBalance(utils.tokenAddrs.OMG, LedgerAccount.Cash, 10);
      await moneyMarket.setBalanceSheet(testBalanceSheet.address);
      await borrowStorage.addBorrowableAsset(utils.tokenAddrs.OMG);

      await utils.assertGracefulFailure(moneyMarket, "Borrower::InsufficientAssetCash", [], async () => {
        await moneyMarket.customerBorrow(utils.tokenAddrs.OMG, 50, {from: web3.eth.accounts[0]});
      });
    });

    it("fails when not borrowable", async () => {
      await utils.supplyEth(moneyMarket, etherToken, 100, web3.eth.accounts[0]);

      const testBalanceSheet = await TestBalanceSheet.new();
      await testBalanceSheet.setBalanceSheetBalance(utils.tokenAddrs.OMG, LedgerAccount.Cash, 100);
      await moneyMarket.setBalanceSheet(testBalanceSheet.address);

      await utils.assertGracefulFailure(moneyMarket, "Borrower::AssetNotBorrowable", [], async () => {
        await moneyMarket.customerBorrow(utils.tokenAddrs.OMG, 50, {from: web3.eth.accounts[0]});
      });
    });
  });

  describe('#getMaxBorrowAvailable', () => {
    it('gets the maximum borrow available', async () => {
      await utils.supplyEth(moneyMarket, etherToken, 100, web3.eth.accounts[1]);
      await moneyMarket.customerBorrow(etherToken.address, 20, {from: web3.eth.accounts[1]});
      await moneyMarket.customerWithdraw(etherToken.address, 20, web3.eth.accounts[1], {from: web3.eth.accounts[1]});

      assert.equal(await utils.toNumber(moneyMarket.getMaxBorrowAvailable.call(web3.eth.accounts[1])), 160);
    });
  });

  describe('#getValueEquivalent', () => {
    it('should get value of assets', async () => {
      // supply Ether tokens for acct 1
      await borrowStorage.addBorrowableAsset(faucetToken.address);
      await faucetToken.allocateTo(web3.eth.accounts[0], 100);

      // // Approve wallet for 55 tokens
      await faucetToken.approve(moneyMarket.address, 100, {from: web3.eth.accounts[0]});
      await moneyMarket.customerSupply(faucetToken.address, 100, {from: web3.eth.accounts[0]});
      await utils.supplyEth(moneyMarket, etherToken, 100, web3.eth.accounts[1]);
      //
      // set PriceOracle value (each Eth is now worth two Eth!)
      await utils.setAssetValue(priceOracle, etherToken, 2, web3);
      await utils.setAssetValue(priceOracle, faucetToken, 2, web3);
      await moneyMarket.customerBorrow(faucetToken.address, 1, {from: web3.eth.accounts[1]});
      await moneyMarket.customerWithdraw(faucetToken.address, 1, web3.eth.accounts[1], {from: web3.eth.accounts[1]});

      // get value of acct 1
      const eqValue = moneyMarket.getValueEquivalent.call(web3.eth.accounts[1]);
      await moneyMarket.getValueEquivalent(web3.eth.accounts[1]);

      assert.equal(await utils.toNumber(eqValue), 198);
    });
  });

  describe('owned', () => {
    it("sets the owner", async () => {
      const owner = await moneyMarket.getOwner.call();
      assert.equal(owner, web3.eth.accounts[0]);
    });
  });
  
  describe('#saveBlockInterest', async () => {
    it('should snapshot the current balance', async () => {
      const testLedgerStorage = await TestLedgerStorage.new();
      const testBalanceSheet = await TestBalanceSheet.new();

      await moneyMarket.setLedgerStorage(testLedgerStorage.address);
      await moneyMarket.setBalanceSheet(testBalanceSheet.address);

      await testBalanceSheet.setBalanceSheetBalance(faucetToken.address, LedgerAccount.Supply, 50);
      await testBalanceSheet.setBalanceSheetBalance(faucetToken.address, LedgerAccount.Borrow, 150);

      // Approve wallet for 55 tokens and supply them
      await faucetToken.approve(moneyMarket.address, 100, {from: web3.eth.accounts[0]});
      await moneyMarket.customerSupply(faucetToken.address, 100, {from: web3.eth.accounts[0]});

      const blockNumber = await interestRateStorage.blockInterestBlock(LedgerAccount.Supply, faucetToken.address);

      assert.equal(await utils.toNumber(interestRateStorage.blockTotalInterest(LedgerAccount.Supply, faucetToken.address, blockNumber)), 0);
      assert.equal(await utils.toNumber(interestRateStorage.blockInterestRate(LedgerAccount.Supply, faucetToken.address, blockNumber)), 14269406392);
    });

    it('should be called once per block unit');
  });

  // TODO: Make sure we store correct rates for all operations
});
