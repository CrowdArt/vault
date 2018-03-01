const MoneyMarket = artifacts.require("./MoneyMarket.sol");
const WETH9 = artifacts.require("./tokens/WETH9.sol");
const WalletFactory = artifacts.require("./WalletFactory.sol");

const FaucetTokenBAT = artifacts.require("FaucetTokenBAT.sol");
const FaucetTokenDRGN = artifacts.require("FaucetTokenDRGN.sol");
const FaucetTokenOMG = artifacts.require("FaucetTokenOMG.sol");
const FaucetTokenZRX = artifacts.require("FaucetTokenZRX.sol");

const BalanceSheet = artifacts.require("./storage/BalanceSheet.sol");
const BorrowStorage = artifacts.require("./storage/BorrowStorage.sol");
const InterestModel = artifacts.require("./InterestModel.sol");
const InterestRateStorage = artifacts.require("./storage/InterestRateStorage.sol");
const LedgerStorage = artifacts.require("./storage/LedgerStorage.sol");
const PriceOracle = artifacts.require("./storage/PriceOracle.sol");
const TokenStore = artifacts.require("./storage/TokenStore.sol");

const knownTokens = [
  [ "bat", FaucetTokenBAT ],
  [ "drgn", FaucetTokenDRGN ],
  [ "omg", FaucetTokenOMG ],
  [ "zrx", FaucetTokenZRX ],
];

module.exports = async function(callback) {
  const balanceSheet = await BalanceSheet.deployed()
  const borrowStorage = await BorrowStorage.deployed()
  const etherToken = await WETH9.deployed();
  const interestModel = await InterestModel.deployed();
  const interestRateStorage = await InterestRateStorage.deployed();
  const ledgerStorage = await LedgerStorage.deployed();
  const moneyMarket = await MoneyMarket.deployed();
  const priceOracle = await PriceOracle.deployed();
  const tokenStore = await TokenStore.deployed();
  const walletFactory = await WalletFactory.deployed();

  const tokens = {
    [etherToken.address]: "eth"
  };


  await Promise.all(knownTokens.map(async ([symbol, contract]) => {
    try {
      const deployedContract = await contract.deployed();
      tokens[deployedContract.address] = symbol;
    } catch (e) {
      console.log(`Faucet token ${symbol} not deployed`);
    }
  }));

  process.stderr.write(JSON.stringify(
    {
      "balance_sheet": balanceSheet.address,
      "borrow_storage": borrowStorage.address,
      "ether_token": etherToken.address,
      "interest_model": interestModel.address,
      "interest_rate_storage": interestRateStorage.address,
      "ledger_storage": ledgerStorage.address,
      "money_market": moneyMarket.address,
      "price_oracle": priceOracle.address,
      "token_store": tokenStore.address,
      "tokens": tokens,
      "wallet_factory": walletFactory.address,
    }
  ));

  callback();
}
