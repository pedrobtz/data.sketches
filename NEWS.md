# data.sketches 0.1.0

* Initial release. Provides an R interface to the Apache DataSketches C++
  library:
  - Quantile sketches: `kll_doubles()`, `kll_floats()`, `req()`, and
    `tdigest_double()`.
  - Cardinality sketches: `hll()`, `cpc()`, and `theta()` (with set
    operations).
  - Frequency sketches: `frequent_items()` and `count_min()`.
  - Tuple sketches: `array_of_doubles()` (with set operations).
  - Sampling sketches: `varopt()` and `ebpps()`.
  - Filters: `bloom_filter()`.

  All sketches provide `$update()`, `$merge()`, `$summary()`, `$inspect()`,
  and native `$serialize()` / `bytes =` round-tripping, plus `format()`,
  `print()`, `as.character()`, and `summary()` methods.
