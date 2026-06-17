# data.sketches

data.sketches provides an R interface to the [Apache
DataSketches](https://datasketches.apache.org/) library of streaming
algorithms for approximate analytics on data too large to hold or
process exactly. Sketches are compact, mergeable summaries that answer
queries such as approximate distinct counts, quantiles and ranks,
frequent items and point-frequency estimates, weighted sampling, and set
membership, within known error bounds.

The package implements, grouped by family:

**Quantile sketches** for approximate quantiles, ranks, CDF, and PMF:

- [`kll_doubles()`](https://pedrobtz.github.io/data.sketches/reference/kll_doubles.md),
  [`kll_floats()`](https://pedrobtz.github.io/data.sketches/reference/kll_floats.md)
  – Karnin-Lang-Liberty (KLL) sketches.
- [`req()`](https://pedrobtz.github.io/data.sketches/reference/req.md) –
  Relative Error Quantiles (REQ), accurate near one tail.
- [`tdigest_double()`](https://pedrobtz.github.io/data.sketches/reference/tdigest_double.md)
  – t-Digest, accurate near both tails.

**Cardinality sketches** for approximate distinct counting:

- [`hll()`](https://pedrobtz.github.io/data.sketches/reference/hll.md) –
  HyperLogLog (HLL).
- [`cpc()`](https://pedrobtz.github.io/data.sketches/reference/cpc.md) –
  Compressed Probabilistic Counting (CPC).
- [`theta()`](https://pedrobtz.github.io/data.sketches/reference/theta.md)
  – Theta, with set operations
  [`theta_union()`](https://pedrobtz.github.io/data.sketches/reference/theta_set_operations.md),
  [`theta_intersection()`](https://pedrobtz.github.io/data.sketches/reference/theta_set_operations.md),
  [`theta_difference()`](https://pedrobtz.github.io/data.sketches/reference/theta_set_operations.md),
  and
  [`theta_jaccard()`](https://pedrobtz.github.io/data.sketches/reference/theta_set_operations.md).

**Frequency sketches** for approximate frequency estimation:

- [`frequent_items()`](https://pedrobtz.github.io/data.sketches/reference/frequent_items.md)
  – frequent items (heavy hitters) in a character stream.
- [`count_min()`](https://pedrobtz.github.io/data.sketches/reference/count_min.md)
  – point estimates of item frequency.

**Tuple sketches**, a Theta-extension that pairs per-key value arrays
with approximate distinct counting:

- [`array_of_doubles()`](https://pedrobtz.github.io/data.sketches/reference/array_of_doubles.md)
  – Array of Doubles, with set operations
  [`array_of_doubles_union()`](https://pedrobtz.github.io/data.sketches/reference/array_of_doubles_set_operations.md),
  [`array_of_doubles_intersection()`](https://pedrobtz.github.io/data.sketches/reference/array_of_doubles_set_operations.md),
  and
  [`array_of_doubles_difference()`](https://pedrobtz.github.io/data.sketches/reference/array_of_doubles_set_operations.md).

**Sampling sketches** for weighted sampling from a stream:

- [`varopt()`](https://pedrobtz.github.io/data.sketches/reference/varopt.md)
  – VarOpt, for minimum-variance subset-sum estimation.
- [`ebpps()`](https://pedrobtz.github.io/data.sketches/reference/ebpps.md)
  – EBPPS (Exact and Bounded Probabilistic Proportional-to-Size), a
  modern alternative to reservoir sampling.

**Filters** for approximate set membership:

- [`bloom_filter()`](https://pedrobtz.github.io/data.sketches/reference/bloom_filter.md)
  – Bloom filter.

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
