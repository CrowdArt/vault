const FaucetTokenBAT = artifacts.require("FaucetTokenBAT.sol");
const FaucetTokenDRGN = artifacts.require("FaucetTokenDRGN.sol");
const FaucetTokenOMG = artifacts.require("FaucetTokenOMG.sol");
const FaucetTokenZRX = artifacts.require("FaucetTokenZRX.sol");

// BAT (decimals 10) 2500, DRGN (decimals 10) 500, OMG (decimals 18) 75, ZRX (decimals 18) 500
const tokens = [
  [ FaucetTokenBAT, 2500e18 ],
  [ FaucetTokenDRGN, 500e10 ],
  [ FaucetTokenOMG, 75e18 ],
  [ FaucetTokenZRX, 500e18 ],
];

async function deployToken(deployer, token, value) {
  // deploy the token
  await deployer.deploy(token);

  // get the deployed token
  const contract = await token.deployed();

  // set token allocation amount
  return await contract.setPerRequestTokenAmount(value);
}

async function deployAll(deployer, network) {
  const tokenPromises = tokens.map(([token, value]) => {
    return deployToken(deployer, token, value);
  });

  await Promise.all(tokenPromises);

  console.log("Deployed all tokens v4.");
}

module.exports = function(deployer, network) {
  // If we're on a test-net, let's deploy all of our faucet tokens
  if (network == "development" || network == "mission" || network == "rinkeby") {
    deployer.then(async () => await deployAll(deployer, network));
  } else {
    console.log("Not deploying faucet tokens v4...");
  }
};
