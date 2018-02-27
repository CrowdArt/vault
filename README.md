[![CircleCI](https://circleci.com/gh/compound-finance/vault.svg?style=svg&circle-token=d58f8a4064fc9f3b462d8629cc5187f8a7dcb673)](https://circleci.com/gh/compound-finance/vault)

Compound Vault
==============

The Compound Vault holds all of the contracts used to implement the Compound protocol. Through the Money Market contract, users of the blockchain *supply* capital (Ether or ERC-20 tokens) to earn interest, or *borrow* capital by holding collateral in the contract. The Money Market contract tracks each of these balances, a balance sheet and automatically sets interest rates.

Contracts
=========

We detail a few of the core contracts in the Compound protocol.

<dl>
  <dt>Money Market</dt>
  <dd>The main contract to interact with the Compound protocol. Users may supply capital (wrapped Ether or ERC-20 tokens) to this protocol, or may borrow assets with sufficient collateral.</dd>

  <dt>Ledger</dt>
  <dd>Tracks ledger entries in the Money Market. Every time a user supplies or borrows capital, the ledger will track a credit and a debit. Ledger also tracks the total balance sheet of the money market.</dd>

  <dt>Supplier</dt>
  <dd>Tracks when a user supplies capital to the Money Market. This sub-contract allows a customer to supply or withdraw capital and calcuates the interest rates via <em>account checkpoints</em>.</dd>

  <dt>Borrower</dt>
  <dd>The main contract to borrow from the Compound protocol. Users may borrow capital from Compound so long as that user keeps a sufficient amount of capital in other tokens with the protocol. This contract handles borrowing and what to do when an account fails to meet its threshold.</dd>

  <dt>Wallet</dt>
  <dd>A simple contract to allow users (if they wish) to have a contract to interact with the Compound protocol with simplified ABI functions.</dd>

  <dt>PriceOracle</dt>
  <dd>A contract to track the value of given assets in terms of Ether. This allows the protocol to determine how much a given account is able to borrow and still maintain a healty balance.</dd>

  <dt>InterestRateStorage</dt>
  <dd>A contract to store interest rates per block unit (10,000 blocks). This allows us to quickly apply interest to accounts by calculating the interest once per block unit, instead of for each account.</dd>
</dl>

Installation
------------
To install the Compound Vault first pull the repository from GitHub and then
install its dependencies:

    git clone https://github.com/compound-finance/vault
    cd vault
    yarn
    truffle compile
    truffle migrate

Testing
-------
Contract tests are defined under the [test
directory](https://github.com/compound-finance/vault/tree/master/test). To run the tests run:

    truffle test
    
Assertions used in our tests are provided by [ChaiJS](http://chaijs.com).    

Deployment
----------
To deploy the Vault contracts run:

    truffle deploy

_© Copyright 2017 Geoffrey Hayes, Compound_

Discussion
----------

For any concerns with the protocol, open an issue or visit us on [Discord](https://discordapp.com/invite/874ntdw) to discuss.

For security concerns, please email [security@compound.finance](mailto:security@compound.finance).
