# Changelog

## data.sketches (development version)

### Bug fixes

- Interrupting a long `$update()` or query no longer leaks its input
  vector. The native loops probed for interrupts with
  `R_CheckUserInterrupt()`, which longjmps past C++ destructors and so
  skipped the release of cpp11’s preserve token on the input; an
  interrupted 40M-element update pinned ~320 MB in R’s precious list for
  the rest of the session. All 25 probe sites now use
  `cpp11::check_user_interrupt()`, which unwinds through
  `R_UnwindProtect`.

- [`theta()`](https://pedrobtz.github.io/data.sketches/reference/theta.md)
  and
  [`array_of_doubles()`](https://pedrobtz.github.io/data.sketches/reference/array_of_doubles.md)
  sketches rebuilt from `bytes =` no longer lose their width. A compact
  payload does not carry the builder `lg_k`, and the previous fallback
  to the default width silently cost about an order of magnitude of
  accuracy on any later `$merge()` or union — unioning two round-tripped
  `lg_k = 20` sketches retained 4,096 entries instead of 1,048,576. The
  width is now recovered from the retained-entry count.

- Native update and query loops no longer pump the R event loop on the
  first element of every call.

### New features

- `$merge()` on `theta_sketch` and `array_of_doubles_sketch` gains an
  `lg_k` argument, matching
  [`theta_union()`](https://pedrobtz.github.io/data.sketches/reference/theta_set_operations.md)
  and
  [`array_of_doubles_union()`](https://pedrobtz.github.io/data.sketches/reference/array_of_doubles_set_operations.md).
  Previously there was no way to control the width of a merge.

### Error handling

- Errors originating in the C++ bridge now carry the same classed
  conditions as the R-level validators, so
  `tryCatch(datasketches_error = )` catches every failure the package
  raises. New classes: `datasketches_invalid_bytes` (corrupt or
  truncated `bytes =` payload), `datasketches_empty_sketch`
  (`$quantile()`, `$rank()`, `$cdf()`, `$pmf()`, `$min()`, `$max()` on
  an empty sketch), and `datasketches_dead_pointer`.

- Printing or summarising a sketch restored with
  [`readRDS()`](https://rdrr.io/r/base/readRDS.html) or
  [`load()`](https://rdrr.io/r/base/load.html) now raises an actionable
  error pointing at `$serialize()` / `bytes =`, rather than reporting
  that the object is not a valid sketch. External pointers do not
  survive R’s serialization; sketches must be persisted with
  `$serialize()`.

- A `bytes =` payload shorter than 8 bytes passed to
  [`hll()`](https://pedrobtz.github.io/data.sketches/reference/hll.md)
  now raises `datasketches_invalid_bytes` rather than
  `datasketches_invalid_args`, so a malformed payload has one class
  across all sketch families. Both classes inherit `datasketches_error`.

## data.sketches 0.1.0

CRAN release: 2026-07-09

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
