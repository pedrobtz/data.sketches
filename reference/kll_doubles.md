# KLL sketch for approximate quantiles of a numeric stream

Creates a [KLL](https://datasketches.apache.org/docs/KLL/KLLSketch.html)
quantile sketch over `double` values. A KLL sketch is a compact,
mergeable summary that answers approximate quantile, rank, CDF, and PMF
queries over a stream far larger than memory, with a configurable
accuracy/size trade-off controlled by `k`.

## Usage

``` r
kll_doubles(x = NULL, k = NULL, bytes = NULL)
```

## Arguments

- x:

  Optional numeric vector to update the new sketch with.

- k:

  Sketch width controlling the accuracy/size trade-off, a whole number
  in `[8, 65535]`. Larger `k` is more accurate and larger. Defaults to
  `200` (resolved when a fresh sketch is built). Must not be set when
  `bytes` is supplied.

- bytes:

  Optional [raw](https://rdrr.io/r/base/raw.html) vector holding a
  native serialized sketch to reconstruct.

## Value

A `kll_doubles_sketch` object. Key methods:

- `$update(x)`:

  Add numeric values (mutates, returns the sketch).

- `$merge(other)`:

  Absorb another sketch (mutates, returns the sketch).

- `$quantile(probs, inclusive = TRUE)`:

  Approximate quantiles for probabilities in `[0, 1]`.

- `$rank(x, inclusive = TRUE)`:

  Approximate ranks of `x`; missing inputs return `NA`.

- `$cdf(split_points)` / `$pmf(split_points)`:

  Cumulative / mass estimates; return `length(split_points) + 1` values.

- `$n()`, `$k()`, `$num_retained()`, `$is_empty()`,
  `$is_estimation_mode()`, `$min()`, `$max()`,
  `$rank_error(pmf = FALSE)`:

  Metadata and accuracy accessors.

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

## Examples

``` r
sketch <- kll_doubles(rnorm(10000))
sketch$quantile(c(0.25, 0.5, 0.75))
#> [1] -0.65111385  0.01117251  0.67973491
sketch$rank(c(-1, 0, 1))
#> [1] 0.1565 0.4964 0.8370

# Round-trip through the native byte format.
restored <- kll_doubles(bytes = sketch$serialize())
identical(restored$quantile(0.5), sketch$quantile(0.5))
#> [1] TRUE
```
