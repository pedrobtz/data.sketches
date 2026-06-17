# Suggest Bloom filter sizing parameters

Helpers that translate a target accuracy into Bloom filter constructor
arguments for the `num_bits`/`num_hashes` sizing strategy. These compute
the same values that
[`bloom_filter()`](https://pedrobtz.github.io/data.sketches/reference/bloom_filter.md)
uses internally for the `max_items`/`fpp` sizing strategy, for callers
who want to inspect or reuse them (for example, to create multiple
compatible filters with an explicit `seed`).

## Usage

``` r
bloom_filter_suggest_num_filter_bits(max_items, fpp)

bloom_filter_suggest_num_hashes(max_items, num_bits)
```

## Arguments

- max_items:

  Target maximum number of distinct items, a single positive whole
  number up to `2^53`.

- fpp:

  Target false-positive probability, a single number in `(0, 1]`.

- num_bits:

  Number of bits in the filter, a single positive whole number up to
  `2^53`.

## Value

A single number: `bloom_filter_suggest_num_filter_bits()` returns the
suggested `num_bits` (a double, which may exceed
`.Machine$integer.max`); `bloom_filter_suggest_num_hashes()` returns the
suggested `num_hashes` (an integer).

## Examples

``` r
num_bits <- bloom_filter_suggest_num_filter_bits(1000, 0.01)
num_hashes <- bloom_filter_suggest_num_hashes(1000, num_bits)
bf <- bloom_filter(num_bits = num_bits, num_hashes = num_hashes)
```
