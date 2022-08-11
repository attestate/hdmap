# hdmap

> Hdmap as in Harberger dmap

```
 dmap.sol
┌────────────────────────────────────────────────┐
│                                                │
│ keys              meta              data       │
│                                                │
│ 0x000...00  ───►  0xabc...00  ───►  0xcafecafe │
│ 0x000...01                                     │
│ ...                                            │
│ 0x111...11  ───►  0x00000001  ───►  0xf0rd0000 │
│                                                │
└────────────────────────────────────────────────┘

   ┌───┐
   │   │  ┌───┐             Depreciating licenses
   │   │  │   │  ┌───┐
   │   │  │   │  │   │  ┌───┐
   │   │  │   │  │   │  │   │  ┌───┐
 ──┴───┴──┴───┴──┴───┴──┴───┴──┴───┴──────────────

    #1  ─► #2  ─► #3  ─► #4  ─► #5

 ─────────────────────────────────────────────────

  Process:

  1. Register a name space identifier for your
     organization: e.g. "maker".

  2. A `SimpleNameZone` is deployed when you call
     `assess(bytes32("maker"))`. SALSA-rules apply!

  3. Stow some keys (and lock them) e.g.
     "maker:dai"

  4. Make sure you continously self-assess your
     namezone's property value! It's "partial
     common ownership" and can be bought by
     others!
```

## description

- Hdmap implements a Harberger tax as deprecating licenses for a
  [dmap](https://github.com/dapphub/dmap)
  [zonefab](https://github.com/dmfxyz/zonefab).
- An sub-namezone owner can permanently or temporarly lock key value pairs.
  But write-access is permanently auctioned via [depreciating
  licenses](https://anthonyleezhang.github.io/pdfs/dl.pdf).
- The tax is calculated on a per-block basis.
- The tax rate is 1/1908000/block. The denominator (1908000) represents the
  number of blocks Ethereum targets to produce in a year (given 12 second block
  target). Practically, means that a self-assessed key worth 1 ether will
  accumulate a tax obligation of 1 ether/year.
- Whenever a sub-namezone is transferred via `function give(...)`, the
  `recipient` assumes the tax obligation.
- All captured Harberger taxes are sent to Ethereum miners. Hdmap is an
  "Ethereum upgrade" and, hence, different from the many "protocols" issuing
  their own tokens or implementing egoistical rent-seeking.

## tests

always run foundry as a mainnet fork using the `-f` option

```shell
foundry test -f <json rpc endpoint url>
```
