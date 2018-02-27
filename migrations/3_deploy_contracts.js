const WETH9 = artifacts.require("WETH9.sol");
const MoneyMarket = artifacts.require("MoneyMarket.sol");
const InterestModel = artifacts.require("InterestModel.sol");
const WalletFactory = artifacts.require("WalletFactory.sol");

const BalanceSheet = artifacts.require("BalanceSheet.sol");
const BorrowStorage = artifacts.require("BorrowStorage.sol");
const InterestRateStorage = artifacts.require("InterestRateStorage.sol");
const LedgerStorage = artifacts.require("LedgerStorage.sol");
const PriceOracle = artifacts.require("PriceOracle.sol");
const TokenStore = artifacts.require("TokenStore.sol");

const MINIMUM_COLLATERAL_RATIO = 2 * 10000;

async function deployAll(deployer, network) {
  // First, deploy MoneyMarket, WETH9 and InterstModel
  await deployer.deploy(MoneyMarket);
  await deployer.deploy(WETH9);
  await deployer.deploy(InterestModel);

  // Grab those now-deployed addresses
  const moneyMarket = await MoneyMarket.deployed();
  const etherToken = await WETH9.deployed();
  const interestModel = await InterestModel.deployed();

  // Next, grab the storage contracts which were deployed in a previous migration
  const balanceSheet = await BalanceSheet.deployed();
  const borrowStorage = await BorrowStorage.deployed();
  const interestRateStorage = await InterestRateStorage.deployed();
  const ledgerStorage = await LedgerStorage.deployed();
  const priceOracle = await PriceOracle.deployed();
  const tokenStore = await TokenStore.deployed();

  // Deploy the WalletFactory, which needed the MoneyMarket and WETH9 address
  const walletFactory = await deployer.deploy(WalletFactory, moneyMarket.address, etherToken.address);

  // Finally, we need to set-up our allowences and storage
  // Note: if this is after the initial deploy, we should use `allow.js` for
  //       allowences instead of setting them here.
  await Promise.all([
    moneyMarket.setScaledMinimumCollateralRatio(MINIMUM_COLLATERAL_RATIO),

    moneyMarket.setInterestModel(interestModel.address),

    balanceSheet.allow(moneyMarket.address),
    borrowStorage.allow(moneyMarket.address),
    interestRateStorage.allow(moneyMarket.address),
    ledgerStorage.allow(moneyMarket.address),
    priceOracle.allow(moneyMarket.address),
    tokenStore.allow(moneyMarket.address),

    moneyMarket.setBalanceSheet(balanceSheet.address),
    moneyMarket.setBorrowStorage(borrowStorage.address),
    moneyMarket.setInterestRateStorage(interestRateStorage.address),
    moneyMarket.setLedgerStorage(ledgerStorage.address),
    moneyMarket.setPriceOracle(priceOracle.address),
    moneyMarket.setTokenStore(tokenStore.address)
  ]);

  console.log("Deployed all contracts and storage v3.");
}

module.exports = function(deployer, network) {
  deployer.then(async () => await deployAll(deployer, network));
};
