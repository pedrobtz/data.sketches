# EBPPS sketch for proportional-to-size sampling

Creates an
[EBPPS](https://datasketches.apache.org/docs/Sampling/EB-PPS_SamplingSketches.html)
(Exact and Bounded Probabilistic Proportional-to-Size) sketch, which
samples up to `k` items from a stream of weighted (item, weight) pairs.
It is a modern alternative to classic reservoir sampling: each item's
inclusion probability is proportional to its share of the total stream
weight, with a tight bound on the resulting sample size.

## Usage

``` r
ebpps(x = NULL, weight = NULL, k = NULL, type = NULL, bytes = NULL)
```

## Arguments

- x:

  Optional numeric or character vector of items to update the new sketch
  with.

- weight:

  Optional weight(s) for each element of `x`: a single non-negative,
  finite number, or a vector of such values matching `length(x)`.
  Defaults to `1`. Cannot be set without `x`.

- k:

  Maximum sample size, a single whole number in `[1, 2^31 - 2]`.
  Defaults to `256`. Must not be set when `bytes` is supplied.

- type:

  Item type for a fresh sketch, either `"double"` or `"character"`.
  Defaults to the type of `x` (or `"double"` if `x` is not supplied).
  Must not be set when `bytes` is supplied.

- bytes:

  Optional [raw](https://rdrr.io/r/base/raw.html) vector holding a
  native serialized sketch to reconstruct.

## Value

An `ebpps_sketch` object. Key methods:

- `$update(x, weight = NULL)`:

  Add weighted items (mutates, returns the sketch).

- `$merge(other)`:

  Absorb another sketch with the same item type (mutates, returns the
  sketch).

- `$result()`:

  The current sample as a numeric or character vector.

- `$k()`, `$n()`, `$cumulative_weight()`, `$c()`, `$is_empty()`,
  `$is_character()`:

  Metadata accessors.

- `$summary()`, `$inspect()`, `$serialize()`:

  Structured metadata, verbose debug output, and the native byte
  payload.

## Details

Unlike the hash-based cardinality and frequency sketches, EBPPS retains
items verbatim rather than hashing them, so the item type (numeric or
character) is fixed when the sketch is created and cannot change.

At most one of `x` or `bytes` may be supplied:

- Pass `x` to build a sketch and immediately update it with a numeric or
  character vector of items (optionally with `weight`). The item type is
  inferred from `x` unless `type` is supplied.

- Pass `bytes` to reconstruct a sketch from a native serialized payload
  (as produced by `sketch$serialize()`). `weight`, `k`, and `type` must
  not be supplied alongside `bytes`; they are restored from the payload.

- Pass neither for an empty (mutable) sketch with the given `k` and
  `type`.

[`update()`](https://rdrr.io/r/stats/update.html) silently ignores
`NA`/`NaN`/`NA_character_` in `x` (and the corresponding `weight`),
matching the missing-value policy used across families; there is no
`na_rm` argument.

Two sketches can only be merged with `$merge()` if they hold the same
item type (a mismatch raises `datasketches_incompatible_sketch`). The
merged sketch is resized to the smaller of the two inputs' configured
`k`, matching the native implementation.

## Examples

``` r
items <- 1:1000
weights <- runif(1000)
sketch <- ebpps(items, weights, k = 50)
sketch$result()
#>  [1] 815 284 800 418 117  90 929 387 498 462 512 900 344   9 402 954 940 310  30
#> [20] 828 413 158 137   1 566 308 178 961 877  97 594 245 149 721 336 914 295  95
#> [39] 928 277 135 142 578 112 192 849 354 769 472 884
sketch$c()
#> [1] 50

# Round-trip through the native byte format.
restored <- ebpps(bytes = sketch$serialize())
restored$k()
#> [1] 50
```
