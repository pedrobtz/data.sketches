# REQ sketch for relative-error approximate quantiles of a numeric stream

Creates a [REQ](https://datasketches.apache.org/docs/REQ/ReqSketch.html)
(Relative Error Quantiles) sketch over `double` values. Like
[`kll_doubles()`](https://pedrobtz.github.io/data.sketches/reference/kll_doubles.md),
a REQ sketch is a compact, mergeable summary that answers approximate
quantile, rank, CDF, and PMF queries over a stream far larger than
memory. Unlike KLL, REQ's accuracy is *relative* and rank-dependent:
error is small near the prioritized end of the rank range (controlled by
`hra`) and grows towards the other end.

## Usage

``` r
req(x = NULL, k = NULL, hra = NULL, bytes = NULL)
```

## Arguments

- x:

  Optional numeric vector to update the new sketch with.

- k:

  Sketch width controlling the accuracy/size trade-off, a single even
  whole number in `[4, 1024]`. Larger `k` is more accurate and larger;
  `k = 12` corresponds to roughly 1% relative error at 95% confidence.
  Defaults to `12` (resolved when a fresh sketch is built). Must not be
  set when `bytes` is supplied.

- hra:

  If `TRUE`, prioritize accuracy for high ranks (near 1.0); if `FALSE`,
  prioritize low ranks (near 0.0). Defaults to `TRUE` (resolved when a
  fresh sketch is built). Must not be set when `bytes` is supplied.

- bytes:

  Optional [raw](https://rdrr.io/r/base/raw.html) vector holding a
  native serialized sketch to reconstruct.

## Value

A `req_sketch` object. Key methods:

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

- `$rank_lower_bound(probs, num_std_dev = 1)` /
  `$rank_upper_bound(probs, num_std_dev = 1)`:

  Approximate confidence bounds on the rank(s) `probs`, at 1, 2, or 3
  standard deviations.

- `$n()`, `$k()`, `$num_retained()`, `$is_empty()`,
  `$is_estimation_mode()`, `$min()`, `$max()`, `$is_hra()`:

  Metadata accessors.

- `$summary()`, `$inspect()`, `$serialize()`:

  Structured metadata, verbose debug output, and the native byte
  payload.

## Details

At most one of `x` or `bytes` may be supplied:

- Pass `x` to build a sketch and immediately update it with a numeric
  vector.

- Pass `bytes` to reconstruct a sketch from a native serialized payload
  (as produced by `sketch$serialize()`). Width and `hra` are restored
  from the payload, so `k` and `hra` must not be supplied alongside
  `bytes`.

- Pass neither for an empty sketch of width `k`.

[`update()`](https://rdrr.io/r/stats/update.html) silently ignores
`NA`/`NaN`, matching the upstream/Python behaviour; there is no `na_rm`
argument.

## Examples

``` r
sketch <- req(rnorm(10000))
sketch$quantile(c(0.25, 0.5, 0.75))
#> [1] -0.716282516  0.004452604  0.687098066
sketch$rank(c(-1, 0, 1))
#> [1] 0.1562 0.4974 0.8372
sketch$rank_upper_bound(0.99)
#> [1] 0.9901089

# Round-trip through the native byte format.
restored <- req(bytes = sketch$serialize())
identical(restored$quantile(0.5), sketch$quantile(0.5))
#> [1] TRUE
```
