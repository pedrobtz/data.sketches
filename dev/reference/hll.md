# HLL sketch for approximate distinct counting

Creates an
[HLL](https://datasketches.apache.org/docs/HLL/HllSketches.html)
(HyperLogLog) sketch, a compact, mergeable summary that estimates the
number of distinct values seen in a stream far larger than memory.

## Usage

``` r
hll(x = NULL, lg_k = NULL, type = NULL, bytes = NULL)
```

## Arguments

- x:

  Optional numeric or character vector to update the new sketch with.
  Each element is hashed and contributes to the distinct-count estimate.

- lg_k:

  log2 of the number of buckets, a single whole number in `[4, 21]`.
  Larger `lg_k` is more accurate and larger. Defaults to `12` (resolved
  when a fresh sketch is built). Must not be set when `bytes` is
  supplied.

- type:

  One of `"HLL_4"`, `"HLL_6"`, or `"HLL_8"`, controlling the per-bucket
  encoding width (a size/speed trade-off that does not affect accuracy).
  Defaults to `"HLL_4"` (resolved when a fresh sketch is built). Must
  not be set when `bytes` is supplied.

- bytes:

  Optional [raw](https://rdrr.io/r/base/raw.html) vector holding a
  native serialized sketch to reconstruct.

## Value

An `hll_sketch` object. Key methods:

- `$update(x)`:

  Add numeric or character values (mutates, returns the sketch).

- `$merge(other)`:

  Absorb another sketch (mutates, returns the sketch).

- `$estimate()`:

  Approximate number of distinct values seen.

- `$lower_bound(num_std_dev = 1)` / `$upper_bound(num_std_dev = 1)`:

  Approximate confidence bounds on `estimate()`, at 1, 2, or 3 standard
  deviations.

- `$lg_k()`, `$hll_type()`, `$is_empty()`, `$is_compact()`:

  Metadata accessors.

- `$summary()`, `$inspect()`, `$serialize()`:

  Structured metadata, verbose debug output, and the native byte
  payload.

## Details

At most one of `x` or `bytes` may be supplied:

- Pass `x` to build a sketch and immediately update it with a numeric or
  character vector.

- Pass `bytes` to reconstruct a sketch from a native serialized payload
  (as produced by `sketch$serialize()`). Configuration is restored from
  the payload, so `lg_k` and `type` must not be supplied alongside
  `bytes`.

- Pass neither for an empty sketch with the given `lg_k` and `type`.

[`update()`](https://rdrr.io/r/stats/update.html) silently ignores
`NA`/`NaN`/`NA_character_`, matching the missing-value policy used
across families; there is no `na_rm` argument.

## Examples

``` r
sketch <- hll(sample(1000, 5000, replace = TRUE))
sketch$estimate()
#> [1] 996.1926
sketch$lower_bound()
#> [1] 983.4702
sketch$upper_bound()
#> [1] 1009.232

# Round-trip through the native byte format.
restored <- hll(bytes = sketch$serialize())
identical(restored$estimate(), sketch$estimate())
#> [1] TRUE
```
