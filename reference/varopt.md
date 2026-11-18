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

  Optional weight(s) for each element of `x`: a single positive, finite
  number, or a vector of such values matching `length(x)`. Defaults to
  `1`. Cannot be set without `x`.

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
#> 1   771 10.38281
#> 2   376 10.38281
#> 3   290 10.38281
#> 4   924 10.38281
#> 5   563 10.38281
#> 6   103 10.38281
#> 7   534 10.38281
#> 8   881 10.38281
#> 9    50 10.38281
#> 10  521 10.38281
#> 11  858 10.38281
#> 12  995 10.38281
#> 13  170 10.38281
#> 14   80 10.38281
#> 15  443 10.38281
#> 16   16 10.38281
#> 17  273 10.38281
#> 18  450 10.38281
#> 19  798 10.38281
#> 20  512 10.38281
#> 21  856 10.38281
#> 22   74 10.38281
#> 23  757 10.38281
#> 24  594 10.38281
#> 25  210 10.38281
#> 26  549 10.38281
#> 27  912 10.38281
#> 28  845 10.38281
#> 29  837 10.38281
#> 30  764 10.38281
#> 31  815 10.38281
#> 32  811 10.38281
#> 33  275 10.38281
#> 34  203 10.38281
#> 35  134 10.38281
#> 36  144 10.38281
#> 37  820 10.38281
#> 38  874 10.38281
#> 39   58 10.38281
#> 40  371 10.38281
#> 41   22 10.38281
#> 42  551 10.38281
#> 43  453 10.38281
#> 44  231 10.38281
#> 45  695 10.38281
#> 46  168 10.38281
#> 47  202 10.38281
#> 48  207 10.38281
#> 49  930 10.38281
#> 50  396 10.38281
sketch$estimate_subset_sum(\(x) x <= 500)
#> $lower_bound
#> [1] 184.7918
#> 
#> $estimate
#> [1] 259.5702
#> 
#> $upper_bound
#> [1] 334.3485
#> 
#> $total_weight
#> [1] 519.1403
#> 

# Round-trip through the native byte format.
restored <- varopt(bytes = sketch$serialize())
identical(restored$samples(), sketch$samples())
#> [1] TRUE
```
