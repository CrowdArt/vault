"use strict";

const WETH9 = artifacts.require("./tokens/WETH9.sol");
const MoneyMarket = artifacts.require("./MoneyMarket.sol");
const TokenStore = artifacts.require("./storage/TokenStore.sol");
const Wallet = artifacts.require("./Wallet.sol");
const WalletFactory = artifacts.require("./WalletFactory.sol");

const utils = require('./utils');

contract('WalletFactory', function(accounts) {
  var walletFactory;
  var moneyMarket;
  var etherToken;
  var tokenStore;

  before(async () => {
    moneyMarket = await MoneyMarket.deployed();
    etherToken = await WETH9.deployed();
    tokenStore = await TokenStore.deployed();

    walletFactory = await WalletFactory.new(moneyMarket.address, etherToken.address);
  });

  describe("#newWallet", () => {
    it("should create a new wallet", async () => {
      // Find out where wallet will be created
      const walletAddress = await walletFactory.newWallet.call(web3.eth.accounts[1]);

      // Actually create the wallet
      await walletFactory.newWallet(web3.eth.accounts[1]);

      // Make a Wallet variable pointed at the address from above
      const wallet = Wallet.at(walletAddress);

      // Supply eth into wallet
      await wallet.supplyEth({from: web3.eth.accounts[1], value: 55});

      // Verify balance
      assert.equal(await utils.toNumber(wallet.balanceEth.call()), 55);

      // Withdraw eth
      await wallet.withdrawEth(22, web3.eth.accounts[1], {from: web3.eth.accounts[1]});

      // Verify balance
      assert.equal(await utils.toNumber(wallet.balanceEth.call()), 33);
    });

    it.skip("should only work if by wallet factory owner", async () => {
      await utils.assertOnlyOwner(wallet, wallet.newWallet.bind(null, web3.eth.accounts[1]), web3);
    });

    it("should be owned by set owner", async () => {
      // Find out where wallet will be created
      const walletAddress = await walletFactory.newWallet.call(web3.eth.accounts[1], {from: web3.eth.accounts[0]});

      // Actually create the wallet
      await walletFactory.newWallet(web3.eth.accounts[1], {from: web3.eth.accounts[0]});

      // Make a Wallet variable pointed at the address from above
      const wallet = Wallet.at(walletAddress);

      // Supply eth into wallet
      await wallet.supplyEth({from: web3.eth.accounts[1], value: 55});

      await utils.assertOnlyOwner(wallet, wallet.withdrawEth.bind(null, 22, web3.eth.accounts[1]), web3.eth.accounts[1], web3.eth.accounts[2]);
    });

    it("should emit new wallet event", async () => {
      // Find out where wallet will be created
      const walletAddress = (await walletFactory.newWallet.call(web3.eth.accounts[1], {from: web3.eth.accounts[0]})).valueOf();

      // Actually create the wallet
      await walletFactory.newWallet(web3.eth.accounts[1], {from: web3.eth.accounts[0]});

      await utils.assertEvents(walletFactory, [
      {
        event: "NewWallet",
        args: {
          walletOwner: web3.eth.accounts[1],
          newWalletAddress: walletAddress
        }
      }]);
    });
  });
});
