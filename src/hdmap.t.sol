/// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.6;

import "forge-std/Test.sol";

import { Dmap } from './dmap.sol';
import { RootZone } from './root.sol';
import { SimpleNameZoneFactory, SimpleNameZone } from "zonefab/SimpleNameZone.sol";
import { Hdmap, Deed } from "./hdmap.sol";

contract Assesser {
  function assess(Hdmap hdmap, bytes32 key) external payable {
    hdmap.assess{value: msg.value}(key);
  }

  function stow(Hdmap hdmap, bytes32 org, bytes32 key, bytes32 meta, bytes32 data) external {
    hdmap.stow(org, key, meta, data);
  }
}

contract CensorAssesser is Assesser {
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
    hdmap.assess{value: 1}(key);
  }
}

contract BeneficiaryReentry is Assesser, Reentry {}

contract HdmapTest is Test {
  // Address of publicly deployed dmap
  address dmapAddress = 0x90949c9937A11BA943C7A72C3FA073a37E3FdD96;
  address rootAddress = 0x022ea9ba506E38eF6093b6AB53e48bbD60f86832;
  address zonefabAddress = 0xa964133B1d5b3FF1c4473Ad19bE37b6E2AaDE62b;

  Dmap dmap;
  SimpleNameZoneFactory zonefab;
  Hdmap hdmap;
  RootZone rz;
  bytes32 commitment;

  event Give(
    address indexed giver,
    bytes32 indexed zone,
    address indexed recipient
  );

  receive() external payable {}

  function setUp() public {
    dmap = Dmap(dmapAddress);
    zonefab = SimpleNameZoneFactory(zonefabAddress);
    hdmap = new Hdmap(dmap, zonefab);

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
    (, bytes32 data) = dmap.get(slot);
    assertEq(data, bytes32(bytes20(address(hdmap))));
  }

  function testConstants() public {
    assertTrue(hdmap.denominator() == 0x271C80);
  }

  function testIfBeneficiaryRentrancyIsGuarded() public {
    bytes32 key = 0x0000000000000000000000000000000000000000000000000000000000001337;
    uint256 value = 1;
    hdmap.assess{value: value}(key);

    BeneficiaryReentry br = new BeneficiaryReentry();
    vm.etch(block.coinbase, address(br).code);
    assertEq(block.coinbase.code, address(br).code);
    br.assess{value: 2}(hdmap, key);

    bytes32 reentryKey = 0x0000000000000000000000000000000000000000000000000000000000000666;
    (address controller, uint256 collateral, uint256 startBlock) = hdmap.deeds(reentryKey);
    assertEq(controller, address(0));
    assertEq(collateral, 0);
    assertEq(startBlock, 0);
  }

  function testIfCoinbaseRentrancyIsGuarded() public {
    bytes32 key = 0x0000000000000000000000000000000000000000000000000000000000001337;
    uint256 value = 1;
    hdmap.assess{value: value}(key);

    Reentry reentry = new Reentry();
    vm.etch(block.coinbase, address(reentry).code);
    assertEq(block.coinbase.code, address(reentry).code);
    hdmap.assess{value: 2}(key);

    bytes32 reentryKey = 0x0000000000000000000000000000000000000000000000000000000000000666;
    (address controller, uint256 collateral, uint256 startBlock) = hdmap.deeds(reentryKey);
    assertEq(controller, address(0));
    assertEq(collateral, 0);
    assertEq(startBlock, 0);
  }

  function testToMakeSureThatBeneficiaryCannotCensorAssess() public {
    bytes32 key = 0x0000000000000000000000000000000000000000000000000000000000001337;
    uint256 value = 1;
    hdmap.assess{value: value}(key);

    Censor censor = new Censor();
    vm.etch(block.coinbase, address(censor).code);
    assertEq(block.coinbase.code, address(censor).code);
    CensorAssesser ca = new CensorAssesser();
    ca.assess{value: 2}(hdmap, key);
  }

  function testToMakeSureThatCoinbaseCannotCensorAssess() public {
    bytes32 key = 0x0000000000000000000000000000000000000000000000000000000000001337;
    uint256 value = 1;
    hdmap.assess{value: value}(key);

    Censor censor = new Censor();
    vm.etch(block.coinbase, address(censor).code);
    assertEq(block.coinbase.code, address(censor).code);
    hdmap.assess{value: 2}(key);
  }

  function testEmptyLookup() public {
    bytes32 key = 0x0000000000000000000000000000000000000000000000000000000000001337;
    address org = hdmap.lookup(key);
    assertEq(org, address(0));
  }

  function testLookup() public {
    bytes32 key = 0x0000000000000000000000000000000000000000000000000000000000001337;
    uint256 value = 1;
    hdmap.assess{value: value}(key);

    address org = hdmap.lookup(key);
    assertTrue(org != address(0));
  }

  function encodeZoneAndName(address zone, bytes32 name) public pure returns (bytes memory) {
    return abi.encode(zone, name);
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

  function testAssessForFree() public {
    bytes32 key = 0x0000000000000000000000000000000000000000000000000000000000001337;
    hdmap.assess{value: 0}(key);
  }

  function testReAssessForFree() public {
    bytes32 key = 0x0000000000000000000000000000000000000000000000000000000000001337;
    hdmap.assess{value: 0}(key);

    (uint256 price, uint256 taxes) = hdmap.fiscal(key);
    assertEq(price, 0);
    assertEq(taxes, 0);
    Assesser Assesser = new Assesser();
    Assesser.assess{value: 1}(hdmap, key);
  }

  function testAssess() public {
    bytes32 key = 0x0000000000000000000000000000000000000000000000000000000000001337;
    uint256 value = 1;
    uint256 currentBlock = block.number;
    vm.expectEmit(true, true, true, false);
    emit Give(address(0), key, address(this));
    hdmap.assess{value: value}(key);

    (address controller, uint256 collateral, uint256 startBlock) = hdmap.deeds(key);
    assertEq(controller, address(this));
    assertEq(collateral, value);
    assertEq(startBlock, currentBlock);
  }

  function testLoweringThePrice() public {
    bytes32 key = 0x0000000000000000000000000000000000000000000000000000000000001337;
    uint256 value = 1 ether;
    uint256 currentBlock = block.number;
    vm.expectEmit(true, true, true, false);
    emit Give(address(0), key, address(this));
    hdmap.assess{value: value}(key);

    (address controller0, uint256 collateral0, uint256 startBlock0) = hdmap.deeds(key);
    assertEq(controller0, address(this));
    assertEq(collateral0, value);
    assertEq(startBlock0, currentBlock);

    vm.roll(block.number+hdmap.denominator()/2);
    assertEq(block.number, currentBlock+hdmap.denominator()/2, "blocks must match");

    (uint256 nextPrice0, uint256 taxes0) = hdmap.fiscal(key);
    assertEq(nextPrice0, 0.5 ether, "price");
    assertEq(taxes0, 0.5 ether, "taxes");

    uint256 prevBalanceOwner = address(this).balance;
    uint256 prevBalanceCB = block.coinbase.balance;
    hdmap.assess{value: 0}(key);
    assertEq(prevBalanceOwner+0.5 ether, address(this).balance, "owner bal");
    assertEq(prevBalanceCB+0.5 ether, block.coinbase.balance, "cb bal");

    (address controller1, uint256 collateral1, uint256 startBlock1) = hdmap.deeds(key);
    assertEq(controller1, address(this));
    assertEq(collateral1, 0);
    assertEq(startBlock1, block.number);
  }

  function testLoweringThePriceAsExternalAssesser() public {
    bytes32 key = 0x0000000000000000000000000000000000000000000000000000000000001337;
    uint256 value = 1 ether;
    uint256 currentBlock = block.number;
    vm.expectEmit(true, true, true, false);
    emit Give(address(0), key, address(this));
    hdmap.assess{value: value}(key);

    (address controller0, uint256 collateral0, uint256 startBlock0) = hdmap.deeds(key);
    assertEq(controller0, address(this));
    assertEq(collateral0, value);
    assertEq(startBlock0, currentBlock);

    vm.roll(block.number+hdmap.denominator()/2);
    assertEq(block.number, currentBlock+hdmap.denominator()/2, "blocks must match");

    (uint256 nextPrice0, uint256 taxes0) = hdmap.fiscal(key);
    assertEq(nextPrice0, 0.5 ether, "price");
    assertEq(taxes0, 0.5 ether, "taxes");

    Assesser assesser = new Assesser();
    vm.expectRevert(Hdmap.ErrValue.selector);
    assesser.assess{value: 0}(hdmap, key);
  }

  function testReAssessForLowerPrice() public {
    bytes32 key = 0x0000000000000000000000000000000000000000000000000000000000001337;
    uint256 value = hdmap.denominator();
    uint256 currentBlock = block.number;
    hdmap.assess{value: value}(key);

    (address controller0, uint256 collateral0, uint256 startBlock0) = hdmap.deeds(key);
    assertEq(controller0, address(this));
    assertEq(collateral0, value);
    assertEq(startBlock0, currentBlock);

    vm.roll(block.number+1);

    (uint256 nextPrice1, uint256 taxes1) = hdmap.fiscal(key);
    assertEq(nextPrice1, collateral0-1);
    assertEq(taxes1, 1);

    Assesser assesser = new Assesser();
    vm.expectRevert(Hdmap.ErrValue.selector);
    assesser.assess{value: collateral0-2}(hdmap, key);
  }

  function testReAssess() public {
    bytes32 key = 0x0000000000000000000000000000000000000000000000000000000000001337;
    uint256 value = hdmap.denominator();
    uint256 currentBlock = block.number;
    hdmap.assess{value: value}(key);

    (address controller0, uint256 collateral0, uint256 startBlock0) = hdmap.deeds(key);
    assertEq(controller0, address(this));
    assertEq(collateral0, value);
    assertEq(startBlock0, currentBlock);

    vm.roll(block.number+1);

    (uint256 nextPrice1, uint256 taxes1) = hdmap.fiscal(key);
    assertEq(nextPrice1, collateral0-1);
    assertEq(taxes1, 1);

    Assesser assesser = new Assesser();
    uint256 balance0 = address(this).balance;
    vm.expectEmit(true, true, true, false);
    emit Give(address(this), key, address(assesser));
    assesser.assess{value: collateral0}(hdmap, key);
    uint256 balance1 = address(this).balance;
    assertEq(balance0 - balance1, 1);

    (address controller1, uint256 collateral1, uint256 startBlock1) = hdmap.deeds(key);
    assertEq(controller1, address(assesser));
    assertEq(collateral1, collateral0);
    assertEq(startBlock1, block.number);
  }

  function testCostAfterAYear() public {
    bytes32 key = 0x0000000000000000000000000000000000000000000000000000000000001337;
    uint256 value = 1 ether;
    uint256 currentBlock = block.number;
    hdmap.assess{value: value}(key);

    (address controller, uint256 collateral, uint256 startBlock) = hdmap.deeds(key);
    assertEq(controller, address(this));
    assertEq(collateral, value);
    assertEq(startBlock, currentBlock);

    (uint256 nextPrice0, uint256 taxes0) = hdmap.fiscal(key);
    assertEq(nextPrice0, collateral);
    assertEq(taxes0, 0);

    vm.roll(block.number+hdmap.denominator());

    (uint256 nextPrice1, uint256 taxes1) = hdmap.fiscal(key);
    assertEq(nextPrice1, 0);
    assertEq(taxes1, value);
  }

  function testFiscal() public {
    bytes32 key = 0x0000000000000000000000000000000000000000000000000000000000001337;
    uint256 value = hdmap.denominator();
    uint256 currentBlock = block.number;
    hdmap.assess{value: value}(key);

    (address controller, uint256 collateral, uint256 startBlock) = hdmap.deeds(key);
    assertEq(controller, address(this));
    assertEq(collateral, value);
    assertEq(startBlock, currentBlock);

    (uint256 nextPrice0, uint256 taxes0) = hdmap.fiscal(key);
    assertEq(nextPrice0, collateral);
    assertEq(taxes0, 0);

    vm.roll(block.number+1);

    (uint256 nextPrice1, uint256 taxes1) = hdmap.fiscal(key);
    assertEq(nextPrice1, collateral-1);
    assertEq(taxes1, 1);

    vm.roll(block.number+value-1);
    (uint256 nextPrice2, uint256 taxes2) = hdmap.fiscal(key);
    assertEq(nextPrice2, 0);
    assertEq(taxes2, value);
  }

  function testGive() public {
    bytes32 key = 0x0000000000000000000000000000000000000000000000000000000000001337;
    uint256 value = hdmap.denominator();
    uint256 currentBlock = block.number;
    hdmap.assess{value: value}(key);

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

  function testGiveToAddressZero() public {
    bytes32 key = 0x0000000000000000000000000000000000000000000000000000000000001337;
    uint256 value = hdmap.denominator();
    uint256 currentBlock = block.number;
    hdmap.assess{value: value}(key);

    (address controller0, uint256 collateral0, uint256 startBlock0) = hdmap.deeds(key);
    assertEq(controller0, address(this));
    assertEq(collateral0, value);
    assertEq(startBlock0, currentBlock);

    address recipient = address(0);
    vm.expectRevert(Hdmap.ErrRecipient.selector);
    hdmap.give(key, recipient);
  }

  function testStowNonExistent() public {
    bytes32 org = 0x0000000000000000000000000000000000000000000000000000000000001234;
    bytes32 key = 0x0000000000000000000000000000000000000000000000000000000000001337;
    bytes32 meta = 0x0000000000000000000000000000000000000000000000000000000000001330;
    bytes32 data = 0x0000000000000000000000000000000000000000000000000000000000001337;
    vm.expectRevert(Hdmap.ErrAuthorization.selector);
    hdmap.stow(org, key, meta, data);
  }

  function testStowWithoutPermission() public {
    bytes32 org = 0x0000000000000000000000000000000000000000000000000000000000001234;
    uint256 value = hdmap.denominator();
    hdmap.assess{value: value}(org);

    bytes32 key = 0x0000000000000000000000000000000000000000000000000000000000001337;
    bytes32 meta = 0x0000000000000000000000000000000000000000000000000000000000001330;
    bytes32 data = 0x0000000000000000000000000000000000000000000000000000000000001337;
    Assesser assesser = new Assesser();
    vm.expectRevert(Hdmap.ErrAuthorization.selector);
    assesser.stow(hdmap, org, key, meta, data);
  }

  function testLockedMeta() public {
    bytes32 meta0 = 0x0000000000000000000000000000000000000000000000000000000000000000;
    bool locked0;
    assembly {
      locked0 := and(meta0, 1)
    }
    assertFalse(locked0);

    bytes32 meta1 = 0x0000000000000000000000000000000000000000000000000000000000000001;
    bool locked1;
    assembly {
      locked1 := and(meta1, 1)
    }
    assertTrue(locked1);

    bytes32 meta2 = 0x0000000000000000000000000000000000000000000000000000000000000002;
    bool locked2;
    assembly {
      locked2 := and(meta2, 1)
    }
    assertFalse(locked2);
  }

  function testStow() public {
    bytes32 org = 0x0000000000000000000000000000000000000000000000000000000000001234;
    uint256 value = hdmap.denominator();
    hdmap.assess{value: value}(org);

    address zone = hdmap.lookup(org);
    assertTrue(zone != address(0));

    bytes32 key = 0x0000000000000000000000000000000000000000000000000000000000001337;
    bytes32 meta = 0x0000000000000000000000000000000000000000000000000000000000000010;
    bytes32 data = 0x0000000000000000000000000000000000000000000000000000000000001337;
    hdmap.stow(org, key, meta, data);

    (bytes32 actualMeta, bytes32 actualData) = hdmap.read(org, key);
    assertEq(actualMeta, meta);
    assertEq(actualData, data);
  }

  function testStowOnEmptyOrg() public {
    bytes32 org = 0x0000000000000000000000000000000000000000000000000000000000001234;
    bytes32 key = 0x0000000000000000000000000000000000000000000000000000000000001337;
    bytes32 meta = 0x0000000000000000000000000000000000000000000000000000000000000010;
    bytes32 data = 0x0000000000000000000000000000000000000000000000000000000000001337;
    vm.expectRevert(Hdmap.ErrAuthorization.selector);
    hdmap.stow(org, key, meta, data);
  }
}
