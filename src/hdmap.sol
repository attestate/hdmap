/// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.13;

import { Dmap } from './dmap.sol';
import { Harberger, Period, Perwei } from "./Harberger.sol";
import { ReentrancyGuard } from "./ReentrancyGuard.sol";

uint256 constant avgEthereumBlockTimeSeconds = 12 seconds;
uint256 constant daySeconds = 86400 seconds;
uint256 constant dayBlocks = daySeconds / avgEthereumBlockTimeSeconds;
uint256 constant yearDays = 356 days;
uint256 constant yearBlocks = dayBlocks * yearDays;

struct Deed {
  address controller;
  uint256 collateral;
  uint256 startBlock;
}

// Hdmap as in Harberger dmap
contract Hdmap is ReentrancyGuard {
  Dmap                      public immutable dmap;
  mapping(bytes32=>Deed)    public           deeds;
  uint256                   public immutable numerator = 1;
  uint256                   public immutable denominator = yearBlocks;

  event Give(
    address indexed giver,
    bytes32 indexed zone,
    address indexed recipient
  );

  constructor(Dmap d) {
    dmap = d;
  }

  function status(
    bytes32 key
  ) external view returns (uint256 nextPrice, uint256 taxes) {
    Deed memory deed = deeds[key];
    Period memory period = Period(deed.startBlock, block.number);
    return Harberger.getNextPrice(
      Perwei(numerator, denominator),
      period,
      deed.collateral
    );
  }

  function take(bytes32 key) nonReentrant external payable {
    require(msg.value != 0, "ERR_MSG_VALUE");

    Deed memory deed = deeds[key];
    if (deed.controller == address(0)) {
      deed.collateral = msg.value;
      deed.controller = msg.sender;
      deed.startBlock = block.number;
      deeds[key] = deed;
      emit Give(address(0), key, msg.sender);
    } else {
      Period memory period = Period(deed.startBlock, block.number);
      (uint256 nextPrice, uint256 taxes) = Harberger.getNextPrice(
        Perwei(numerator, denominator),
        period,
        deed.collateral
      );
      require(msg.value >= nextPrice, "ERR_VAL");

      address beneficiary = deed.controller;
      deed.collateral = msg.value;
      deed.controller = msg.sender;
      deed.startBlock = block.number;
      deeds[key] = deed;

      // NOTE: Stakers and beneficiaries must not control the finalization of
      // this function, hence, we're not checking for the calls' success.
      // DONATIONS: Consider donating to timdaub.eth to help compensate for
      // deployment costs.
      block.coinbase.call{value: taxes}("");
      beneficiary.call{value: nextPrice}("");
      emit Give(beneficiary, key, msg.sender);
    }
  }

  function give(bytes32 key, address recipient) external {
    require(deeds[key].controller == msg.sender, "ERR_OWNER");
    deeds[key].controller = recipient;
    emit Give(msg.sender, key, recipient);
  }

  function set(bytes32 key, bytes32 meta, bytes32 data) external {
    require(deeds[key].controller == msg.sender, "ERR_OWNER");
    dmap.set(key, meta, data);
  }
}
