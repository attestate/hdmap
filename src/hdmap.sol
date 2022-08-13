/// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.13;

import { Dmap } from './dmap.sol';
import {
  SimpleNameZone,
  SimpleNameZoneFactory
} from "zonefab/SimpleNameZone.sol";
import { Harberger, Perwei } from "./Harberger.sol";
import { ReentrancyGuard } from "./ReentrancyGuard.sol";

uint256 constant avgEthereumBlockTimeSeconds = 12 seconds;
uint256 constant daySeconds = 86400 seconds;
uint256 constant dayBlocks = daySeconds / avgEthereumBlockTimeSeconds;
uint256 constant yearDays = 356;
uint256 constant yearBlocks = dayBlocks * yearDays;

struct Deed {
  address controller;
  uint256 collateral;
  uint256 startBlock;
}

// Hdmap as in Harberger dmap
contract Hdmap is ReentrancyGuard {
  Dmap                      public immutable dmap;
  SimpleNameZoneFactory     public immutable zonefab;
  mapping(bytes32=>Deed)    public           deeds;
  uint256                   public immutable numerator    = 1;
  uint256                   public immutable denominator  = yearBlocks;
  bytes32                          immutable LOCK         = bytes32(uint(0x1));

  error ErrValue();
  error ErrAuthorization();

  event Give(
    address indexed giver,
    bytes32 indexed zone,
    address indexed recipient
  );

  constructor(Dmap d, SimpleNameZoneFactory z) {
    dmap = d;
    zonefab = z;
  }

  function fiscal(
    bytes32 org
  ) external view returns (uint256 nextPrice, uint256 taxes) {
    Deed memory deed = deeds[org];
    return Harberger.getNextPrice(
      Perwei(numerator, denominator),
      block.number - deed.startBlock,
      deed.collateral
    );
  }

  function assess(bytes32 org) nonReentrant external payable {
    Deed memory deed = deeds[org];
    if (deed.controller == address(0)) {
      deed.collateral = msg.value;
      deed.controller = msg.sender;
      deed.startBlock = block.number;
      deeds[org] = deed;
      dmap.set(org, LOCK, bytes32(bytes20(address(zonefab.make()))));
      emit Give(address(0), org, msg.sender);
    } else {
      (uint256 nextPrice, uint256 taxes) = Harberger.getNextPrice(
        Perwei(numerator, denominator),
        block.number - deed.startBlock,
        deed.collateral
      );

      if (msg.value < nextPrice && deed.controller != msg.sender) {
        revert ErrValue();
      }

      address beneficiary = deed.controller;
      deed.collateral = msg.value;
      deed.controller = msg.sender;
      deed.startBlock = block.number;
      deeds[org] = deed;

      // NOTE: Stakers and beneficiaries must not control the finalization of
      // this function, hence, we're not checking for the calls' success.
      // DONATIONS: Consider donating to dmap://:free.timdaub to help
      // compensate for deployment costs.
      block.coinbase.call{value: taxes}("");
      beneficiary.call{value: nextPrice}("");
      emit Give(beneficiary, org, msg.sender);
    }
  }

  function give(bytes32 org, address recipient) external {
    if (deeds[org].controller != msg.sender) revert ErrAuthorization();
    deeds[org].controller = recipient;
    emit Give(msg.sender, org, recipient);
  }

  function lookup(bytes32 org) public view returns (address zone) {
    bytes32 slot = keccak256(abi.encode(address(this), org));
    (, bytes32 data) = dmap.get(slot);
    return address(bytes20(data));
  }

  function read(
    bytes32 org,
    bytes32 key
  ) public view returns (bytes32 meta, bytes32 data) {
    address zone = lookup(org);
    bytes32 slot = keccak256(abi.encode(zone, key));
    return dmap.get(slot);
  }

  function stow(bytes32 org, bytes32 key, bytes32 meta, bytes32 data) external {
    if (deeds[org].controller != msg.sender) revert ErrAuthorization();
    SimpleNameZone z = SimpleNameZone(lookup(org));
    z.stow(key, meta, data);
  }
}
