# CPC sketch for approximate distinct counting

Creates a
[CPC](https://datasketches.apache.org/docs/CPC/CpcSketches.html)
(Compressed Probabilistic Counting) sketch, a very compact, mergeable
summary that estimates the number of distinct values seen in a stream
far larger than memory. CPC sketches are similar in purpose to
[`hll()`](https://pedrobtz.github.io/data.sketches/reference/hll.md) but
serialize to a smaller payload, at the cost of slightly higher CPU use.

## Usage

``` r
cpc(x = NULL, lg_k = NULL, seed = NULL, bytes = NULL)
```

## Arguments

- x:

  Optional numeric or character vector to update the new sketch with.
  Each element is hashed and contributes to the distinct-count estimate.

- lg_k:

  log2 of the number of bins, a single whole number in `[4, 26]`. Larger
  `lg_k` is more accurate and larger. Defaults to `11` (resolved when a
  fresh sketch is built). Must not be set when `bytes` is supplied.

- seed:

  Hash seed, a single non-negative whole number up to `2^53`. Defaults
  to `9001` (the upstream default), resolved whether or not `bytes` is
  supplied.

- bytes:

  Optional [raw](https://rdrr.io/r/base/raw.html) vector holding a
  native serialized sketch to reconstruct.

## Value

A `cpc_sketch` object. Key methods:

- `$update(x)`:

  Add numeric or character values (mutates, returns the sketch).

- `$merge(other)`:

  Absorb another sketch with the same `seed` (mutates, returns the
  sketch).

- `$estimate()`:

  Approximate number of distinct values seen.

- `$lower_bound(num_std_dev = 1)` / `$upper_bound(num_std_dev = 1)`:

  Approximate confidence bounds on `estimate()`, at 1, 2, or 3 standard
  deviations.

- `$lg_k()`, `$seed()`, `$is_empty()`:

  Metadata accessors.

- `$summary()`, `$inspect()`, `$serialize()`:

  Structured metadata, verbose debug output, and the native byte
  payload.

## Details

At most one of `x` or `bytes` may be supplied:

- Pass `x` to build a sketch and immediately update it with a numeric or
  character vector.

- Pass `bytes` to reconstruct a sketch from a native serialized payload
  (as produced by `sketch$serialize()`). `lg_k` is restored from the
  payload and must not be supplied alongside `bytes`. Unlike `lg_k`, the
  hash `seed` is *not* stored in the payload and must be supplied if the
  original sketch did not use the default.

- Pass neither for an empty sketch with the given `lg_k` and `seed`.

[`update()`](https://rdrr.io/r/stats/update.html) silently ignores
`NA`/`NaN`/`NA_character_`, matching the missing-value policy used
across families; there is no `na_rm` argument.

Two sketches can only be merged with `$merge()` if they share the same
`seed`; a mismatch raises `datasketches_seed_mismatch`.

## Examples

``` r
sketch <- cpc(sample(1000, 5000, replace = TRUE))
sketch$estimate()
#> [1] 1006.158
sketch$lower_bound()
#> [1] 993.2329
sketch$upper_bound()
#> [1] 1020

# Round-trip through the native byte format.
restored <- cpc(bytes = sketch$serialize())
identical(restored$estimate(), sketch$estimate())
#> [1] TRUE
```
