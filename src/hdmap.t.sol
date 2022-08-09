/// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.6;

import "forge-std/Test.sol";

import { Dmap } from './dmap.sol';
import { RootZone } from './root.sol';
import { Hdmap, Deed } from "./hdmap.sol";

contract Taker {
  function take(Hdmap hdmap, bytes32 key) external payable {
    hdmap.take{value: msg.value}(key);
  }

  function set(Hdmap hdmap, bytes32 key, bytes32 meta, bytes32 data) external {
    hdmap.set(key, meta, data);
  }
}

contract CensorTaker is Taker {
  fallback() external payable {
    revert();
  }
}

contract Censor {
  fallback() external payable {
    revert();
  }
}

contract Reentry {
  fallback() external payable {
    Hdmap hdmap = Hdmap(msg.sender);
    bytes32 key = 0x0000000000000000000000000000000000000000000000000000000000000666;
    hdmap.take{value: 1}(key);
  }
}

contract BeneficiaryReentry is Taker, Reentry {}

contract HdmapTest is Test {
  // Address of publicly deployed dmap
  address dmapAddress = 0x90949c9937A11BA943C7A72C3FA073a37E3FdD96;
  address rootAddress = 0x022ea9ba506E38eF6093b6AB53e48bbD60f86832;

  Dmap dmap;
  Hdmap hdmap;
  RootZone rz;
  bytes32 commitment;

  event Give(
    address indexed giver,
    bytes32 indexed zone,
    address indexed recipient
  );

  receive() external payable {}

  function testIfBeneficiaryRentrancyIsGuarded() public {
    bytes32 key = 0x0000000000000000000000000000000000000000000000000000000000001337;
    uint256 value = 1;
    hdmap.take{value: value}(key);

    BeneficiaryReentry br = new BeneficiaryReentry();
    vm.etch(block.coinbase, address(br).code);
    assertEq(block.coinbase.code, address(br).code);
    br.take{value: 2}(hdmap, key);

    bytes32 reentryKey = 0x0000000000000000000000000000000000000000000000000000000000000666;
    (address controller, uint256 collateral, uint256 startBlock) = hdmap.deeds(reentryKey);
    assertEq(controller, address(0));
    assertEq(collateral, 0);
    assertEq(startBlock, 0);
  }

  function testIfCoinbaseRentrancyIsGuarded() public {
    bytes32 key = 0x0000000000000000000000000000000000000000000000000000000000001337;
    uint256 value = 1;
    hdmap.take{value: value}(key);

    Reentry reentry = new Reentry();
    vm.etch(block.coinbase, address(reentry).code);
    assertEq(block.coinbase.code, address(reentry).code);
    hdmap.take{value: 2}(key);

    bytes32 reentryKey = 0x0000000000000000000000000000000000000000000000000000000000000666;
    (address controller, uint256 collateral, uint256 startBlock) = hdmap.deeds(reentryKey);
    assertEq(controller, address(0));
    assertEq(collateral, 0);
    assertEq(startBlock, 0);
  }

  function testToMakeSureThatBeneficiaryCannotCensorTake() public {
    bytes32 key = 0x0000000000000000000000000000000000000000000000000000000000001337;
    uint256 value = 1;
    hdmap.take{value: value}(key);

    Censor censor = new Censor();
    vm.etch(block.coinbase, address(censor).code);
    assertEq(block.coinbase.code, address(censor).code);
    CensorTaker ct = new CensorTaker();
    ct.take{value: 2}(hdmap, key);
  }

  function testToMakeSureThatCoinbaseCannotCensorTake() public {
    bytes32 key = 0x0000000000000000000000000000000000000000000000000000000000001337;
    uint256 value = 1;
    hdmap.take{value: value}(key);

    Censor censor = new Censor();
    vm.etch(block.coinbase, address(censor).code);
    assertEq(block.coinbase.code, address(censor).code);
    hdmap.take{value: 2}(key);
  }

  function setUp() public {
    dmap = Dmap(dmapAddress);
    hdmap = new Hdmap(dmap);

    bytes32 salt = 0x73616c7400000000000000000000000000000000000000000000000000000000; // b32("salt");
    bytes32 name = 0x68646d6170000000000000000000000000000000000000000000000000000000; // b32("hdmap");
    address zone = address(hdmap);
    bytes memory encoded = abi.encode(salt, name, zone);
    commitment = keccak256(encoded);

    rz = RootZone(rootAddress);
    rz.hark{value: 1 ether}(commitment);
    assertEq(rz.mark(), commitment, "after hark");

    rz.etch(salt, name, zone);
    assertEq(rz.mark(), commitment, "after etch");

    bytes32 slot = keccak256(encodeZoneAndName(address(rz), name));
    (bytes32 meta, bytes32 data) = dmap.get(slot);
    assertEq(data, bytes32(bytes20(address(hdmap))));
  }

  function encodeZoneAndName(address zone, bytes32 name) public pure returns (bytes memory) {
    bytes12 empty = 0x000000000000;
    return abi.encodePacked(empty, bytes20(zone), name);
  }

  function testEncodeZoneAndName() public {
    address zone = 0x022ea9ba506E38eF6093b6AB53e48bbD60f86832;
    bytes32 name = 0x68646d6170000000000000000000000000000000000000000000000000000000; // b32("hdmap");
    bytes memory code = encodeZoneAndName(zone, name);
    bytes memory expected = hex"000000000000000000000000022ea9ba506E38eF6093b6AB53e48bbD60f8683268646d6170000000000000000000000000000000000000000000000000000000";
    assertEq(code, expected);
  }

  function testCalculatingSlot() public {
    address zone = 0x022ea9ba506E38eF6093b6AB53e48bbD60f86832;
    bytes32 name = 0x68646d6170000000000000000000000000000000000000000000000000000000; // b32("hdmap");
    bytes memory code = encodeZoneAndName(zone, name);
    bytes32 expected = 0xf020a19d5890843c96480ace83c5d0f64285d8a4606492d951dfe770cc344679;
    assertEq(keccak256(code), expected);
  }

  function testFailTakeForFree() public {
    bytes32 key = 0x0000000000000000000000000000000000000000000000000000000000001337;
    hdmap.take{value: 0}(key);
  }

  function testTake() public {
    bytes32 key = 0x0000000000000000000000000000000000000000000000000000000000001337;
    uint256 value = 1;
    uint256 currentBlock = block.number;
    vm.expectEmit(true, true, true, false);
    emit Give(address(0), key, address(this));
    hdmap.take{value: value}(key);

    (address controller, uint256 collateral, uint256 startBlock) = hdmap.deeds(key);
    assertEq(controller, address(this));
    assertEq(collateral, value);
    assertEq(startBlock, currentBlock);
  }

  function testReTakeForLowerPrice() public {
    bytes32 key = 0x0000000000000000000000000000000000000000000000000000000000001337;
    uint256 value = hdmap.denominator();
    uint256 currentBlock = block.number;
    hdmap.take{value: value}(key);

    (address controller0, uint256 collateral0, uint256 startBlock0) = hdmap.deeds(key);
    assertEq(controller0, address(this));
    assertEq(collateral0, value);
    assertEq(startBlock0, currentBlock);

    vm.roll(block.number+1);

    (uint256 nextPrice1, uint256 taxes1) = hdmap.status(key);
    assertEq(nextPrice1, collateral0-1);
    assertEq(taxes1, 1);

    Taker taker = new Taker();
    vm.expectRevert(bytes("ERR_VAL"));
    taker.take{value: collateral0-2}(hdmap, key);
  }

  function testReTake() public {
    bytes32 key = 0x0000000000000000000000000000000000000000000000000000000000001337;
    uint256 value = hdmap.denominator();
    uint256 currentBlock = block.number;
    hdmap.take{value: value}(key);

    (address controller0, uint256 collateral0, uint256 startBlock0) = hdmap.deeds(key);
    assertEq(controller0, address(this));
    assertEq(collateral0, value);
    assertEq(startBlock0, currentBlock);

    vm.roll(block.number+1);

    (uint256 nextPrice1, uint256 taxes1) = hdmap.status(key);
    assertEq(nextPrice1, collateral0-1);
    assertEq(taxes1, 1);

    Taker taker = new Taker();
    uint256 balance0 = address(this).balance;
    vm.expectEmit(true, true, true, false);
    emit Give(address(this), key, address(taker));
    taker.take{value: collateral0}(hdmap, key);
    uint256 balance1 = address(this).balance;
    assertEq(balance0 - balance1, 1);

    (address controller1, uint256 collateral1, uint256 startBlock1) = hdmap.deeds(key);
    assertEq(controller1, address(taker));
    assertEq(collateral1, collateral0);
    assertEq(startBlock1, block.number);
  }

  function testCostAfterAYear() public {
    bytes32 key = 0x0000000000000000000000000000000000000000000000000000000000001337;
    uint256 value = 1 ether;
    uint256 currentBlock = block.number;
    hdmap.take{value: value}(key);

    (address controller, uint256 collateral, uint256 startBlock) = hdmap.deeds(key);
    assertEq(controller, address(this));
    assertEq(collateral, value);
    assertEq(startBlock, currentBlock);

    (uint256 nextPrice0, uint256 taxes0) = hdmap.status(key);
    assertEq(nextPrice0, collateral);
    assertEq(taxes0, 0);

    vm.roll(block.number+hdmap.denominator());

    (uint256 nextPrice1, uint256 taxes1) = hdmap.status(key);
    assertEq(nextPrice1, 0);
    assertEq(taxes1, value);
  }

  function testStatus() public {
    bytes32 key = 0x0000000000000000000000000000000000000000000000000000000000001337;
    uint256 value = hdmap.denominator();
    uint256 currentBlock = block.number;
    hdmap.take{value: value}(key);

    (address controller, uint256 collateral, uint256 startBlock) = hdmap.deeds(key);
    assertEq(controller, address(this));
    assertEq(collateral, value);
    assertEq(startBlock, currentBlock);

    (uint256 nextPrice0, uint256 taxes0) = hdmap.status(key);
    assertEq(nextPrice0, collateral);
    assertEq(taxes0, 0);

    vm.roll(block.number+1);

    (uint256 nextPrice1, uint256 taxes1) = hdmap.status(key);
    assertEq(nextPrice1, collateral-1);
    assertEq(taxes1, 1);

    vm.roll(block.number+value-1);
    (uint256 nextPrice2, uint256 taxes2) = hdmap.status(key);
    assertEq(nextPrice2, 0);
    assertEq(taxes2, value);
  }

  function testGive() public {
    bytes32 key = 0x0000000000000000000000000000000000000000000000000000000000001337;
    uint256 value = hdmap.denominator();
    uint256 currentBlock = block.number;
    hdmap.take{value: value}(key);

    (address controller0, uint256 collateral0, uint256 startBlock0) = hdmap.deeds(key);
    assertEq(controller0, address(this));
    assertEq(collateral0, value);
    assertEq(startBlock0, currentBlock);

    address recipient = address(1337);
    vm.expectEmit(true, true, true, false);
    emit Give(address(this), key, recipient);
    hdmap.give(key, recipient);

    (address controller1, uint256 collateral1, uint256 startBlock1) = hdmap.deeds(key);
    assertEq(controller1, recipient);
    assertEq(collateral1, value);
    assertEq(startBlock1, currentBlock);
  }

  function testSetNonExistent() public {
    bytes32 key = 0x0000000000000000000000000000000000000000000000000000000000001337;
    bytes32 meta = 0x0000000000000000000000000000000000000000000000000000000000001337;
    bytes32 data = 0x0000000000000000000000000000000000000000000000000000000000001337;
    vm.expectRevert(bytes("ERR_OWNER"));
    hdmap.set(key, meta, data);
  }

  function testSetWithoutPermission() public {
    bytes32 key = 0x0000000000000000000000000000000000000000000000000000000000001337;
    uint256 value = hdmap.denominator();
    hdmap.take{value: value}(key);

    bytes32 meta = 0x0000000000000000000000000000000000000000000000000000000000001337;
    bytes32 data = 0x0000000000000000000000000000000000000000000000000000000000001337;
    Taker taker = new Taker();
    vm.expectRevert(bytes("ERR_OWNER"));
    taker.set(hdmap, key, meta, data);
  }

  function testSet() public {
    bytes32 key = 0x0000000000000000000000000000000000000000000000000000000000001337;
    uint256 value = hdmap.denominator();
    hdmap.take{value: value}(key);

    bytes32 meta = 0x0000000000000000000000000000000000000000000000000000000000001337;
    bytes32 data = 0x0000000000000000000000000000000000000000000000000000000000001337;
    hdmap.set(key, meta, data);

    bytes32 slot = keccak256(encodeZoneAndName(address(hdmap), key));
    (bytes32 actualMeta, bytes32 actualData) = dmap.get(slot);
    assertEq(actualMeta, meta);
    assertEq(actualData, data);
  }

  function testSetTwice() public {
    bytes32 key = 0x0000000000000000000000000000000000000000000000000000000000001337;
    uint256 value = hdmap.denominator();
    hdmap.take{value: value}(key);

    bytes32 meta0 = 0x0000000000000000000000000000000000000000000000000000000000001337;
    bytes32 data0 = 0x0000000000000000000000000000000000000000000000000000000000001337;
    hdmap.set(key, meta0, data0);

    bytes32 slot = keccak256(encodeZoneAndName(address(hdmap), key));
    (bytes32 actualMeta, bytes32 actualData) = dmap.get(slot);
    assertEq(actualMeta, meta0);
    assertEq(actualData, data0);

    bytes32 meta1 = 0x0000000000000000000000000000000000000000000000000000000000001337;
    bytes32 data1 = 0x0000000000000000000000000000000000000000000000000000000000000666;
    hdmap.set(key, meta1, data1);
  }
}
