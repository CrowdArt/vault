require('dotenv').config();
const Web3 = require("web3");
const web3 = new Web3();
const _ = require("lodash");
const WalletProvider = require("truffle-wallet-provider");
const Wallet = require('ethereumjs-wallet');

const networks = ["rinkeby", "kovan", "ropsten", "mainnet"];

const infuraNetworks = _.fromPairs(_.compact(networks.map((network) => {
  var envVarName = `${network.toUpperCase()}_PRIVATE_KEY`
  var privateKeyHex = process.env[envVarName];

  if(privateKeyHex) {
    var privateKey = new Buffer(process.env[envVarName], "hex")
    var wallet = Wallet.fromPrivateKey(privateKey);
    var provider = new WalletProvider(wallet, `https://${network}.infura.io/`);

    return [
      network,
      {
        host: "localhost",
        port: 8545,
        network_id: "*",
        gas: 4600000,
        gasPrice: web3.toWei(13, "gwei"),
        provider,
      }
    ];
  }
})));

var missionProvider;
var missionPrivateKeyHex = process.env["MISSION_PRIVATE_KEY"];

if(missionPrivateKeyHex) {
  var missionPrivateKey = new Buffer(missionPrivateKeyHex, "hex")
  var missionWallet = Wallet.fromPrivateKey(missionPrivateKey);
  missionProvider = new WalletProvider(missionWallet, `https://parity.stage.compound.finance/`);
}

module.exports = {
  networks: {
    development: {
      host: "localhost",
      port: 8545,
      network_id: "*",
      gas: 4600000,
      gasPrice: 20000,
    },
    mission: {
      port: 8545,
      gas: 4612388,
      gasPrice: web3.toWei(15, "gwei"),
      network_id: "235",
      provider: missionProvider,
    },
    ...infuraNetworks,
  },
  solc: {
    optimizer: {
      enabled: true
    }
  }
};
