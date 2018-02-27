pragma solidity ^0.4.19;

import "./base/Owned.sol";
import "./MoneyMarket.sol";
import "./eip20/EIP20Interface.sol";
import "./tokens/WETH9.sol";

/**
  * @title The Compound Smart Wallet
  * @author Compound
  * @notice The Compound Smart Wallet allows customers to easily access
  *         the Compound core contracts.
  */
contract Wallet is Owned {
    MoneyMarket public moneyMarket;
    WETH9 public etherToken;

    event Supply(address acct, address asset, uint256 amount);
    event Withdrawal(address acct, address asset, uint256 amount);
    event Borrow(address acct, address asset, uint256 amount);

    /**
      * @notice Creates a new Wallet.
      * @param moneyMarketAddress Address of Compound MoneyMarket contract
      * @param etherTokenAddress Address of WETH9 contract
      */
    function Wallet(address owner_, address moneyMarketAddress, address etherTokenAddress) public {
        owner = owner_;
        moneyMarket = MoneyMarket(moneyMarketAddress);
        etherToken = WETH9(etherTokenAddress);
    }

    /**
      * @notice Supplies eth into the Compound MoneyMarket contract
      * @return success or failure
      */
    function supplyEth() public payable returns (bool) {
        // Transfer eth into WETH9
        // This should only fail if out-of-gas
        etherToken.deposit.value(msg.value)();

        return supplyDirect(address(etherToken), msg.value);
    }

    /**
      * @notice Supplies token into Compound MoneyMarket contract
      * @param asset Address of token
      * @param amount Amount of token to transfer
      * @return success or failure
      */
    function supplyAsset(address asset, uint256 amount) public returns (bool) {
        // First, transfer in to this wallet
        if (!EIP20Interface(asset).transferFrom(msg.sender, address(this), amount)) {
            failure("Wallet::TokenTransferFailed");
            return false;
        }

        return supplyDirect(asset, amount);
    }

    /**
      * @notice Supplies token into Compound MoneyMarket contract from this Wallet
      * @param asset Address of token (must be owned by this contract)
      * @param amount Amount of token to transfer
      * @return success or failure
      */
    function supplyDirect(address asset, uint256 amount) public returns (bool) {
        // Approve the moneyMarket to pull in this asset
        if (!EIP20Interface(asset).approve(address(moneyMarket), amount)) {
            failure("Wallet::AssetApproveFailed", uint256(msg.sender), uint256(asset), uint256(amount));
            return false;
        }

        // Supply asset in Compound MoneyMarket contract
        if (!moneyMarket.customerSupply(asset, amount)) {
            return false;
        }

        // Log this supply
        Supply(msg.sender, asset, amount);

        return true;
    }

    /**
      * @notice Withdraws eth from Compound MoneyMarket contract
      * @param amount Amount to withdraw
      * @param to Address to withdraw to
      * @return success or failure
      */
    function withdrawEth(uint256 amount, address to) public returns (bool) {
        if (!checkOwner()) {
            return false;
        }

        // Withdraw from Compound MoneyMarket contract to WETH9
        if (!moneyMarket.customerWithdraw(address(etherToken), amount, address(this))) {
            return false;
        }

        // Now we have WETH9s, let's withdraw them to Eth
        // Note, this fails with `revert`
        etherToken.withdraw(amount);

        // Now, we should have the ether from the withdraw,
        // let's send that to the `to` address
        if (!to.send(amount)) {
            // TODO: The asset is now stuck in the wallet?
            failure("Wallet::EthTransferFailed", uint256(msg.sender), uint256(to), uint256(amount));
            return false;
        }

        // Log event
        Withdrawal(msg.sender, address(etherToken), amount);

        return true;
    }

    /**
      * @notice Withdraws asset from Compound MoneyMarket contract
      * @param asset Asset to withdraw
      * @param amount Amount to withdraw
      * @param to Address to withdraw to
      * @return success or failure
      */
    function withdrawAsset(address asset, uint256 amount, address to) public returns (bool) {
        if (!checkOwner()) {
            return false;
        }

        // Withdraw the asset
        if (!moneyMarket.customerWithdraw(asset, amount, to)) {
            return false;
        }

        // Log event
        Withdrawal(msg.sender, asset, amount);

        return true;
    }

    /**
      * @notice Borrows eth from Compound MoneyMarket contract
      * @param amount Amount to borrow
      * @param to Address to withdraw to
      * @return success or failure
      */
    function borrowEth(uint256 amount, address to) public returns (bool) {
        if (!checkOwner()) {
            return false;
        }

        // Borrow the ether asset
        if (!moneyMarket.customerBorrow(address(etherToken), amount)) {
            return false;
        }

        // Log borrow event
        Borrow(msg.sender, address(etherToken), amount);

        // Now withdraw the ether asset
        return withdrawEth(amount, to);
    }

    /**
      * @notice Borrows asset from Compound MoneyMarket contract
      * @param asset Asset to borrow
      * @param amount Amount to borrow
      * @param to Address to withdraw to
      * @return success or failure
      */
    function borrowAsset(address asset, uint256 amount, address to) public returns (bool) {
        if (!checkOwner()) {
            return false;
        }

        // Borrow the asset
        if (!moneyMarket.customerBorrow(asset, amount)) {
            return false;
        }

        // Log borrow event
        Borrow(msg.sender, asset, amount);

        // Now withdraw the asset
        return withdrawAsset(asset, amount, to);
    }

    /**
      * @notice Returns the balance of Eth in this wallet via MoneyMarket Contract
      * @return Eth balance from MoneyMarket Contract
      */
    function balanceEth() public returns (uint256) {
        return balance(address(etherToken));
    }

    /**
      * @notice Returns the balance of given asset in this wallet via MoneyMarket Contract
      * @return Asset balance from MoneyMarket Contract
      */
    function balance(address asset) public returns (uint256) {
        return moneyMarket.getSupplyBalance(address(this), asset);
    }

    /**
      * @notice Supply Eth into Compound MoneyMarket contract.
      * @dev We allow arbitrary supplys in from `etherToken`
      *      Note: Fallback functions cannot have return values.
      */
    function() public payable {
        if (msg.sender == address(etherToken)) {
            /* This contract unwraps WETH9s during withdrawals.
             *
             * When we unwrap a token, WETH9 sends this contract
             * the value of the tokens in Ether. We should not treat this
             * as a new supply (!!), and as such, we choose to not call
             * `supplyEth` for Ether transfers from WETH9.
             */

            return;
        } else {
            supplyEth();
        }
    }
}
