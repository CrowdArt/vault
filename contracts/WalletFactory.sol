pragma solidity ^0.4.19;

import "./base/Owned.sol";
import "./Wallet.sol";

/**
  * @title The Compound Smart Wallet Factory
  * @author Compound
  * @notice Helps Compound users create a Compound Smart Wallet
  * 		after registration.
  */
contract WalletFactory is Owned {
    /*
     * Note: These state variables are immuatable.
     * We must create a new factory to change either address.
     */
    address public moneyMarketAddress;
    address public etherTokenAddress;

    event NewWallet(address walletOwner, address newWalletAddress, address walletFactoryAddress);

    /**
      * @notice Creates a new Wallet Factory.
      * @param moneyMarketAddress_ Address of Compound MoneyMarket contract
      * @param etherTokenAddress_ Address of Compound WETH9 contract
      */
    function WalletFactory(address moneyMarketAddress_, address etherTokenAddress_) public {
        moneyMarketAddress = moneyMarketAddress_;
        etherTokenAddress = etherTokenAddress_;
    }

    /**
      * @notice Creates a new Compound Smart Wallet with given owner
      * @return wallet The new wallet which was created
      * !!SECURITY!! Add back `ownerOnly` check
      */
    function newWallet(address walletOwner) public returns (Wallet) {
        Wallet wallet = new Wallet(walletOwner, moneyMarketAddress, etherTokenAddress);

        NewWallet(walletOwner, address(wallet), address(this));

        return wallet;
    }

}
