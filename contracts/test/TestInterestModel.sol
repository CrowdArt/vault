pragma solidity ^0.4.19;

/**
  * @title Test Contract for Interest Model
  * @author Compound
  */
contract TestInterestModel {
    function getScaledSupplyRatePerBlock(uint256 supply, uint256 borrows) public pure returns (uint64) {
        return uint64(supply * 10000 + borrows);
    }

    function getScaledBorrowRatePerBlock(uint256 supply, uint256 borrows) public pure returns (uint64) {
        return uint64(borrows * 10000 + supply);
    }
}
