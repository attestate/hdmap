/// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.6;

import "forge-std/Test.sol";

import {Harberger, Perwei} from "./Harberger.sol";

contract HarbergerTest is Test {
  function testPriceZero() public {
    uint256 blockDiff = 50;
    Perwei memory perwei1 = Perwei(100, 100);

    uint256 price = 0;
    (uint256 nextPrice, uint256 taxes) = Harberger.getNextPrice(
      perwei1,
      blockDiff,
      price
    );
    assertEq(nextPrice, 0);
    assertEq(taxes, 0);
  }

  function testUsedBuffer() public {
    uint256 blockDiff = 50;
    Perwei memory perwei1 = Perwei(1, 100);
    uint256 price = 1 ether;

    (uint256 nextPrice, uint256 taxes) = Harberger.getNextPrice(
      perwei1,
      blockDiff,
      price
    );
    assertEq(nextPrice, 0.5 ether);
    assertEq(taxes, 0.5 ether);
  }

  function testLowerPrice() public {
    uint256 blockDiff = 51;
    Perwei memory perwei1= Perwei(1, 100);
    uint256 price = 1 ether;

    (uint256 nextPrice, uint256 taxes) = Harberger.getNextPrice(
      perwei1,
      blockDiff,
      price
    );
    assertEq(nextPrice, 0.49 ether);
    assertEq(taxes, 0.51 ether);
  }

  function testConsumingTotalPrice() public {
    uint256 blockDiff = 150;
    Perwei memory perwei1 = Perwei(1, 100);
    uint256 price = 1 ether;

    (uint256 nextPrice, uint256 taxes) = Harberger.getNextPrice(
      perwei1,
      blockDiff,
      price
    );
    assertEq(nextPrice, 0);
    assertEq(taxes, 1 ether);
  }

  function testGettingNextPrice() public {
    uint256 blockDiff = 1;
    Perwei memory perwei1 = Perwei(1, 100);
    uint256 price = 1 ether;

    (uint256 nextPrice, uint256 taxes) = Harberger.getNextPrice(
      perwei1,
      blockDiff,
      price
    );
    assertEq(nextPrice, 0.99 ether);
    assertEq(taxes, 0.01 ether);
  }

  function testBlockTax() public {
    uint256 blockDiff1 = 1;
    Perwei memory perwei1 = Perwei(1, 100);
    assertEq(Harberger.taxPerBlock(perwei1, blockDiff1, 1 ether), 0.01 ether);

    uint256 blockDiff2 = 2;
    Perwei memory perwei2 = Perwei(1, 100);
    assertEq(Harberger.taxPerBlock(perwei2, blockDiff2, 1 ether), 0.02 ether);

    uint256 blockDiff3 = 100;
    Perwei memory perwei3 = Perwei(1, 100);
    assertEq(Harberger.taxPerBlock(perwei3, blockDiff3, 1 ether), 1 ether);

    uint256 blockDiff4 = 2;
    Perwei memory perwei4 = Perwei(100, 100);
    assertEq(Harberger.taxPerBlock(perwei4, blockDiff4, 1 ether), 2 ether);

    uint256 blockDiff5 = 1;
    Perwei memory perwei5 = Perwei(1, 1000);
    assertEq(Harberger.taxPerBlock(perwei5, blockDiff5, 1 ether), 0.001 ether);

    uint256 blockDiff6 = 1;
    // NOTE: To test the precision up to 18 decimals, we're gonna simulate a
    // tax that is 1 WEI per block.
    Perwei memory perwei6 = Perwei(1, 1e18);
    assertEq(Harberger.taxPerBlock(perwei6, blockDiff6, 1 ether), 1 wei);
  }
}
