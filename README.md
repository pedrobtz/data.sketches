
<!-- README.md is generated from README.Rmd. Please edit that file -->

# data.sketches

<!-- badges: start -->

[![R-CMD-check](https://github.com/pedrobtz/data.sketches/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/pedrobtz/data.sketches/actions/workflows/R-CMD-check.yaml)
[![coverage](https://raw.githubusercontent.com/pedrobtz/data.sketches/main/.github/badges/coverage.svg)](https://github.com/pedrobtz/data.sketches/actions/workflows/coverage.yaml)
<!-- badges: end -->

data.sketches provides an R interface to the [Apache
DataSketches](https://datasketches.apache.org/) library of streaming
algorithms for approximate analytics on data too large to hold or
process exactly. Sketches are compact, mergeable summaries that answer
queries such as approximate distinct counts, quantiles and ranks,
frequent items and point-frequency estimates, weighted sampling, and set
membership, within known error bounds.

The package implements, grouped by family:

**Quantile sketches** for approximate quantiles, ranks, CDF, and PMF:

- `kll_doubles()`, `kll_floats()` – Karnin-Lang-Liberty (KLL) sketches.
- `req()` – Relative Error Quantiles (REQ), accurate near one tail.
- `tdigest_double()` – t-Digest, accurate near both tails.

**Cardinality sketches** for approximate distinct counting:

- `hll()` – HyperLogLog (HLL).
- `cpc()` – Compressed Probabilistic Counting (CPC).
- `theta()` – Theta, with set operations `theta_union()`,
  `theta_intersection()`, `theta_difference()`, and `theta_jaccard()`.

**Frequency sketches** for approximate frequency estimation:

- `frequent_items()` – frequent items (heavy hitters) in a character
  stream.
- `count_min()` – point estimates of item frequency.

**Tuple sketches**, a Theta-extension that pairs per-key value arrays
with approximate distinct counting:

- `array_of_doubles()` – Array of Doubles, with set operations
  `array_of_doubles_union()`, `array_of_doubles_intersection()`, and
  `array_of_doubles_difference()`.

**Sampling sketches** for weighted sampling from a stream:

- `varopt()` – VarOpt, for minimum-variance subset-sum estimation.
- `ebpps()` – EBPPS (Exact and Bounded Probabilistic
  Proportional-to-Size), a modern alternative to reservoir sampling.

**Filters** for approximate set membership:

- `bloom_filter()` – Bloom filter.

## Installation

Install the development version from GitHub with pak:

``` r
pak::pak("pedrobtz/data.sketches")
```

Or install the released version from CRAN with:

``` r
install.packages("data.sketches")
```

## Example

Build a KLL sketch from a numeric vector and query approximate quantiles
and ranks:

``` r
library(data.sketches)

sketch <- kll_doubles(rnorm(10000))
sketch

sketch$quantile(c(0.25, 0.5, 0.75))
sketch$rank(c(-1, 0, 1))
```

Sketches are mergeable, so partial sketches built from different chunks
of a stream can be combined into one:

``` r
a <- kll_doubles(rnorm(5000, mean = -2))
b <- kll_doubles(rnorm(5000, mean = 2))
a$merge(b)
a$quantile(c(0.25, 0.5, 0.75))
```

Sketches can be serialized to a raw vector and restored, for
interoperability with other Apache DataSketches implementations:

``` r
bytes <- sketch$serialize()
restored <- kll_doubles(bytes = bytes)
restored$quantile(0.5)
```
