"use strict";

const LedgerStorage = artifacts.require("./storage/LedgerStorage.sol");
const BalanceSheet = artifacts.require("./storage/BalanceSheet.sol");
const BorrowStorage = artifacts.require("./storage/BorrowStorage.sol");
const InterestRateStorage = artifacts.require("./storage/InterestRateStorage.sol");
const InterestModel = artifacts.require("./InterestModel.sol");
const TokenStore = artifacts.require("./storage/TokenStore.sol");
const PriceOracle = artifacts.require("./storage/PriceOracle.sol");

var _ = require("lodash");
var Promise = require("bluebird");
var BigNumber = require('bignumber.js');
var one = new BigNumber(1);
const toAssetValue = (value) => (value * 10 ** 9);
const interestRateScale = 10 ** 17;
const blocksPerYear = 2102400;
const annualBPSToScaledPerBlockRate = (value) => Math.trunc((value * interestRateScale) / (10000 * blocksPerYear));
const annualBPSToScaledPerBlockRateNonTrunc = (value) => (value * interestRateScale) / (10000 * blocksPerYear);
// to scale 5%: scaleInterest(0.05)
const scaleInterest = (interest) => Math.trunc(interest * Math.pow(10, 17));

const storageTypes = [
  ['priceOracle', 'setPriceOracle', PriceOracle],
  ['borrowStorage', 'setBorrowStorage', BorrowStorage],
  ['tokenStore', 'setTokenStore', TokenStore],
  ['ledgerStorage', 'setLedgerStorage', LedgerStorage],
  ['interestModel', 'setInterestModel', InterestModel],
  ['interestRateStorage', 'setInterestRateStorage', InterestRateStorage],
  ['balanceSheet', 'setBalanceSheet', BalanceSheet]
];

function validateRate(assert, annualBPS, actual, expected, msg) {
  validateRateWithMaxRatio(assert, annualBPS, actual, expected, 0.0000002, msg)
}

function validateRateWithMaxRatio(assert, annualBPS, actual, expected, maxRatio, msg, debug=true) {
  const blockRateDerivedFromAnnualBPS = annualBPSToScaledPerBlockRateNonTrunc(annualBPS);

  const delta = expected - blockRateDerivedFromAnnualBPS;

  // errorRatio: How does our blockchain computed per block rate compare to the annual bps
  // that has been converted to a per block rate?
  var errorRatio = 0;

  if (blockRateDerivedFromAnnualBPS != 0) {
    errorRatio = Math.abs(delta) / blockRateDerivedFromAnnualBPS;
  }

  if (errorRatio >= maxRatio || debug) {
    console.log(`${msg}, annualBPS=${annualBPS}, expected=${expected}, actual=${actual}, errorRatio=${errorRatio}, blockRateDerivedFromAnnualBPS=${blockRateDerivedFromAnnualBPS}`);
  }

  assert.isBelow(errorRatio, maxRatio, "bad error ratio");
  assert.equal(actual, expected, msg);
}

async function createAndApproveWeth(ledger, etherToken, amount, account, approvalAmount) {
  await etherToken.deposit({from: account, value: amount});
  await etherToken.approve(ledger.address, approvalAmount || amount, {from: account});
};

async function assertFailure(msg, execFn) {
  try {
    await execFn();
    assert.fail('should have thrown');
  } catch (error) {
    await assert.equal(error.message, msg);
  }
}

async function assertGracefulFailure(contract, failure, failureParamsOrExecFn, maybeExecFn) {
  var failureParams;
  var execFn;

  // Allow failureParams to be optional.
  if (maybeExecFn) {
    execFn = maybeExecFn;
    failureParams = failureParamsOrExecFn;
  } else {
    failureParams = null;
    execFn = failureParamsOrExecFn;
  }

  await execFn();

  return new Promise((resolve, reject) => {
    var event = contract.allEvents();
    event.get((error, events) => {
      var found = false;

      for (event of events) {
        if (event.event === 'GracefulFailure') {
          if (event.args.errorMessage === failure) {
            if (failureParams) {
              for (var i = 0; i < failureParams.length; i++) {
                var expected = failureParams[i];
                var actual = event.args.values[i];

                if (failureParams[i] && expected != actual) {
                  throw new Error(`GracefulFailure parameter mismatch #${i+1}, "${expected}" expected, got "${actual}"`);
                }
              }
            }

            found = true;
            resolve(event);
          } else {
            throw new Error(`GracefulFailure "${failure}" expected, got "${event.args.errorMessage}"`);
          }
        }
      }

      if (!found) {
        throw new Error(`GracefulFailure "${failure}" not detected`);
      }
    });

    event.stopWatching();
  });
}

async function increaseTime(web3, seconds) {
  return new Promise((resolve, reject) => {
    web3.currentProvider.sendAsync({
      jsonrpc: "2.0",
      method: "evm_increaseTime",
      params: [seconds], // 86400 is num seconds in day
      id: new Date().getTime()
    }, (err, result) => {
      if(err){ return reject(err) }
      return resolve(result)
    });
  });
}

async function mineBlock(web3) {
  return new Promise((resolve, reject) => {
    web3.currentProvider.sendAsync({
      jsonrpc: "2.0",
      method: "evm_mine",
      params: [],
      id: new Date().getTime()
    }, (err, result) => {
      if(err){ return reject(err) }
      return resolve(result)
    });
  });
}

async function evmSnapshot(web3) {
  return new Promise((resolve, reject) => {
    web3.currentProvider.sendAsync({
      jsonrpc: "2.0",
      method: "evm_snapshot",
      params: [],
      id: new Date().getTime()
    }, (err, result) => {
      if(err){ return reject(err) }
      return resolve(result)
    });
  });
}

async function evmRestore(web3, snapshot) {
  return new Promise((resolve, reject) => {
    web3.currentProvider.sendAsync({
      jsonrpc: "2.0",
      method: "evm_restore",
      params: [snapshot],
      id: new Date().getTime()
    }, (err, result) => {
      if(err){ return reject(err) }
      return resolve(result)
    });
  });
}

async function mineBlocks(web3, blocksToMine) {
  var promises = [];

  for (var i = 0; i < blocksToMine; i++) {
    promises.push(await mineBlock(web3));
  }

  return await Promise.all(promises);
}

async function toNumber(maybePromiseMaybeDecimal) {
  const n = await Promise.resolve(maybePromiseMaybeDecimal);

  if (typeof(n) === 'number') {
    return n;
  } else {
    return n.toNumber();
  }
}

module.exports = {
  mineBlocks: mineBlocks,
  annualBPSToScaledPerBlockRate: annualBPSToScaledPerBlockRate,
  validateRate: validateRate,
  validateRateWithMaxRatio: validateRateWithMaxRatio,
  scaleInterest: scaleInterest,

  // Simple function to stop futzing over numbers and promises in our tests
  toNumber: toNumber,

  takeSnapshot: evmSnapshot,

  restoreSnapshot: evmRestore,

  allowAll: async function(contracts, allowed) {
    const restores = await Promise.all(contracts.map(async (contract) => {
      return [contract, await contract.allowed.call()];
    }));

    await Promise.all(contracts.map((contract) => {
      return contract.allow(allowed.address);
    }));

    return restores;
  },

  restoreAll: async function(restores) {
    await Promise.all(restores.map(([contract, allowedAddress]) => {
      return contract.allow(allowedAddress);
    }));
  },

  random: function() {
    return Math.floor(Math.random() * Math.floor((Math.pow(2, 64))));
  },

  // https://ethereum.stackexchange.com/a/21661
  //
  assertEvents: function(contract, expectedEvents, args) {
    return new Promise((resolve, reject) => {
      var event = contract.allEvents(args);
      event.get((error, events) => {
        _.each(expectedEvents, (expectedEvent) => {
          if (!_.find(events, expectedEvent)) {
            throw new Error(expectedEvent.event + "(" + JSON.stringify(expectedEvent.args) + ") wasn't logged");
          }
        })
        resolve();
      });
      event.stopWatching();
    });
  },

  assertDifference: async function(assert, difference, checkFn, execFn) {
    const start = await checkFn();

    await execFn();

    const end = await checkFn();

    return assert.equal(end.minus(start).toNumber(), difference);
  },

  assertMatchingArray: function(firstArray, secondArray) {
    firstArray.forEach((value, index) =>
      assert.equal(value, secondArray[index])
    )
  },
  increaseTime: async function(web3, seconds) {
    await increaseTime(web3, seconds);
    await mineBlock(web3);
  },
  assertOnlyOwner: async function(contract, f, ownerAccountOrWeb3, nonOwnerAccountOrNull) {
    var ownerAccount, nonOwnerAccount;

    if (nonOwnerAccountOrNull) {
      ownerAccount = ownerAccountOrWeb3;
      nonOwnerAccount = nonOwnerAccountOrNull;
    } else {
      const web3 = ownerAccountOrWeb3;
      ownerAccount = web3.eth.accounts[0];
      nonOwnerAccount = web3.eth.accounts[1];
    }

    await f({from: ownerAccount});

    await assertGracefulFailure(contract, "Unauthorized", async () => {
      await f({from: nonOwnerAccount});
    });
  },

  assertOnlyAllowed: async function(contract, f, web3, afterEach) {
    const ownerAccount = web3.eth.accounts[0];
    const existingAllowedAccount = await contract.allowed.call();
    const allowedAccount = web3.eth.accounts[1];
    const nonAllowedAccount = web3.eth.accounts[2];

    await contract.allow(allowedAccount);

    await f({from: allowedAccount});

    if (afterEach) {
      await afterEach();
    }

    // Don't allow rando account
    await assertGracefulFailure(contract, "Allowed::NotAllowed", async () => {
      await f({from: nonAllowedAccount});
    });

    if (afterEach) {
      await afterEach();
    }

    // Not even owner
    await assertGracefulFailure(contract, "Allowed::NotAllowed", async () => {
      await f({from: ownerAccount});
    });

    await contract.allow(existingAllowedAccount);
  },

  createAndTransferWeth: async function(transferrable, etherToken, amount, account) {
    await etherToken.deposit({from: account, value: amount});
    await etherToken.transfer(transferrable, 100, {from: account});
  },

  supplyEth: async function(supplier, etherToken, amount, account) {
    await createAndApproveWeth(supplier, etherToken, amount, account);
    await supplier.customerSupply(etherToken.address, amount, {from: account});
  },

  ledgerAccountBalance: async function(ledger, account, token) {
    return await toNumber(ledger.getSupplyBalance.call(account, token));
  },

  tokenBalance: async function(token, account) {
    return await toNumber(token.balanceOf(account));
  },

  ethBalance: async function(account) {
    return await web3.eth.getBalance(account);
  },

  setAssetValue: async function(oracle, asset, amountInWei, web3) {
    return await oracle.setAssetValue(asset.address, toAssetValue(amountInWei), {from: web3.eth.accounts[0]});
  },

  addBorrowableAsset: async function(borrower, asset, web3) {
    return await borrower.addBorrowableAsset(asset.address, {from: web3.eth.accounts[0]});
  },

  assertInterestRate: async function(assert, interestRateStorage, etherTokenAddress, blockNumber, expectedBlockUnit, expectedBlockUnitInterestRate, expectedCompoundInterestRate) {
    assert.equal((await interestRateStorage.getSnapshotBlockUnit(etherTokenAddress, blockNumber)).toNumber(), expectedBlockUnit);
    assert.equal((await interestRateStorage.getSnapshotBlockUnitInterestRate(etherTokenAddress, blockNumber)).toNumber(), expectedBlockUnitInterestRate);
    assert.equal((await interestRateStorage.getCompoundedInterestRate(etherTokenAddress, blockNumber)).toNumber(), expectedCompoundInterestRate);
  },

// http://www.thecalculatorsite.com/articles/finance/compound-interest-formula.php
// A = P (1 + r/n) ^ (nt)
//
// Where:
//
// A = the future value of the investment/borrow, including interest
// P = the principal investment amount (the initial supply or borrow amount)
// r = the annual interest rate (decimal)
// n = the number of times that interest is compounded per year
// t = the number of years the money is invested or borrowed for

  compoundedInterest: (
    {
      principal,
      interestRate,
      payoutsPerTimePeriod,
      duration,
    }
  ) =>
    principal.times(
      one.plus(interestRate.dividedBy(payoutsPerTimePeriod)).
        toPower(payoutsPerTimePeriod.times(duration)
      )
    ),
  tokenAddrs: {
    OMG: "0x0000000000000000000000000000000000000001",
    BAT: "0x0000000000000000000000000000000000000002"
  },
  assertFailure,
  assertGracefulFailure,
  createAndApproveWeth,
}
