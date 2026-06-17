# Changelog

## data.sketches 0.1.0

- Initial release. Provides an R interface to the Apache DataSketches
  C++ library:
  - Quantile sketches:
    [`kll_doubles()`](https://pedrobtz.github.io/data.sketches/reference/kll_doubles.md),
    [`kll_floats()`](https://pedrobtz.github.io/data.sketches/reference/kll_floats.md),
    [`req()`](https://pedrobtz.github.io/data.sketches/reference/req.md),
    and
    [`tdigest_double()`](https://pedrobtz.github.io/data.sketches/reference/tdigest_double.md).
  - Cardinality sketches:
    [`hll()`](https://pedrobtz.github.io/data.sketches/reference/hll.md),
    [`cpc()`](https://pedrobtz.github.io/data.sketches/reference/cpc.md),
    and
    [`theta()`](https://pedrobtz.github.io/data.sketches/reference/theta.md)
    (with set operations).
  - Frequency sketches:
    [`frequent_items()`](https://pedrobtz.github.io/data.sketches/reference/frequent_items.md)
    and
    [`count_min()`](https://pedrobtz.github.io/data.sketches/reference/count_min.md).
  - Tuple sketches:
    [`array_of_doubles()`](https://pedrobtz.github.io/data.sketches/reference/array_of_doubles.md)
    (with set operations).
  - Sampling sketches:
    [`varopt()`](https://pedrobtz.github.io/data.sketches/reference/varopt.md)
    and
    [`ebpps()`](https://pedrobtz.github.io/data.sketches/reference/ebpps.md).
  - Filters:
    [`bloom_filter()`](https://pedrobtz.github.io/data.sketches/reference/bloom_filter.md).

  All sketches provide `$update()`, `$merge()`, `$summary()`,
  `$inspect()`, and native `$serialize()` / `bytes =` round-tripping,
  plus [`format()`](https://rdrr.io/r/base/format.html),
  [`print()`](https://rdrr.io/r/base/print.html),
  [`as.character()`](https://rdrr.io/r/base/character.html), and
  [`summary()`](https://rdrr.io/r/base/summary.html) methods.
