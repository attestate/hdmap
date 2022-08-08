# hdmap

> Hdmap as in Harberger dmap

## description

- Hdmap implements a Harberger tax as depricating licenses for `bytes32` dmap
  keys.
- The tax is calculated on a per-block basis.
- The tax rate is 1/1908000/block. The denumerator (1908000) represents the
  number of blocks Ethereum targets to produce in a year (given 12 second block
  target). Practically, means that a self-assessed key worth 1 ether will
  accumulate a tax obligation of 1 ether/year.
- dmap keys can be transferred and it means the `recipient` assumes the tax
  obligation.
- All captured Harberger taxes are sent to Ethereum miners. Hdmap is an
  "Ethereum upgrade" and, hence, very different from the many "protocols"
  issuing their own tokens or implementing egoistical rent-seeking.

## tests

always run foundry as a mainnet fork using the `-f` option

```shell
foundry test -f <json rpc endpoint url>
```
