# data.sketches 0.1.1

## Bug fixes

* Interrupting a long `$update()` or query no longer leaks its input vector.
  The native loops probed for interrupts with `R_CheckUserInterrupt()`, which
  longjmps past C++ destructors and so skipped the release of cpp11's preserve
  token on the input; an interrupted 40M-element update pinned ~320 MB in R's
  precious list for the rest of the session. All 25 probe sites now use
  `cpp11::check_user_interrupt()`, which unwinds through `R_UnwindProtect`.

* `theta()` and `array_of_doubles()` sketches rebuilt from `bytes =` no longer
  lose their width. A compact payload does not carry the builder `lg_k`, and
  the previous fallback to the default width silently cost about an order of
  magnitude of accuracy on any later `$merge()` or union — unioning two
  round-tripped `lg_k = 20` sketches retained 4,096 entries instead of
  1,048,576. The width is now recovered from the retained-entry count.

* Native update and query loops no longer pump the R event loop on the first
  element of every call.

## New features

* `$merge()` on `theta_sketch` and `array_of_doubles_sketch` gains an `lg_k`
  argument, matching `theta_union()` and `array_of_doubles_union()`. Previously
  there was no way to control the width of a merge.

## Error handling

* Errors originating in the C++ bridge now carry the same classed conditions as
  the R-level validators, so `tryCatch(datasketches_error = )` catches every
  failure the package raises. New classes:
  `datasketches_invalid_bytes` (corrupt or truncated `bytes =` payload),
  `datasketches_empty_sketch` (`$quantile()`, `$rank()`, `$cdf()`, `$pmf()`,
  `$min()`, `$max()` on an empty sketch), and `datasketches_dead_pointer`.

* Printing or summarising a sketch restored with `readRDS()` or `load()` now
  raises an actionable error pointing at `$serialize()` / `bytes =`, rather
  than reporting that the object is not a valid sketch. External pointers do
  not survive R's serialization; sketches must be persisted with
  `$serialize()`.

* A `bytes =` payload shorter than 8 bytes passed to `hll()` now raises
  `datasketches_invalid_bytes` rather than `datasketches_invalid_args`, so a
  malformed payload has one class across all sketch families. Both classes
  inherit `datasketches_error`.

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
