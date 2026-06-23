# VarOpt sketch for variance-optimal sampling and subset-sum estimation

Creates a
[VarOpt](https://datasketches.apache.org/docs/Sampling/VarOptSamplingSketches.html)
sketch, which samples up to `k` items from a stream of weighted (item,
weight) pairs. It is designed for minimum-variance estimation of subset
sums: `$estimate_subset_sum()` estimates the total weight of all stream
items matching a predicate, using only the retained sample.

## Usage

``` r
varopt(x = NULL, weight = NULL, k = NULL, type = NULL, bytes = NULL)
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

A `varopt_sketch` object. Key methods:

- `$update(x, weight = NULL)`:

  Add weighted items (mutates, returns the sketch).

- `$merge(other)`:

  Absorb another sketch with the same item type (mutates, returns the
  sketch).

- `$samples()`:

  A data frame of retained items and their estimated weights.

- `$estimate_subset_sum(predicate)`:

  Estimated total weight of stream items matching `predicate`, with
  `lower_bound` and `upper_bound`.

- `$k()`, `$n()`, `$num_samples()`, `$is_empty()`, `$is_character()`:

  Metadata accessors.

- `$summary()`, `$inspect()`, `$serialize()`:

  Structured metadata, verbose debug output, and the native byte
  payload.

## Details

Unlike the hash-based cardinality and frequency sketches, VarOpt retains
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

Two sketches can only be merged with `$merge()`, or combined with
[`varopt_union()`](https://pedrobtz.github.io/data.sketches/reference/varopt_union.md),
if they hold the same item type (a mismatch raises
`datasketches_incompatible_sketch`). Both operations resize the result
for the larger of the two inputs' configured `k`.

## Examples

``` r
items <- 1:1000
weights <- runif(1000)
sketch <- varopt(items, weights, k = 50)
sketch$samples()
#>    item   weight
#> 1   994 10.38281
#> 2   767 10.38281
#> 3   142 10.38281
#> 4   497 10.38281
#> 5   153 10.38281
#> 6   261 10.38281
#> 7   208 10.38281
#> 8   682 10.38281
#> 9   632 10.38281
#> 10  690 10.38281
#> 11  453 10.38281
#> 12  772 10.38281
#> 13  894 10.38281
#> 14  833 10.38281
#> 15  829 10.38281
#> 16  932 10.38281
#> 17   64 10.38281
#> 18  800 10.38281
#> 19  846 10.38281
#> 20  250 10.38281
#> 21  170 10.38281
#> 22  589 10.38281
#> 23  326 10.38281
#> 24  365 10.38281
#> 25  280 10.38281
#> 26  112 10.38281
#> 27  569 10.38281
#> 28  731 10.38281
#> 29  790 10.38281
#> 30  530 10.38281
#> 31  815 10.38281
#> 32  366 10.38281
#> 33  960 10.38281
#> 34  912 10.38281
#> 35   97 10.38281
#> 36  269 10.38281
#> 37  237 10.38281
#> 38  465 10.38281
#> 39  131 10.38281
#> 40  864 10.38281
#> 41  144 10.38281
#> 42  210 10.38281
#> 43  808 10.38281
#> 44  410 10.38281
#> 45  246 10.38281
#> 46  585 10.38281
#> 47  331 10.38281
#> 48  821 10.38281
#> 49  248 10.38281
#> 50  235 10.38281
sketch$estimate_subset_sum(\(x) x <= 500)
#> $lower_bound
#> [1] 194.6004
#> 
#> $estimate
#> [1] 269.953
#> 
#> $upper_bound
#> [1] 344.0484
#> 
#> $total_weight
#> [1] 519.1403
#> 

# Round-trip through the native byte format.
restored <- varopt(bytes = sketch$serialize())
identical(restored$samples(), sketch$samples())
#> [1] TRUE
```
