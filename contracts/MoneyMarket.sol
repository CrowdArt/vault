pragma solidity ^0.4.19;


import "./InterestModel.sol";
import "./storage/BalanceSheet.sol";
import "./storage/BorrowStorage.sol";
import "./storage/InterestRateStorage.sol";
import "./storage/LedgerStorage.sol";
import "./storage/PriceOracle.sol";
import "./storage/TokenStore.sol";

/**
  * @title The Compound MoneyMarket Contract
  * @author Compound
  * @notice The Compound MoneyMarket Contract in the core contract governing
  *         all accounts in Compound.
  */
contract MoneyMarket {

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // module: MoneyMarket

    /**
      * @notice `MoneyMarket` is the core Compound MoneyMarket contract
      */
    function MoneyMarket() public {
        owner = msg.sender; // from Owned
    }

    /**
      * @notice Do not pay directly into MoneyMarket, please use `supply`.
      */
    function() payable public {
        revert();
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // module: Graceful
    event GracefulFailure(string errorMessage, uint256[] values);

    function failure(string errorMessage) internal returns (bool) {
        uint256[] memory values = new uint256[](0);

        GracefulFailure(errorMessage, values);

        return false;
    }

    function failure(string errorMessage, uint256 value0) internal returns (bool) {
        uint256[] memory values = new uint256[](1);
        values[0] = value0;

        GracefulFailure(errorMessage, values);

        return false;
    }

    function failure(string errorMessage, uint256 value0, uint256 value1) internal returns (bool) {
        uint256[] memory values = new uint256[](2);
        values[0] = value0;
        values[1] = value1;

        GracefulFailure(errorMessage, values);

        return false;
    }

    function failure(string errorMessage, uint256 value0, uint256 value1, uint256 value2) internal returns (bool) {
        uint256[] memory values = new uint256[](3);
        values[0] = value0;
        values[1] = value1;
        values[2] = value2;

        GracefulFailure(errorMessage, values);

        return false;
    }

    function failure(string errorMessage, uint256 value0, uint256 value1, uint256 value2, uint256 value3) internal returns (bool) {
        uint256[] memory values = new uint256[](4);
        values[0] = value0;
        values[1] = value1;
        values[2] = value2;
        values[3] = value3;

        GracefulFailure(errorMessage, values);

        return false;
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // module: Owned
    address owner;

    function getOwner() public view returns(address) {
        return owner;
    }

    function checkOwner() internal returns (bool) {
        if (msg.sender == owner) {
            return true;
        } else {
            failure("Unauthorized", uint256(msg.sender), uint256(owner));
            return false;
        }
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // module: Ledger tracks balances for a given customer by asset with interest

    LedgerStorage public ledgerStorage;
    InterestModel public interestModel;
    InterestRateStorage public interestRateStorage;
    BalanceSheet public balanceSheet;

    enum LedgerReason {
        CustomerSupply,
        CustomerWithdrawal,
        Interest,
        CustomerBorrow,
        CustomerPayBorrow,
        CollateralPayBorrow
    }
    enum LedgerType { Debit, Credit }
    enum LedgerAccount {
        Cash,
        Borrow,
        Supply,
        InterestExpense,
        InterestIncome,
        Trading
    }

    event LedgerEntry(
        LedgerReason    ledgerReason,     // Ledger reason
        LedgerType      ledgerType,       // Credit or Debit
        LedgerAccount   ledgerAccount,    // Ledger account
        address         customer,         // Customer associated with entry
        address         asset,            // Asset associated with this entry
        uint256         amount,           // Amount of asset associated with this entry
        uint256         balance,          // Ledger account is Supply or Borrow, the new balance
        uint64          interestRateBPS,  // Interest rate in basis point if fixed
        uint256         nextPaymentDate); // Next payment date if associated with borrow

    /**
      * @notice `setLedgerStorage` sets the ledger storage location for this contract
      * @dev This is for long-term data storage
      * @param ledgerStorageAddress The contract which acts as the long-term data store
      * @return Success of failure of operation
      */
    function setLedgerStorage(address ledgerStorageAddress) public returns (bool) {
        if (!checkOwner()) {
            return false;
        }

        ledgerStorage = LedgerStorage(ledgerStorageAddress);

        return true;
    }

    /**
      * @notice `setBalanceSheet` sets the balance sheet for this contract
      * @dev This is for long-term data storage
      * @param balanceSheetAddress The contract which acts as the long-term data store
      * @return Success of failure of operation
      */
    function setBalanceSheet(address balanceSheetAddress) public returns (bool) {
        if (!checkOwner()) {
            return false;
        }

        balanceSheet = BalanceSheet(balanceSheetAddress);

        return true;
    }

    /**
      * @notice `setInterestModel` sets the interest helper for this contract
      * @param interestModelAddress The contract which acts as the interest model
      * @return Success of failure of operation
      */
    function setInterestModel(address interestModelAddress) public returns (bool) {
        if (!checkOwner()) {
            return false;
        }

        interestModel = InterestModel(interestModelAddress);

        return true;
    }

    /**
      * @notice `setInterestRateStorage` sets the interest rate storage for this contract
      * @param interestRateStorageAddress The contract which acts as the interest rate storage
      * @return Success of failure of operation
      */
    function setInterestRateStorage(address interestRateStorageAddress) public returns (bool) {
        if (!checkOwner()) {
            return false;
        }

        interestRateStorage = InterestRateStorage(interestRateStorageAddress);

        return true;
    }

    /**
      * @notice Debit a ledger account.
      * @param ledgerReason What caused this debit?
      * @param ledgerAccount Which ledger account to adjust (e.g. Supply or Borrow)
      * @param customer The customer associated with this debit
      * @param asset The asset which is being debited
      * @param amount The amount to debit
      * @dev This throws on any error
      */
    function debit(LedgerReason ledgerReason, LedgerAccount ledgerAccount, address customer, address asset, uint256 amount) internal {
        if (!saveBlockInterest(asset, ledgerAccount)) {
            revert();
        }

        if (isAsset(ledgerAccount)) {
            if (isCustomerAccount(ledgerAccount)) {
                if (!ledgerStorage.increaseBalanceByAmount(customer, uint8(ledgerAccount), asset, amount)) {
                    revert();
                }
            }

            if (!balanceSheet.increaseAccountBalance(asset, uint8(ledgerAccount), amount)) {
                revert();
            }
        } else if(isLiability(ledgerAccount)) {
            if (isCustomerAccount(ledgerAccount)) {
                if (!ledgerStorage.decreaseBalanceByAmount(customer, uint8(ledgerAccount), asset, amount)) {
                    revert();
                }
            }

            if (!balanceSheet.decreaseAccountBalance(asset, uint8(ledgerAccount), amount)) {
                revert();
            }
        } else {
            // Untracked ledger account
        }

        // Debit Entry
        LedgerEntry({
            ledgerReason: ledgerReason,
            ledgerType: LedgerType.Debit,
            ledgerAccount: ledgerAccount,
            customer: customer,
            asset: asset,
            amount: amount,
            balance: getBalance(customer, ledgerAccount, asset),
            interestRateBPS: 0,
            nextPaymentDate: 0
            });

        if (!ledgerStorage.saveCheckpoint(customer, uint8(ledgerAccount), asset)) {
            revert();
        }
    }

    /**
      * @notice Credit a ledger account.
      * @param ledgerReason What caused this credit?
      * @param ledgerAccount Which ledger account to adjust (e.g. Supply or Borrow)
      * @param customer The customer associated with this credit
      * @param asset The asset which is being credited
      * @param amount The amount to credit
      * @dev This throws on any error
      */
    function credit(LedgerReason ledgerReason, LedgerAccount ledgerAccount, address customer, address asset, uint256 amount) internal {
        if (!saveBlockInterest(asset, ledgerAccount)) {
            revert();
        }

        if(isAsset(ledgerAccount)) {
            if (isCustomerAccount(ledgerAccount)) {
                if (!ledgerStorage.decreaseBalanceByAmount(customer, uint8(ledgerAccount), asset, amount)) {
                    revert();
                }
            }

            if (!balanceSheet.decreaseAccountBalance(asset, uint8(ledgerAccount), amount)) {
                revert();
            }
        } else if(isLiability(ledgerAccount)) {
            if (isCustomerAccount(ledgerAccount)) {
                if (!ledgerStorage.increaseBalanceByAmount(customer, uint8(ledgerAccount), asset, amount)) {
                    revert();
                }
            }

            if (!balanceSheet.increaseAccountBalance(asset, uint8(ledgerAccount), amount)) {
                revert();
            }
        } else {
            // Untracked ledger account
        }

        // Credit Entry
        LedgerEntry({
            ledgerReason: ledgerReason,
            ledgerType: LedgerType.Credit,
            ledgerAccount: ledgerAccount,
            customer: customer,
            asset: asset,
            amount: amount,
            balance: getBalance(customer, ledgerAccount, asset),
            interestRateBPS: 0,
            nextPaymentDate: 0
            });

        if (!ledgerStorage.saveCheckpoint(customer, uint8(ledgerAccount), asset)) {
            revert();
        }
    }

    /**
      * @notice `getBalance` gets a customer's balance
      * @param customer the customer
      * @param ledgerAccount the ledger account
      * @param asset the asset to query
      * @return true if the account is an asset false otherwise
      */
    function getBalance(address customer, LedgerAccount ledgerAccount, address asset) internal view returns (uint) {
        return ledgerStorage.getBalance(customer, uint8(ledgerAccount), asset);
    }

    /**
      * @notice `getCustomerBalance` gets a customer's balance
      * @param customer the customer
      * @param ledgerAccount the ledger account
      * @param asset the asset to query
      * @return true if the account is an asset false otherwise
      */
    function getCustomerBalance(address customer, uint8 ledgerAccount, address asset) public view returns (uint) {
        return getBalance(customer, LedgerAccount(ledgerAccount), asset);
    }

    /**
      * @notice `isAsset` indicates if this account is the type that has an associated balance
      * @param ledgerAccount the account type (e.g. Supply or Borrow)
      * @return true if the account is an asset, false otherwise
      */
    function isAsset(LedgerAccount ledgerAccount) private pure returns (bool) {
        return (
        ledgerAccount == LedgerAccount.Borrow ||
        ledgerAccount == LedgerAccount.Cash
        );
    }

    /**
      * @notice `isLiability` indicates if this account is the type that has an associated balance
      * @param ledgerAccount the account type (e.g. Supply or Borrow)
      * @return true if the account is an asset, false otherwise
      */
    function isLiability(LedgerAccount ledgerAccount) private pure returns (bool) {
        return (
        ledgerAccount == LedgerAccount.Supply
        );
    }

    /**
      * @notice `isCustomerAccount` indicates if this account is the balance of a customer
      * @param ledgerAccount the account type (e.g. Supply or Borrow)
      * @return true if the account is a customer account, false otherwise
      */
    function isCustomerAccount(LedgerAccount ledgerAccount) private pure returns (bool) {
        return (
        ledgerAccount == LedgerAccount.Supply ||
        ledgerAccount == LedgerAccount.Borrow
        );
    }

    /**
      * @notice `saveBlockInterest` takes a snapshot of the current block interest
      *         and total interest since the last snapshot
      * @param ledgerAccount the ledger account to snapshot
      * @param asset the asset to snapshot
      * @dev this function can be called idempotently within a block
      * @return success or failure
      */
    function saveBlockInterest(address asset, LedgerAccount ledgerAccount) internal returns (bool) {
        uint64 interestRate = getInterestRate(asset, ledgerAccount);

        if (interestRate > 0) {
            return interestRateStorage.saveBlockInterest(uint8(ledgerAccount), asset, interestRate);
        }

        return true;
    }

    /**
      * @notice `getInterestRate` returns the current interest rate for the given asset
      * @param asset The asset to query
      * @param ledgerAccount the account type (e.g. Supply or Borrow)
      * @return the interest rate scaled or something
      */
    function getInterestRate(address asset, LedgerAccount ledgerAccount) public view returns (uint64) {
        uint256 supply = balanceSheet.getBalanceSheetBalance(asset, uint8(LedgerAccount.Supply));
        uint256 borrows = balanceSheet.getBalanceSheetBalance(asset, uint8(LedgerAccount.Borrow));

        if (ledgerAccount == LedgerAccount.Borrow) {
            return interestModel.getScaledBorrowRatePerBlock(supply, borrows);
        } else if (ledgerAccount == LedgerAccount.Supply) {
            return interestModel.getScaledSupplyRatePerBlock(supply, borrows);
        } else {
            return 0;
        }
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // module: CollateralCalculator
    PriceOracle public priceOracle;

    // Minimum collateral to borrow ratio. Must be >= 1 when divided by collateralRatioScale.
    uint256 public scaledMinCollateralToBorrowRatio = 2 * collateralRatioScale;

    uint256 public constant collateralRatioScale = 10000;

    event MinimumCollateralRatioChange(uint256 newScaledMinimumCollateralRatio);

    /**
      * @notice `setPriceOracle` sets the priceOracle storage location for this contract
      * @dev This is for long-term data storage (TODO: Test)
      * @param priceOracleAddress The contract which acts as the long-term PriceOracle store
      * @return Success of failure of operation
      */
    function setPriceOracle(address priceOracleAddress) public returns (bool) {
        if (!checkOwner()) {
            return false;
        }

        priceOracle = PriceOracle(priceOracleAddress);

        return true;
    }

    /**
      * @notice `setScaledMinimumCollateralRatio` sets the minimum collateral ratio
      * @param scaledRatio the minimum collateral-to-borrow ratio to be set. It must be >= 1 when divided by collateralRatioScale
      * @return success or failure
      */
    function setScaledMinimumCollateralRatio(uint256 scaledRatio) public returns (bool) {
        if (!checkOwner()) {
            return false;
        }

        // enforce non-zero input and de-scaled value > 1
        if(scaledRatio <= collateralRatioScale) {
            return failure("Collateral::InvalidScaledRatio", scaledRatio);
        }

        scaledMinCollateralToBorrowRatio = scaledRatio;

        MinimumCollateralRatioChange(scaledMinCollateralToBorrowRatio);

        return true;
    }

    /**
      * @notice `getMaxWithdrawAvailable` gets the maximum withdrawal value available given supply and any outstanding borrows
      * It is supply - (borrows * minimumCollateralRatio)
      * @param account the address of the account
      * @return uint256 the maximum eth-equivalent value that can be withdrawn
      */
    function getMaxWithdrawAvailable(address account) public view returns (uint256) {

        ValueEquivalents memory ve = getValueEquivalents(account);

        uint256 ratioAdjustedBorrow = (ve.borrowValue * scaledMinCollateralToBorrowRatio)/ collateralRatioScale;
        if(ratioAdjustedBorrow >= ve.supplyValue) {
            return 0;
        }
        return ve.supplyValue - ratioAdjustedBorrow;
    }

    /**
      * @notice `getMaxBorrowAvailable` gets the maximum borrow available given supply and any outstanding borrows
      * It is maxWithdrawAvailable / minimumCollateralRatio
      * @param account the address of the account
      * @return uint256 the maximum additional eth equivalent borrow value that can be added to account
      */
    function getMaxBorrowAvailable(address account) public view returns (uint256) {

        return (getMaxWithdrawAvailable(account) * collateralRatioScale) / scaledMinCollateralToBorrowRatio;
    }


    /**
      * @notice `canWithdrawCollateral` returns true if the eth-equivalent value of asset <= `getMaxWithdrawAvailable`
      * @param account account that wants to withdraw
      * @param asset proposed for withdrawal
      * @param amount amount of asset proposed for withdrawal
      */
    function canWithdrawCollateral(address account, address asset, uint256 amount) public returns (bool) {
        uint256 maxWithdrawValue = getMaxWithdrawAvailable(account);

        uint256 withdrawValue = priceOracle.getAssetValue(asset, amount);
        bool result = maxWithdrawValue >= withdrawValue;
        if(!result) {
            failure("Collateral::WithdrawLimit", uint256(asset), amount, maxWithdrawValue, withdrawValue);
        }
        return result;
    }


    /**
      *
      * @notice `canBorrowAssetAmount` determines if the requested borrow amount is valid for the specified borrower
      * based on the borrowers current holdings and the minimum collateral to borrow ratio
      * @param borrower the borrower whose collateral should be examined
      * @param borrowAmount the requested (or current) borrow amount
      * @param borrowAsset denomination of borrow
      * @return boolean true if the requested amount is acceptable and false otherwise
      */
    function canBorrowAssetAmount(address borrower, uint256 borrowAmount, address borrowAsset) internal returns (bool) {

        uint256 borrowValue = priceOracle.getAssetValue(borrowAsset, borrowAmount);
        uint256 maxBorrowAvailable = getMaxBorrowAvailable(borrower);

        bool result = maxBorrowAvailable >= borrowValue;
        if(!result) {
            failure("Borrower::InvalidCollateralRatio", uint256(borrowAsset), borrowAmount, borrowValue, maxBorrowAvailable);
        }
        return result;
    }

    /**
      * @notice `collateralShortfall` returns eth equivalent value of collateral needed to bring borrower to a valid collateral ratio,
      * @param borrower account to check
      * @return the collateral shortfall value, or 0 if borrower has enough collateral
      */
    function collateralShortfall(address borrower) public view returns (uint256) {

        ValueEquivalents memory ve = getValueEquivalents(borrower);

        uint256 ratioAdjustedBorrow = (ve.borrowValue * scaledMinCollateralToBorrowRatio) / collateralRatioScale;

        uint256 result = 0;
        if(ratioAdjustedBorrow > ve.supplyValue) {
            result = ratioAdjustedBorrow - ve.supplyValue;
        }
        return result;
    }

    // There are places where it is useful to have both total supplyValue and total borrowValue.
    // This struct lets us get both at once in one loop over assets.
    struct ValueEquivalents {
        uint256 supplyValue;
        uint256 borrowValue;
    }

    function getValueEquivalents(address acct) internal view returns (ValueEquivalents memory) {
        uint256 assetCount = priceOracle.getAssetsLength(); // from PriceOracle
        uint256 supplyValue = 0;
        uint256 borrowValue = 0;

        for (uint16 i = 0; i < assetCount; i++) {
            address asset = priceOracle.assets(i);
            supplyValue += priceOracle.getAssetValue(asset, getBalance(acct, LedgerAccount.Supply, asset));
            borrowValue += priceOracle.getAssetValue(asset, getBalance(acct, LedgerAccount.Borrow, asset));
        }
        return ValueEquivalents({supplyValue: supplyValue, borrowValue: borrowValue});
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // module: Supplier
    TokenStore public tokenStore;

    /**
      * @notice `setTokenStore` sets the token store contract
      * @dev This is for long-term token storage
      * @param tokenStoreAddress The contract which acts as the long-term token store
      * @return Success of failure of operation
      */
    function setTokenStore(address tokenStoreAddress) public returns (bool) {
        if (!checkOwner()) {
            return false;
        }

        tokenStore = TokenStore(tokenStoreAddress);

        return true;
    }

    /**
      * @notice `checkTokenStore` verifies token store has been set
      * @return True if token store is initialized, false otherwise
      */
    function checkTokenStore() internal returns (bool) {
        if (tokenStore == address(0)) {
            failure("Supplier::TokenStoreUninitialized");
            return false;
        }

        return true;
    }

    /**
      * @notice `customerSupply` supplies a given asset in a customer's supplier account.
      * @param asset Asset to supply
      * @param amount The amount of asset to supply
      * @return success or failure
      */
    function customerSupply(address asset, uint256 amount) public returns (bool) {

        if (!checkTokenStore()) {
            return false;
        }

        if (!saveBlockInterest(asset, LedgerAccount.Supply)) {
            failure("Supplier::FailedToSaveBlockInterest", uint256(asset), uint256(LedgerAccount.Supply));
            return false;
        }

        if (!accrueSupplyInterest(msg.sender, asset)) {
            return false;
        }

        // EIP20 reverts if not allowed or balance too low.  We do a pre-check to enable a graceful failure message instead.
        EIP20Interface token = EIP20Interface(asset);
        uint256 allowance = token.allowance(msg.sender, address(this));
        uint256 balance = token.balanceOf(msg.sender);
        bool allowed = (balance >= amount && allowance >= amount);

        if(!allowed) {
            failure("Supplier::TokenTransferFromFail", uint256(asset), uint256(amount), allowance, uint256(msg.sender));
            return false;
        }

        if(!token.transferFrom(msg.sender, address(tokenStore), amount)) {
            failure("Supplier::TokenTransferFromFail2");
            return false;
        }

        debit(LedgerReason.CustomerSupply, LedgerAccount.Cash, msg.sender, asset, amount);
        credit(LedgerReason.CustomerSupply, LedgerAccount.Supply, msg.sender, asset, amount);
        return true;
    }

    /**
      * @notice `customerWithdraw` withdraws the given amount from a customer's balance of the specified asset
      * @param asset Asset type to withdraw
      * @param amount amount to withdraw
      * @param to address to withdraw to
      * @return success or failure
      */
    function customerWithdraw(address asset, uint256 amount, address to) public returns (bool) {
        if (!checkTokenStore()) {
            return false;
        }

        if (!saveBlockInterest(asset, LedgerAccount.Supply)) {
            failure("Supplier::FailedToSaveBlockInterest", uint256(asset), uint256(LedgerAccount.Supply));
            return false;
        }

        // accrue interest, which is likely to increase the balance, before checking balance.
        if (!accrueSupplyInterest(msg.sender, asset)) {
            return false;
        }

        // Make sure account holds enough of asset
        uint256 balance = getBalance(msg.sender, LedgerAccount.Supply, asset);
        if (amount > balance) {
            failure("Supplier::InsufficientBalance", uint256(asset), uint256(amount), uint256(to), uint256(balance));
            return false;
        }

        // make sure asset is not encumbered as collateral. requires eth-equivalent value calculation
        if(!canWithdrawCollateral(msg.sender, asset, amount)) {
            return false; // canWithdrawCollateral generates a graceful failure when it returns false
        }

        debit(LedgerReason.CustomerWithdrawal, LedgerAccount.Supply, msg.sender, asset, amount);
        credit(LedgerReason.CustomerWithdrawal, LedgerAccount.Cash, msg.sender, asset, amount);

        // Transfer asset out to `to` address
        if (!tokenStore.transferAssetOut(asset, to, amount)) {
            // TODO: We've marked the debits and credits, maybe we should reverse those?
            // Can we just do the following?
            // credit(LedgerReason.CustomerWithdrawal, LedgerAccount.Supply, msg.sender, asset, amount);
            // debit(LedgerReason.CustomerWithdrawal, LedgerAccount.Cash, msg.sender, asset, amount);
            // We probably ought to add LedgerReason.CustomerWithdrawalFailed and use that instead of LedgerReason.CustomerWithdrawal.
            // Either way, we'll likely need changes in Farmer and/or Data to process the resulting logs.
            failure("Supplier::TokenTransferToFail", uint256(asset), uint256(amount), uint256(to), uint256(balance));
            return false;
        }

        return true;
    }

    /**
      * @notice `getSupplyBalance` returns the balance (with interest) for
      *         the given account in the given asset (e.g. W-Eth or OMG)
      * @param customer The customer
      * @param asset The asset to check the balance of
      * @return The balance (with interest)
      */
    function getSupplyBalance(address customer, address asset) public returns (uint256) {
        if (!saveBlockInterest(asset, LedgerAccount.Supply)) {
            revert();
        }

        return interestRateStorage.getCurrentBalance(
            uint8(LedgerAccount.Supply),
            asset,
            ledgerStorage.getBalanceBlockNumber(customer, uint8(LedgerAccount.Supply), asset),
            ledgerStorage.getBalance(customer, uint8(LedgerAccount.Supply), asset)
        );
    }

    /**
      * @notice `accrueSupplyInterest` accrues any current interest on an
      *         supply account.
      * @param customer The customer
      * @param asset The asset to accrue supply interest on
      * @return success or failure
      */
    function accrueSupplyInterest(address customer, address asset) public returns (bool) {
        uint256 blockNumber = ledgerStorage.getBalanceBlockNumber(customer, uint8(LedgerAccount.Supply), asset);

        if (blockNumber != 0 && blockNumber != block.number) {
            // We need to true up balance

            uint256 balanceWithInterest = getSupplyBalance(customer, asset);
            uint256 balanceLessInterest = ledgerStorage.getBalance(customer, uint8(LedgerAccount.Supply), asset);

            if (balanceWithInterest - balanceLessInterest > balanceWithInterest) {
                // Interest should never be negative
                failure("Supplier::InterestUnderflow", uint256(asset), uint256(customer), balanceWithInterest, balanceLessInterest);
                return false;
            }

            uint256 interest = balanceWithInterest - balanceLessInterest;

            if (interest != 0) {
                debit(LedgerReason.Interest, LedgerAccount.InterestExpense, customer, asset, interest);
                credit(LedgerReason.Interest, LedgerAccount.Supply, customer, asset, interest);
                if (!ledgerStorage.saveCheckpoint(customer, uint8(LedgerAccount.Supply), asset)) {
                    revert();
                }
            }
        }

        return true;
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // module: Borrower
    BorrowStorage public borrowStorage;

    uint64 public constant discountRateScale = 10 ** 5;
    // Given a real number decimal, to convert it to basis points you multiply by 10000.
    // For example, we know 100 basis points = 1% = .01.  We get the basis points from the decimal: .01 * 10000 = 100
    uint16 constant basisPointMultiplier = 10000;

    uint16 public liquidationDiscountRateBPS = 200;
    uint16 public constant maxLiquidationDiscountRateBPS = 3000;

    /**
      * @notice `setBorrowStorage` sets the borrow storage location for this contract
      * @dev This is for long-term data storage (TODO: Test)
      * @param borrowStorageAddress The contract which acts as the long-term store
      * @return Success of failure of operation
      */
    function setBorrowStorage(address borrowStorageAddress) public returns (bool) {
        if (!checkOwner()) {
            return false;
        }

        borrowStorage = BorrowStorage(borrowStorageAddress);

        return true;
    }

    /**
      * @notice `setLiquidationDiscountNumeratorBPS` sets the discount rate on price of borrowed asset when liquidating a loan
      * @param basisPoints will be divided by 10000 to calculate the discount rate.  Must be <= maxLiquidationDiscountRateBPS.
      * @return Success or failure of operation
      */
    function setLiquidationDiscountRateBPS(uint16 basisPoints) public returns (bool) {
        if (!checkOwner()) {
            return false;
        }
        if(basisPoints > maxLiquidationDiscountRateBPS) {
            return failure("Borrower::InvalidLiquidationDiscount", uint256(basisPoints));
        }

        liquidationDiscountRateBPS = basisPoints;
        return true;
    }

    /**
      * @notice `customerBorrow` creates a new borrow and supplies the requested asset into the user's account.
      * @param asset The asset to borrow
      * @param amount The amount to borrow
      * @return success or failure
      */
    function customerBorrow(address asset, uint256 amount) public returns (bool) {
        if (!borrowStorage.borrowableAsset(asset)) {
            failure("Borrower::AssetNotBorrowable", uint256(asset));
            return false;
        }

        if (!canBorrowAssetAmount(msg.sender, amount, asset)) {
            // canBorrowAssetAmount generates a graceful failure message on failure
            return false;
        }

        if (!saveBlockInterest(asset, LedgerAccount.Borrow)) {
            failure("Borrower::FailedToSaveBlockInterest", uint256(asset), uint256(LedgerAccount.Borrow));
            return false;
        }

        // Check that we have a sufficient amount of cash to give to the customer
        uint256 assetCash = balanceSheet.getBalanceSheetBalance(asset, uint8(LedgerAccount.Cash));

        if (assetCash < amount) {
            failure("Borrower::InsufficientAssetCash", uint256(asset), assetCash);
            return false;
        }

        // TODO: If customer already has a borrow of asset, we need to make sure we can handle the change.
        // Before adding the new amount we will need to either calculate interest on existing borrow amount or snapshot
        // the current borrow balance.
        // Alternatively: Block additional borrow for same asset.

        debit(LedgerReason.CustomerBorrow, LedgerAccount.Borrow, msg.sender, asset, amount);
        credit(LedgerReason.CustomerBorrow, LedgerAccount.Supply, msg.sender, asset, amount);

        return true;
    }

    /**
      * @notice `customerPayBorrow` customer makes a borrow payment
      * @param asset The asset to pay down
      * @param amount The amount to pay down
      * @return success or failure
      */
    function customerPayBorrow(address asset, uint256 amount) public returns (bool) {
        if (!accrueBorrowInterest(msg.sender, asset)) {
            return false;
        }

        if (!saveBlockInterest(asset, LedgerAccount.Borrow)) {
            failure("Borrower::FailedToSaveBlockInterest", uint256(asset), uint256(LedgerAccount.Borrow));
            return false;
        }

        credit(LedgerReason.CustomerPayBorrow, LedgerAccount.Borrow, msg.sender, asset, amount);
        debit(LedgerReason.CustomerPayBorrow, LedgerAccount.Supply, msg.sender, asset, amount);

        return true;
    }

    /**
      * @notice `previewLiquidateCollateral` returns how much of the specified collateral a liquidator would receive
      * AT CURRENT PriceOracle PRICES by calling `liquidateCollateral` with the same parameters. See `liquidateCollateral`
      * for more information.
      * @param borrower the account whose borrow would be reduced
      * @param borrowedAsset the type of asset that was borrowed and that would be supplied by the msg.sender
      * @param borrowedAssetAmount how much of the borrowed asset msg.sender plans to supply; it will be applied to reduce
      * the balance of the borrow. NOTE: sender should first true up their balance if interest must be accrued in order
      * to supply collateralAsset
      * @param collateralAsset what asset msg.sender should receive in exchange- note that this will be
      * transferred from the borrower, so the borrower must have enough of the asset to support the amount resulting
      * from the borrowedAssetAmount and the discounted conversion price
      * @return the amount of collateral that would be received AT CURRENT PRICES. If 0 is returned, no liquidation
      * would occur. Check logs for failure reason.
      */
    function previewLiquidateCollateral(address borrower, address borrowedAsset, uint borrowedAssetAmount, address collateralAsset) public returns (uint256) {

        // Do basic checks first before running up gas costs.
        if (borrowedAsset == collateralAsset) {
            failure("Liquidation::CollateralSameAsBorrow", uint256(collateralAsset), uint256(borrowedAsset));
            return 0;
        }

        if (borrowedAssetAmount == 0) {
            failure("Liquidation::ZeroBorrowDeliveryAmount", uint256(borrowedAsset));
            return 0;
        }

        // Make sure msg.sender has as much of the borrowed asset as they are claiming to deliver
        // NOTE: liquidator is responsible for truing up their balance with any accrued interest, if that is necessary
        // to support the liquidation amount. Not truing up here avoids excess gas consumption for liquidators with a
        // large balance of borrowedAsset who wish to liquidate multiple under-collateralized borrows.
        uint256 liquidatorBalance = getBalance(msg.sender, LedgerAccount.Supply, borrowedAsset);
        if (liquidatorBalance < borrowedAssetAmount) {
            failure("Liquidation::InsufficientReplacementBalance", liquidatorBalance, uint256(borrowedAssetAmount));
            return 0;
        }

        // true up borrow balance first
        if (!accrueBorrowInterest(borrower, borrowedAsset)) {
            return 0;
        }

        uint256 borrowBalance = getBalance(borrower, LedgerAccount.Borrow, borrowedAsset);

        // Only check shortfall after truing up borrow balance.
        uint256 shortfall = collateralShortfall(borrower);
        // Only allow conversion if there is a non-zero shortfall
        if (shortfall == 0) {
            failure("Liquidation::ValidCollateralRatio", uint256(borrower));
            return 0;
        }

        // Disallow liquidation that exceeds current balance
        if (borrowedAssetAmount > borrowBalance) {
            failure("Liquidation::ExcessReplacementAmount", uint256(borrowedAssetAmount), uint(borrowBalance));
            return 0;
        }

        // TODO Later: We can use shortfall calculated above to limit amount of collateral seized.
        // We probably will want to allow the seizure to be slightly more than the shortfall to
        // increase the chance of the borrower staying within the valid collateral ratio after the
        // current liquidation is completed.

        // How much collateral should the liquidator receive?
        uint256 seizeCollateralAmount =
        getConvertedAssetValueWithDiscount(borrowedAsset, borrowedAssetAmount,
            collateralAsset, liquidationDiscountRateBPS);

        // Make sure borrower has enough of the requested collateral
        uint256 collateralBalance = getBalance(borrower, LedgerAccount.Supply, collateralAsset);
        if(collateralBalance < seizeCollateralAmount) {
            failure("Liquidation::InsufficientCollateral", collateralBalance, seizeCollateralAmount);
            return 0;
        }

        return seizeCollateralAmount;
    }

    /**
      * @notice `liquidateCollateral` enables a 3rd party to reduce a loan balance and receive the specified collateral
      * from the borrower.  It can only be used if the borrower is under the minimum collateral ratio.  As an incentive
      * to the liquidator, the collateral asset is priced at a small discount to its current price in the PriceOracle.
      * @param borrower the account whose borrow will be reduced
      * @param borrowedAsset the type of asset that was borrowed and that will be supplied by the msg.sender. msg.sender
      * must hold asset in the Compound Money Market.
      * @param borrowedAssetAmount how much of the borrowed asset msg.sender is supplying; it will be applied to reduce
      * the balance of the borrow
      * @param collateralAsset what asset msg.sender should receive in exchange- note that this will be
      * transferred from the borrower, so the borrower must have enough of the asset to support the amount resulting
      * from the borrowedAssetAmount and the discounted conversion price
      * @return the amount of collateral that was delivered to msg.sender. If 0 is returned, no liquidation occurred.
      * Check logs for failure reason.
      */
    function liquidateCollateral(address borrower, address borrowedAsset, uint borrowedAssetAmount, address collateralAsset) public returns (uint256) {

        uint256 liquidationAmount = previewLiquidateCollateral(borrower, borrowedAsset, borrowedAssetAmount, collateralAsset);
        if(liquidationAmount == 0) {
            return 0; // previewLiquidateCollateral should have generated a graceful failure message
        }

        // seize collateral
        credit(LedgerReason.CollateralPayBorrow, LedgerAccount.Supply, msg.sender, collateralAsset, liquidationAmount);
        debit(LedgerReason.CollateralPayBorrow, LedgerAccount.Supply, borrower, collateralAsset, liquidationAmount);

        // reduce borrow balance
        credit(LedgerReason.CollateralPayBorrow, LedgerAccount.Borrow, borrower, borrowedAsset, borrowedAssetAmount);
        debit(LedgerReason.CollateralPayBorrow, LedgerAccount.Supply, msg.sender, borrowedAsset, borrowedAssetAmount);

        return liquidationAmount;
    }

    /**
      * @notice `getBorrowBalance` returns the balance (with interest) for
      *         the given customers's borrow of the given asset (e.g. W-Eth or OMG)
      * @param customer The customer
      * @param asset The asset to check the balance of
      * @return The borrow balance of given account
      */
    function getBorrowBalance(address customer, address asset) public returns (uint256) {
        if (!saveBlockInterest(asset, LedgerAccount.Borrow)) {
            revert();
        }

        return interestRateStorage.getCurrentBalance(
            uint8(LedgerAccount.Borrow),
            asset,
            ledgerStorage.getBalanceBlockNumber(customer, uint8(LedgerAccount.Borrow), asset),
            ledgerStorage.getBalance(customer, uint8(LedgerAccount.Borrow), asset)
        );
    }

    /**
      * @notice `accrueBorrowInterest` accrues any current interest on a given borrow.
      * @param customer The customer
      * @param asset The asset to accrue borrow interest on
      * @return success or failure
      */
    function accrueBorrowInterest(address customer, address asset) public returns (bool) {
        uint256 blockNumber = ledgerStorage.getBalanceBlockNumber(customer, uint8(LedgerAccount.Borrow), asset);

        if (blockNumber != block.number) {
            uint256 balanceWithInterest = getBorrowBalance(customer, asset);
            uint256 balanceLessInterest = ledgerStorage.getBalance(customer, uint8(LedgerAccount.Borrow), asset);

            if (balanceWithInterest - balanceLessInterest > balanceWithInterest) {
                // Interest should never be negative
                failure("Borrower::InterestUnderflow", uint256(asset), uint256(customer), balanceWithInterest, balanceLessInterest);
                return false;
            }

            uint256 interest = balanceWithInterest - balanceLessInterest;

            if (interest != 0) {
                credit(LedgerReason.Interest, LedgerAccount.InterestIncome, customer, asset, interest);
                debit(LedgerReason.Interest, LedgerAccount.Borrow, customer, asset, interest);
                if (!ledgerStorage.saveCheckpoint(customer, uint8(LedgerAccount.Borrow), asset)) {
                    revert();
                }
            }
        }

        return true;
    }


    /**
     * `getConvertedAssetValueWithDiscount` returns the PriceOracle's view of the current
     * value of srcAsset in terms of targetAsset, after applying the specified discount to
     * the oracle's targetAsset value. Returns 0 if either asset is unknown.
     *
     * @param srcAsset The address of the asset to query
     * @param srcAssetAmount The amount in base units of the asset
     * @param targetAsset The asset in which we want to value srcAsset
     * @param targetDiscountRateBPS the unscaled numerator for basis points discount to be applied to current PriceOracle
     * price of targetAsset (aka for a discount of 5% it should be 500)
     * @return value The value in wei of the asset, or zero.
     */
    function getConvertedAssetValueWithDiscount(address srcAsset, uint256 srcAssetAmount, address targetAsset, uint16 targetDiscountRateBPS) public view returns(uint) {

        if(srcAsset == targetAsset) {
            return 0;
        }

        // We get scaled value from oracle and add discount scaling on top.
        uint scaledSrcValue = scaledDiscountPrice(priceOracle.getScaledValue(srcAsset), 0);
        uint scaledTargetValue = scaledDiscountPrice(priceOracle.getScaledValue(targetAsset), targetDiscountRateBPS);

        if (scaledSrcValue == 0 || scaledTargetValue == 0) {
            return 0; // not supported
        }

        // since we have discount scaling in both the numerator and the denominator, they cancel each other out
        // and we do not need an explicit de-scale operation.
        return (scaledSrcValue * srcAssetAmount) / scaledTargetValue;
    }

    /**
      * @notice `scaledDiscountPrice`
      * @param price value from PriceOracle for an asset
      * @param unscaledDiscountRateBPS the numerator of a basis points fraction, e.g it should be 500 to represent 5%. 0 is a valid discount.
      * @return the scaled discount price after applying the discount rate
      */
    function scaledDiscountPrice(uint price, uint16 unscaledDiscountRateBPS) public pure returns (uint) {

        return (( basisPointMultiplier*discountRateScale - (unscaledDiscountRateBPS * discountRateScale)) * price) / basisPointMultiplier;
    }

    // TODO: Remove the following module before deployment to main net
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // module: easy to examine stuff for trying out truffle debug.
    // Adapted from http://truffleframework.com/tutorials/debugging-a-smart-contract
    // This is intended to be removed before deployment to main net.

    uint8 myVar;

    event Odd();

    event Even();

    function set(uint8 x) public {
        myVar = x;
        if (x % 2 == 0) {
            Even();
        } else {
            Odd();
        }
    }

    function get() public view returns (uint8) {
        return myVar;
    }

}
