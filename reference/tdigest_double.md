# t-Digest sketch for approximate quantiles of a numeric stream

Creates a [t-Digest](https://github.com/tdunning/t-digest) quantile
sketch over `double` values. A t-Digest is a compact, mergeable summary
that answers approximate quantile, rank, CDF, and PMF queries over a
stream far larger than memory. Compared to
[`kll_doubles()`](https://pedrobtz.github.io/data.sketches/reference/kll_doubles.md)
and
[`req()`](https://pedrobtz.github.io/data.sketches/reference/req.md), a
t-Digest concentrates its accuracy near the tails of the distribution
(extreme quantiles such as p99 or p99.9), at some cost to accuracy near
the median.

## Usage

``` r
tdigest_double(x = NULL, k = NULL, bytes = NULL)
```

## Arguments

- x:

  Optional numeric vector to update the new sketch with.

- k:

  Compression parameter controlling the accuracy/size trade-off, a whole
  number in `[10, 65535]`. Larger `k` is more accurate and larger.
  Defaults to `200` (resolved when a fresh sketch is built). Must not be
  set when `bytes` is supplied.

- bytes:

  Optional [raw](https://rdrr.io/r/base/raw.html) vector holding a
  native serialized sketch to reconstruct.

## Value

A `tdigest_double_sketch` object. Key methods:

- `$update(x)`:

  Add numeric values (mutates, returns the sketch).

- `$merge(other)`:

  Absorb another sketch (mutates, returns the sketch).

- `$quantile(probs)`:

  Approximate quantiles for probabilities in `[0, 1]`.

- `$rank(x)`:

  Approximate ranks of `x`; missing inputs return `NA`.

- `$cdf(split_points)` / `$pmf(split_points)`:

  Cumulative / mass estimates; return `length(split_points) + 1` values.

- `$n()`, `$k()`, `$is_empty()`, `$min()`, `$max()`:

  Metadata accessors.

- `$summary()`, `$inspect()`, `$serialize()`:

  Structured metadata, verbose debug output, and the native byte
  payload.

## Details

At most one of `x` or `bytes` may be supplied:

- Pass `x` to build a sketch and immediately update it with a numeric
  vector.

- Pass `bytes` to reconstruct a sketch from a native serialized payload
  (as produced by `sketch$serialize()`). The width is restored from the
  payload, so `k` must not be supplied alongside `bytes`.

- Pass neither for an empty sketch of width `k`.

[`update()`](https://rdrr.io/r/stats/update.html) silently ignores
`NA`/`NaN`, matching the upstream/Python behaviour; there is no `na_rm`
argument.

Unlike
[`kll_doubles()`](https://pedrobtz.github.io/data.sketches/reference/kll_doubles.md)
and
[`req()`](https://pedrobtz.github.io/data.sketches/reference/req.md),
`$quantile()` and `$rank()` have no `inclusive` argument, and there is
no `$rank_error()` accuracy accessor.

## Examples

``` r
sketch <- tdigest_double(rnorm(10000))
sketch$quantile(c(0.5, 0.99, 0.999))
#> [1] 0.02333156 2.31334826 3.01917129
sketch$rank(c(-1, 0, 1))
#> [1] 0.1605379 0.5004536 0.8412543

# Round-trip through the native byte format.
restored <- tdigest_double(bytes = sketch$serialize())
identical(restored$quantile(0.5), sketch$quantile(0.5))
#> [1] TRUE
```
