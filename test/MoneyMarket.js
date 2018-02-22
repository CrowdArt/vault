"use strict";

// mnemonics for array indices for web3.eth.accounts used in tests
const system = 0;
const supplier = 3;
const borrower = 1;
const liquidator = 2;

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
const WETH9 = artifacts.require("./tokens/WETH9.sol");
const EIP20 = artifacts.require("./eip20/EIP20.sol");
const Wallet = artifacts.require("./Wallet.sol");
const utils = require('./utils');
const tokenAddrs = utils.tokenAddrs;

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
    faucetToken = await FaucetToken.new("Pig Token", "PIG", 16);
    etherToken = await WETH9.new();

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
    await moneyMarket.setScaledMinimumCollateralRatio(20000);
    await borrowStorage.addBorrowableAsset(etherToken.address);
  });

  describe('#customerBorrow', () => {
    it("pays out the amount requested", async () => {

      // set token value
      await utils.setAssetValue(priceOracle, faucetToken, 10, web3);

      // 100000 wei WETH to supplier so borrower can borrow it
      await utils.supplyEth(moneyMarket, etherToken, 100000, web3.eth.accounts[supplier]);
      // Allocate 1000 pig tokens to borrower and approve 900 tokens to be moved into compound
      await faucetToken.allocateTo(web3.eth.accounts[borrower], 1000, {from: web3.eth.accounts[system]});
      await faucetToken.approve(moneyMarket.address, 900, {from: web3.eth.accounts[borrower]});

      // Supply the tokens which are collateral
      moneyMarket.customerSupply(faucetToken.address, 900, {from: web3.eth.accounts[borrower]});
      // verify balance in ledger
      assert.equal(await utils.ledgerAccountBalance(moneyMarket, web3.eth.accounts[supplier], etherToken.address), 100000);
      assert.equal(await utils.ledgerAccountBalance(moneyMarket, web3.eth.accounts[borrower], faucetToken.address), 900);

      assert.equal(await utils.getAssetValue(priceOracle, faucetToken, 900), 9000);

      // Finally, borrow WETH
      await moneyMarket.customerBorrow(etherToken.address, 20, {from: web3.eth.accounts[borrower]});

      await utils.awaitAssertEventsCollectMissing(assert, moneyMarket, [
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
            balance: web3.toBigNumber('20'),
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
      it("should fail with a GracefulFailure event", async () => {
        await utils.supplyEth(moneyMarket, etherToken, 100, web3.eth.accounts[0]);

        await utils.awaitGracefulFailureCollectMissing(assert, moneyMarket, "Borrower::InvalidCollateralRatio", [null, 201, 201, 50], async () => {
          await moneyMarket.customerBorrow(etherToken.address, 201, {from: web3.eth.accounts[0]});
        });
      });
    });
  });

  describe('#liquidate', () => {
    it('gives collateral to liquidator in exchange for loan asset', async () => {

      /*
        supplier supplies PIG so it's available to be borrowed
        borrower supplies 100_000 eth for collateral and borrows (and withdraws) 200 PIG at 1:1 value with eth
        PIG value skyrockets by 1500x, yielding:
           supply value 100_000 from the eth
           borrow value 300_000
           borrow_times_ratio = 2 * 300_000 = 600_000 supply needed to support a borrow value of 300_000
           collateral_shortfall = 600_000 - 100_000 = 500_000

        liquidator supplies PIG for loan and gets ETH
       */

      // Allocate 1000 pig tokens to supplier and 750 to liquidator
      await faucetToken.allocateTo(web3.eth.accounts[supplier], 1000, {from: web3.eth.accounts[system]});
      await faucetToken.allocateTo(web3.eth.accounts[liquidator], 750, {from: web3.eth.accounts[system]});

      // Approve supplier for 900 tokens and liquidator for 650
      await faucetToken.approve(moneyMarket.address, 900, {from: web3.eth.accounts[supplier]});
      await faucetToken.approve(moneyMarket.address, 650, {from: web3.eth.accounts[liquidator]});

      // Verify initial state
      assert.equal(await utils.tokenBalance(faucetToken, web3.eth.accounts[supplier]), 1000);
      assert.equal(await utils.tokenBalance(faucetToken, web3.eth.accounts[liquidator]), 750);

      // Supply those tokens
      moneyMarket.customerSupply(faucetToken.address, 900, {from: web3.eth.accounts[supplier]});
      moneyMarket.customerSupply(faucetToken.address, 650, {from: web3.eth.accounts[liquidator]});

      // 100000 wei WETH to borrower that they supply as collateral
      await utils.supplyEth(moneyMarket, etherToken, 100000, web3.eth.accounts[borrower]);

      // verify balance in ledger
      assert.equal(await utils.ledgerAccountBalance(moneyMarket, web3.eth.accounts[supplier], faucetToken.address), 900);
      assert.equal(await utils.ledgerAccountBalance(moneyMarket, web3.eth.accounts[liquidator], faucetToken.address), 650);
      assert.equal(await utils.ledgerAccountBalance(moneyMarket, web3.eth.accounts[borrower], etherToken.address), 100000);

      // Make pig token borrowable
      await borrowStorage.addBorrowableAsset(faucetToken.address, {from: web3.eth.accounts[system]});

      // Make pig token cheap so loan is easy to get
      await priceOracle.setAssetValue(faucetToken.address, toAssetValue(1) , {from: web3.eth.accounts[system]});
      await moneyMarket.customerBorrow(faucetToken.address, 200, {from: web3.eth.accounts[borrower]});
      // Withdraw borrowed asset
      await moneyMarket.customerWithdraw(faucetToken.address, 200, web3.eth.accounts[borrower], {from: web3.eth.accounts[borrower]});

      await utils.mineBlocks(web3, 1);
      // Now make pig token 1500x more expensive, so borrow falls under the collateral requirement
      await priceOracle.setAssetValue(faucetToken.address, toAssetValue(1500) , {from: web3.eth.accounts[system]});

      const shortfall = await moneyMarket.collateralShortfall.call(web3.eth.accounts[borrower]);
      assert.equal(shortfall, 500000);

      const result = await moneyMarket.liquidateCollateral.call(web3.eth.accounts[borrower], faucetToken.address, 50, etherToken.address, {from: web3.eth.accounts[liquidator]});

      // (1500 price pig * 50quantity) / ((1 price eth) * (.98 discount multiplier)) = 75,000 / 0.98 = 76,530.6122449 = 76530 wei weth
      const expected_collateral_seized = 76530;
      assert.equal(result, expected_collateral_seized);
      await moneyMarket.liquidateCollateral(web3.eth.accounts[borrower], faucetToken.address, 50, etherToken.address, {from: web3.eth.accounts[liquidator]});

      // liquidator deposited 650 pig tokens and spent 50 wei on liquidation, so should have 600.
      assert.equal(await utils.ledgerAccountBalance(moneyMarket, web3.eth.accounts[liquidator], faucetToken.address), 600);
      assert.equal(await utils.ledgerAccountBalance(moneyMarket, web3.eth.accounts[liquidator], etherToken.address), expected_collateral_seized);
    });
  });

  describe("when the user tries to take a borrow out of an unsupported asset", () => {
    it("fails when insufficient cash", async () => {
      await utils.supplyEth(moneyMarket, etherToken, 100, web3.eth.accounts[0]);

      const testBalanceSheet = await TestBalanceSheet.new();
      await testBalanceSheet.setBalanceSheetBalance(utils.tokenAddrs.OMG, LedgerAccount.Cash, 10);
      await moneyMarket.setBalanceSheet(testBalanceSheet.address);
      await borrowStorage.addBorrowableAsset(utils.tokenAddrs.OMG);

      await utils.awaitGracefulFailureCollectMissing(assert, moneyMarket, "Borrower::InsufficientAssetCash", [], async () => {
        await moneyMarket.customerBorrow(utils.tokenAddrs.OMG, 50, {from: web3.eth.accounts[0]});
      });
    });

    it("fails when not borrowable", async () => {
      await utils.supplyEth(moneyMarket, etherToken, 100, web3.eth.accounts[0]);

      const testBalanceSheet = await TestBalanceSheet.new();
      await testBalanceSheet.setBalanceSheetBalance(utils.tokenAddrs.OMG, LedgerAccount.Cash, 100);
      await moneyMarket.setBalanceSheet(testBalanceSheet.address);

      await utils.awaitGracefulFailureCollectMissing(assert, moneyMarket, "Borrower::AssetNotBorrowable", [], async () => {
        await moneyMarket.customerBorrow(utils.tokenAddrs.OMG, 50, {from: web3.eth.accounts[0]});
      });
    });
  });

  describe('#getMaxBorrowAvailable', () => {
    it('gets the maximum borrow available with a 2:1 (unscaled) ratio', async () => {
      await utils.supplyEth(moneyMarket, etherToken, 100, web3.eth.accounts[1]);
      await moneyMarket.customerBorrow(etherToken.address, 20, {from: web3.eth.accounts[1]});
      await moneyMarket.customerWithdraw(etherToken.address, 20, web3.eth.accounts[1], {from: web3.eth.accounts[1]});

      // (100 - (20*2))/2 = 30
      assert.equal(await utils.toNumber(moneyMarket.getMaxBorrowAvailable.call(web3.eth.accounts[1])), 30);
    });

    it('gets the maximum borrow available with a 3:2 (unscaled) ratio', async () => {
      const accepted = await moneyMarket.setScaledMinimumCollateralRatio(1.5 * 10000);
      assert(accepted, "collateral ratio setup failed");
      await utils.supplyEth(moneyMarket, etherToken, 100, web3.eth.accounts[1]);
      await moneyMarket.customerBorrow(etherToken.address, 20, {from: web3.eth.accounts[1]});
      await moneyMarket.customerWithdraw(etherToken.address, 20, web3.eth.accounts[1], {from: web3.eth.accounts[1]});

      // (100 - (20*1.5))/1.5 = 46.6...
      assert.equal(await utils.toNumber(moneyMarket.getMaxBorrowAvailable.call(web3.eth.accounts[1])), 46);
    });
  });

  // TODO: Make a multi-return version of getValueEquivalent and figure out how to test it.
  // describe('#getValueEquivalent', () => {
  //   it('should get value of assets', async () => {
  //     // supply Ether tokens for acct 1
  //     await borrowStorage.addBorrowableAsset(faucetToken.address);
  //     await faucetToken.allocateTo(web3.eth.accounts[0], 100);
  //
  //     // // Approve wallet for 55 tokens
  //     await faucetToken.approve(moneyMarket.address, 100, {from: web3.eth.accounts[0]});
  //     await moneyMarket.customerSupply(faucetToken.address, 100, {from: web3.eth.accounts[0]});
  //     await utils.supplyEth(moneyMarket, etherToken, 100, web3.eth.accounts[1]);
  //     //
  //     // set PriceOracle value (each Eth is now worth two Eth!)
  //     await utils.setAssetValue(priceOracle, etherToken, 2, web3);
  //     await utils.setAssetValue(priceOracle, faucetToken, 2, web3);
  //     await moneyMarket.customerBorrow(faucetToken.address, 1, {from: web3.eth.accounts[1]});
  //     await moneyMarket.customerWithdraw(faucetToken.address, 1, web3.eth.accounts[1], {from: web3.eth.accounts[1]});
  //
  //     // get value of acct 1
  //     const eqValue = moneyMarket.getValueEquivalent.call(web3.eth.accounts[1]);
  //     await moneyMarket.getValueEquivalent(web3.eth.accounts[1]);
  //
  //     assert.equal(await utils.toNumber(eqValue), 198);
  //   });
  // });

  describe('owned', () => {
    it("sets the owner", async () => {
      const owner = await moneyMarket.getOwner.call();
      assert.equal(owner, web3.eth.accounts[0]);
    });
  });

  describe('#saveBlockInterest', async () => {
    it.only('should snapshot the current balance', async () => {
      const testLedgerStorage = await TestLedgerStorage.new();
      const testBalanceSheet = await TestBalanceSheet.new();

      await moneyMarket.setLedgerStorage(testLedgerStorage.address);
      await moneyMarket.setBalanceSheet(testBalanceSheet.address);

      await testBalanceSheet.setBalanceSheetBalance(faucetToken.address, LedgerAccount.Supply, 50);
      await testBalanceSheet.setBalanceSheetBalance(faucetToken.address, LedgerAccount.Borrow, 150);

      // give supplier some tokens
      console.log("C");
      await faucetToken.allocateTo(web3.eth.accounts[supplier], 500, {from: web3.eth.accounts[system]});
      console.log("D");
      // Approve wallet for 100 tokens and supply them
      await faucetToken.approve(moneyMarket.address, 100, {from: web3.eth.accounts[supplier]});
      console.log("E");
      console.log("faucetToken.address="+faucetToken.address);
      const foo = await faucetToken.foo.call(100);
      assert(!foo, "foo failed");
      console.log("E2 foo succeeded");


      await moneyMarket.customerSupply(faucetToken.address, 100, {from: web3.eth.accounts[supplier]});
      // const supplied = await moneyMarket.customerSupply.call(faucetToken.address, 100, {from: web3.eth.accounts[supplier]});
      // console.log("supplied="+supplied);
      // assert(supplied, "supply failed");
      assert(false, "THIS IS A BACKSTOP to ensure I see events when I modify customerSupply to return early");
      console.log("F");
      const blockNumber = await interestRateStorage.blockInterestBlock(LedgerAccount.Supply, faucetToken.address);
      console.log("G");
      assert.equal(await utils.toNumber(interestRateStorage.blockTotalInterest(LedgerAccount.Supply, faucetToken.address, blockNumber)), 0);
      console.log("H");
      assert.equal(await utils.toNumber(interestRateStorage.blockInterestRate(LedgerAccount.Supply, faucetToken.address, blockNumber)), 14269406392);
    });

    it('should be called once per block unit');
  });

  describe('#getConvertedAssetValueWithDiscount', async () => {

    describe('conversion in terms of a more valuable asset', async () => {
      it("applies discount to target asset price", async () => {
        await priceOracle.setAssetValue(tokenAddrs.BAT, toAssetValue(2) , {from: web3.eth.accounts[0]});
        await priceOracle.setAssetValue(tokenAddrs.OMG, toAssetValue(5) , {from: web3.eth.accounts[0]});
        const discount_bps = 500;
        const balance = await moneyMarket.getConvertedAssetValueWithDiscount.call(tokenAddrs.BAT, (10 ** 18), tokenAddrs.OMG, discount_bps);
        // compare to 400000000000000000 in non-discounted test in priceOracle.js of getConvertedAssetValue
        // we expect to get more of the target asset here because its price has been discounted
        // expected: ( quantity 1 * 10^18)*(2 price BAT)/(5 price OMG *.95 discount multiplier) = 4.21052631578947368... × 10^17
        assert.equal(balance.valueOf(), 421052631578947368);
      });
    });

    describe('conversion in terms of a less valuable asset', async () => {
      it("returns expected amount", async () => {
        // Asset1 = 5 * 10E18 (aka 5 Eth)// Asset2 = 2 * 10E18 (aka 2 Eth)
        await priceOracle.setAssetValue(tokenAddrs.BAT, toAssetValue(5), {from: web3.eth.accounts[0]});
        await priceOracle.setAssetValue(tokenAddrs.OMG, toAssetValue(2), {from: web3.eth.accounts[0]});
        const discount_bps = 500;
        const balance = await moneyMarket.getConvertedAssetValueWithDiscount.call(tokenAddrs.BAT, (10 ** 18), tokenAddrs.OMG, discount_bps);
        // compare to 2500000000000000000 in non-discounted test in priceOracle.js getConvertedAssetValue
        // we expect to get more of the target asset here because its price has been discounted
        // expected: ( quantity 1 * 10^18)*(5 price BAT)/(2 price OMG *.95 discount multiplier) = 2.631578947368421052... × 10^18
        assert.equal(balance.valueOf(), 2631578947368421052);
      });
    });
  });

  // TODO: Make sure we store correct rates for all operations
});
