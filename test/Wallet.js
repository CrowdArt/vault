"use strict";

const BorrowStorage = artifacts.require("./storage/BorrowStorage.sol");
const EtherToken = artifacts.require("./tokens/EtherToken.sol");
const FaucetToken = artifacts.require("./token/FaucetToken.sol");
const MoneyMarket = artifacts.require("./MoneyMarket.sol");
const PriceOracle = artifacts.require("./storage/PriceOracle.sol");
const TokenStore = artifacts.require("./storage/TokenStore.sol");
const Wallet = artifacts.require("./Wallet.sol");

const utils = require('./utils');

async function supplyEth(wallet, amount, account) {
  await wallet.sendTransaction({value: amount, from: account});
}

async function withdrawEth(wallet, amount, account, to) {
  await wallet.withdrawEth(amount, to, {from: account});
}

async function supplyAsset(wallet, token, amount, account) {
  // Approve wallet for amount tokens
  await token.approve(wallet.address, amount, {from: account});

  // Supply those tokens
  await wallet.supplyAsset(token.address, amount, {from: account});
}

async function withdrawAsset(wallet, token, amount, account, to) {
  await wallet.withdrawAsset(token.address, amount, to, {from: account});
}

async function borrowAsset(wallet, token, amount, to, account) {
  await wallet.borrowAsset(token, amount, to, {from: account});
}

async function borrowEth(wallet, amount, to, account) {
  await wallet.borrowEth(amount, to, {from: account});
}

contract('Wallet', function(accounts) {
  var wallet;
  var moneyMarket;
  var etherToken;
  var faucetToken;
  var borrowStorage;
  var priceOracle;
  var tokenStore;
  var snapshot;

  before(async () => {
    borrowStorage = await BorrowStorage.deployed();
    priceOracle = await PriceOracle.deployed();
    tokenStore = await TokenStore.deployed();
    moneyMarket = await MoneyMarket.deployed();
    etherToken = await EtherToken.deployed();

    snapshot = await utils.takeSnapshot(web3);
  });

  after(async () => {
    await utils.restoreSnapshot(web3, snapshot);
  });

  beforeEach(async () => {
    tokenStore = await TokenStore.new();
    [etherToken, faucetToken] = await Promise.all([EtherToken.new(), FaucetToken.new()]);

    await moneyMarket.setTokenStore(tokenStore.address);
    await tokenStore.allow(moneyMarket.address);

    wallet = await Wallet.new(web3.eth.accounts[1], moneyMarket.address, etherToken.address);
  });

  describe('#supplyEth / fallback', () => {
    it('#fallback should supply assets in moneyMarket', async () => {
      await wallet.sendTransaction({value: 55});

      // verify balance in ledger
      assert.equal(await utils.ledgerAccountBalance(moneyMarket, wallet.address, etherToken.address), 55);

      // verify balances in W-Eth
      assert.equal(await utils.tokenBalance(etherToken, tokenStore.address), 55);
      assert.equal(await utils.tokenBalance(etherToken, web3.eth.accounts[1]), 0);
    });

    it('#supplyEth should supply assets in moneyMarket', async () => {
      await wallet.supplyEth({value: 55});

      // verify balance in ledger
      assert.equal(await utils.ledgerAccountBalance(moneyMarket, wallet.address, etherToken.address), 55);

      // verify balances in W-Eth
      assert.equal(await utils.tokenBalance(etherToken, tokenStore.address), 55);
      assert.equal(await utils.tokenBalance(etherToken, web3.eth.accounts[1]), 0);
    });
  });

  describe('#supplyAsset', () => {
    it('should supply assets in moneyMarket', async () => {
      // Allocate 100 pig tokens to account 1
      await faucetToken.allocateTo(web3.eth.accounts[1], 100);

      // Approve wallet for 55 tokens
      await faucetToken.approve(wallet.address, 55, {from: web3.eth.accounts[1]});

      // Verify initial state
      assert.equal(await utils.tokenBalance(faucetToken, tokenStore.address), 0);
      assert.equal(await utils.tokenBalance(faucetToken, web3.eth.accounts[1]), 100);

      // Supply those tokens
      await wallet.supplyAsset(faucetToken.address, 55, {from: web3.eth.accounts[1]});

      // verify balance in ledger
      assert.equal(await utils.ledgerAccountBalance(moneyMarket, wallet.address, faucetToken.address), 55);

      // verify balances in FaucetToken
      assert.equal(await utils.tokenBalance(faucetToken, tokenStore.address), 55);
      assert.equal(await utils.tokenBalance(faucetToken, web3.eth.accounts[1]), 45);
    });

    it('should leave a Supply event');
    it('should accept supplys from third party');
  });

  describe('#supplyDirect', () => {
    it('should supply assets owned by wallet into moneyMarket', async () => {
      // Allocate 100 pig tokens to account 1
      await faucetToken.allocateTo(web3.eth.accounts[1], 100);

      // Transfer wallet for 55 tokens
      await faucetToken.transfer(wallet.address, 55, {from: web3.eth.accounts[1]});

      // Verify initial state
      assert.equal(await utils.tokenBalance(faucetToken, tokenStore.address), 0);
      assert.equal(await utils.tokenBalance(faucetToken, web3.eth.accounts[1]), 45);
      assert.equal(await utils.tokenBalance(faucetToken, wallet.address), 55);

      // Supply those tokens (any account can call)
      await wallet.supplyDirect(faucetToken.address, 55, {from: web3.eth.accounts[2]});

      // verify balance in ledger
      assert.equal(await utils.ledgerAccountBalance(moneyMarket, wallet.address, faucetToken.address), 55);

      // verify balances in FaucetToken
      assert.equal(await utils.tokenBalance(faucetToken, tokenStore.address), 55);
      assert.equal(await utils.tokenBalance(faucetToken, web3.eth.accounts[1]), 45);
    });

    it('should leave a Supply event');
    it('should accept supplys from third party');
  });

  describe('#withdrawEth', () => {
    it('should withdraw assets from moneyMarket', async () => {
      const randomAddress = '0xa4715d7950e39e2ac90ca3300855bc358253685e';

      // fill initial balance
      await wallet.sendTransaction({value: 55});

      // verify balance in ledger
      assert.equal(await utils.ledgerAccountBalance(moneyMarket, wallet.address, etherToken.address), 55);

      await utils.assertDifference(assert, 22, async () => {
        // get eth balance
        return await utils.ethBalance(randomAddress);
      }, async () => {
        // withdraw eth
        return await wallet.withdrawEth(22, randomAddress, {from: web3.eth.accounts[1]});
      });

      // verify balance in ledger
      assert.equal(await utils.ledgerAccountBalance(moneyMarket, wallet.address, etherToken.address), 33);

      // verify balances in W-Eth
      assert.equal(await utils.tokenBalance(etherToken, tokenStore.address), 33);
      assert.equal(await utils.tokenBalance(etherToken, web3.eth.accounts[1]), 0);
    });

    it('should log Withdrawal event');
    it('should fail on third party calls');
  });

  describe('#withdrawAsset', () => {
    it('should withdraw assets from moneyMarket', async () => {
      // Allocate 100 pig tokens to account 1
      await faucetToken.allocateTo(web3.eth.accounts[1], 100);

      // Approve wallet for 55 tokens
      await faucetToken.approve(wallet.address, 55, {from: web3.eth.accounts[1]});

      // Supply those tokens
      await wallet.supplyAsset(faucetToken.address, 55, {from: web3.eth.accounts[1]});

      // Withdraw to different address
      await wallet.withdrawAsset(faucetToken.address, 33, web3.eth.accounts[2], {from: web3.eth.accounts[1]});

      // verify balances in FaucetToken
      assert.equal(await utils.tokenBalance(faucetToken, tokenStore.address), 22);
      assert.equal(await utils.tokenBalance(faucetToken, web3.eth.accounts[1]), 45);
      assert.equal(await utils.tokenBalance(faucetToken, web3.eth.accounts[2]), 33);
    });

    it('should log Withdrawal event');
    it('should fail on third party calls');
  });

  describe('#borrowAsset', () => {
    it('should borrow assets from moneyMarket', async () => {
      // fill initial balance
      await wallet.sendTransaction({value: web3.toWei(55, "kwei")});

      // give the moneyMarket tokens to lend
      // Approve wallet for 55 tokens
      await faucetToken.allocateTo(web3.eth.accounts[1], web3.toWei(55, "kwei"));

      // Approve wallet for 55 tokens
      await faucetToken.approve(wallet.address, web3.toWei(55, "kwei"), {from: web3.eth.accounts[1]});

      // Supply those tokens
      await wallet.supplyAsset(faucetToken.address, web3.toWei(55, "kwei"), {from: web3.eth.accounts[1]});
      await utils.addBorrowableAsset(borrowStorage, faucetToken, web3);
      await utils.setAssetValue(priceOracle, etherToken, 1, web3);
      await utils.setAssetValue(priceOracle, faucetToken, 1, web3);

      // verify balance in ledger
      assert.equal(await utils.ledgerAccountBalance(moneyMarket, wallet.address, etherToken.address), 55000);
      assert.equal(await utils.ledgerAccountBalance(moneyMarket, wallet.address, faucetToken.address), 55000);

      assert.equal(await utils.toNumber(moneyMarket.getValueEquivalent.call(wallet.address)), web3.toWei(110, "kwei"));

      await wallet.borrowAsset(faucetToken.address, web3.toWei(22, "kwei"), web3.eth.accounts[2], {from: web3.eth.accounts[1]});

      await utils.mineBlocks(web3, 20);

      // verify balance in ledger (still has eth, facuet token was withdrawn)
      assert.equal(await utils.ledgerAccountBalance(moneyMarket, wallet.address, etherToken.address), 55000);
      assert.equal(await utils.ledgerAccountBalance(moneyMarket, wallet.address, faucetToken.address), 55000);

      // verify balances in W-Eth
      assert.equal(await utils.tokenBalance(etherToken, tokenStore.address), web3.toWei(55, "kwei"));
      assert.equal(await utils.tokenBalance(etherToken, web3.eth.accounts[1]), 0);

      // verify balances in FaucetToken
      assert.equal(await utils.tokenBalance(faucetToken, tokenStore.address), web3.toWei(33, "kwei"));
      assert.equal(await utils.tokenBalance(faucetToken, web3.eth.accounts[1]), web3.toWei(0, "kwei"));
    });

    it('should not let you borrow too much', async () => {
      // fill initial balance
      await wallet.sendTransaction({value: web3.toWei(55, "kwei")});

      // give the moneyMarket tokens to lend
      // TODO: Test for `Supplier::TokenTransferToFail` if moneyMarket lacks funding
      await faucetToken.allocateTo(tokenStore.address, web3.toWei(100, "kwei"));

      // set priceOracle value of pig token to 2 wei, which means we can borrow 55
      await utils.setAssetValue(priceOracle, etherToken, 1, web3);
      await utils.setAssetValue(priceOracle, faucetToken, 2, web3);
      await utils.addBorrowableAsset(borrowStorage, faucetToken, web3);

      // verify balance in ledger
      assert.equal(await utils.ledgerAccountBalance(moneyMarket, wallet.address, etherToken.address), 55000);

      // TODO: This should fail at 27.5, not 110. Check we're calculating ratios correctly.
      await utils.assertGracefulFailure(moneyMarket, "Borrower::InvalidCollateralRatio", [null, web3.toWei(111, "kwei"), web3.toWei(222, "kwei"), web3.toWei(55, "kwei")], async () => {
        await wallet.borrowAsset(faucetToken.address, web3.toWei(111, "kwei"), web3.eth.accounts[2], {from: web3.eth.accounts[1]});
      });

      await utils.mineBlocks(web3, 20);

      // verify balance in ledger (still has eth, pig token was withdrawn)
      assert.equal(await utils.ledgerAccountBalance(moneyMarket, wallet.address, etherToken.address), 55000);
      assert.equal(await utils.ledgerAccountBalance(moneyMarket, wallet.address, faucetToken.address), 0);

      // verify balances in W-Eth
      assert.equal(await utils.tokenBalance(etherToken, tokenStore.address), web3.toWei(55, "kwei"));
      assert.equal(await utils.tokenBalance(etherToken, web3.eth.accounts[1]), 0);

      // verify balances in FaucetToken
      assert.equal(await utils.tokenBalance(faucetToken, tokenStore.address), web3.toWei(100, "kwei"));
      assert.equal(await utils.tokenBalance(faucetToken, web3.eth.accounts[1]), 0);
    });

    it('should log Withdrawal event');
    it('should fail on third party calls');
  });

  describe('#borrowEth', () => {
    it('should borrow assets from moneyMarket', async () => {
      await borrowStorage.addBorrowableAsset(etherToken.address);
      await borrowStorage.addBorrowableAsset(faucetToken.address);
      await utils.setAssetValue(priceOracle, faucetToken, 1, web3);
      // Allocate 100 pig tokens to account 1
      await supplyEth(wallet, 33, web3.eth.accounts[1]);
      await faucetToken.allocateTo(web3.eth.accounts[1], 100);

      // Approve wallet for 55 tokens
      await faucetToken.approve(wallet.address, 55, {from: web3.eth.accounts[1]});

      // Supply those tokens
      await wallet.supplyAsset(faucetToken.address, 55, {from: web3.eth.accounts[1]});

      // Borrow eth to different address
      await wallet.borrowEth(33, web3.eth.accounts[2], {from: web3.eth.accounts[1]});

      // verify balances in FaucetToken
      assert.equal(await utils.tokenBalance(faucetToken, tokenStore.address), 55);
      assert.equal(await utils.tokenBalance(faucetToken, web3.eth.accounts[1]), 45);
    });

    it('should log Withdrawal event');
    it('should fail on third party calls');
  });

  describe('#balanceEth', () => {
    it('should have correct balance', async () => {
      await supplyEth(wallet, 22, web3.eth.accounts[1]);

      assert.equal(await utils.toNumber(wallet.balanceEth.call()), 22);

      await supplyEth(wallet, 11, web3.eth.accounts[1]);

      assert.equal(await utils.toNumber(wallet.balanceEth.call()), 33);

      await withdrawEth(wallet, 3, web3.eth.accounts[1], web3.eth.accounts[2]);

      assert.equal(await utils.toNumber(wallet.balanceEth.call()), 30);
    });

    it('should allow third party calls');
  });

  describe('#balance', () => {
    it('should have correct asset balance', async () => {
      // Allocate 100 pig tokens to account 1
      await faucetToken.allocateTo(web3.eth.accounts[1], 100);

      await supplyAsset(wallet, faucetToken, 22, web3.eth.accounts[1]);

      assert.equal(await utils.toNumber(wallet.balance.call(faucetToken.address)), 22);

      await supplyAsset(wallet, faucetToken, 11, web3.eth.accounts[1]);

      await utils.mineBlocks(web3, 20);

      assert.equal(await utils.toNumber(wallet.balance.call(faucetToken.address)), 33);

      await withdrawAsset(wallet, faucetToken, 3, web3.eth.accounts[1], web3.eth.accounts[2]);

      assert.equal(await utils.toNumber(wallet.balance.call(faucetToken.address)), 30);
    });

    it('should allow third party calls');
  });
});
