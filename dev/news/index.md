# Changelog

## data.sketches (development version)

### Security

- The bundled Apache DataSketches C++ library is updated from 5.2.0 to
  5.3.1, which fixes out-of-bounds reads and writes when deserializing
  corrupt KLL, REQ, HLL, CPC, Count-Min, Theta and VarOpt payloads
  (CVE-2026-103501, CVE-2026-103513, CVE-2026-103634, CVE-2026-103635,
  CVE-2026-103636, CVE-2026-123274, CVE-2026-123338). Every `bytes =`
  constructor was affected. If you rebuild sketches from bytes you did
  not produce, upgrade.

- Many deserialization bugs that remain in 5.3.1 are patched locally,
  found by fuzzing every `bytes =` constructor under AddressSanitizer
  and UndefinedBehaviorSanitizer
  ([\#33](https://github.com/pedrobtz/data.sketches/issues/33)). A
  corrupt payload is now rejected with `datasketches_invalid_bytes`
  instead of reaching undefined behavior, an out-of-bounds read or
  write, a double free, a crash on first use (a Bloom filter of zero
  capacity divided by zero on `$update()`), or an allocation of
  gigabytes from a few bytes. The families affected are
  [`hll()`](https://pedrobtz.github.io/data.sketches/dev/reference/hll.md),
  [`bloom_filter()`](https://pedrobtz.github.io/data.sketches/dev/reference/bloom_filter.md),
  [`ebpps()`](https://pedrobtz.github.io/data.sketches/dev/reference/ebpps.md),
  [`frequent_items()`](https://pedrobtz.github.io/data.sketches/dev/reference/frequent_items.md),
  [`req()`](https://pedrobtz.github.io/data.sketches/dev/reference/req.md),
  [`count_min()`](https://pedrobtz.github.io/data.sketches/dev/reference/count_min.md),
  [`tdigest_double()`](https://pedrobtz.github.io/data.sketches/dev/reference/tdigest_double.md),
  [`theta()`](https://pedrobtz.github.io/data.sketches/dev/reference/theta.md),
  [`array_of_doubles()`](https://pedrobtz.github.io/data.sketches/dev/reference/array_of_doubles.md),
  [`kll_doubles()`](https://pedrobtz.github.io/data.sketches/dev/reference/kll_doubles.md),
  [`kll_floats()`](https://pedrobtz.github.io/data.sketches/dev/reference/kll_floats.md)
  and
  [`varopt()`](https://pedrobtz.github.io/data.sketches/dev/reference/varopt.md).
  Payloads written by valid sketches, including those from data.sketches
  0.1.1, still load.

- A small corrupt
  [`req()`](https://pedrobtz.github.io/data.sketches/dev/reference/req.md)
  payload could request an 8 GiB allocation; 5.3.1 rejects it
  ([\#33](https://github.com/pedrobtz/data.sketches/issues/33)).

### Bug fixes

- A
  [`frequent_items()`](https://pedrobtz.github.io/data.sketches/dev/reference/frequent_items.md)
  sketch that ran out of memory while growing, or a KLL sketch that ran
  out of memory in `$merge()`, no longer crashes R later, when it is
  garbage-collected or R exits (“double free or corruption”). The
  library left the sketch’s memory half-replaced after the failed
  allocation; both are patched locally
  ([\#35](https://github.com/pedrobtz/data.sketches/issues/35)).

- [`tdigest_double()`](https://pedrobtz.github.io/data.sketches/dev/reference/tdigest_double.md)
  no longer returns `Inf` or `NaN` quantiles for data near the largest
  double, and such a sketch can again be read back after `$serialize()`.
  The library multiplied means by weights before dividing, which
  overflowed; it is patched locally to divide first.

- [`bloom_filter()`](https://pedrobtz.github.io/data.sketches/dev/reference/bloom_filter.md)
  validates sizes against the library’s own maximum, 17,179,868,864 bits
  (2 GiB): `num_bits` above it raises `datasketches_invalid_num_bits`,
  and `max_items` whose filter at `fpp` would exceed it raises
  `datasketches_invalid_max_items`, naming the limit and what to change.
  Such sizes used to pass R’s check (up to 2^53) and fail in the library
  with an unclassed error, for `num_bits` with the wrong limit (“less
  than 2^63”) in its message.
  [`bloom_filter_suggest_num_hashes()`](https://pedrobtz.github.io/data.sketches/dev/reference/bloom_filter_suggest.md)
  gets the same check;
  [`bloom_filter_suggest_num_filter_bits()`](https://pedrobtz.github.io/data.sketches/dev/reference/bloom_filter_suggest.md)
  still reports what a size needs, even past the limit
  ([\#32](https://github.com/pedrobtz/data.sketches/issues/32)).

- [`bloom_filter_suggest_num_hashes()`](https://pedrobtz.github.io/data.sketches/dev/reference/bloom_filter_suggest.md)
  suggests at most 65535 hash functions, the most a filter stores. With
  more than about 94,500 bits per item the library’s count overflowed
  its 16-bit result, which is undefined behaviour; it is patched locally
  to clamp.

- Every native constructor’s error is now classed: one the library
  raises that R’s checks did not anticipate arrives as
  `datasketches_invalid_args`, with the library’s message as its parent,
  so `tryCatch(datasketches_error = )` catches every failure as 0.1.1
  promised
  ([\#32](https://github.com/pedrobtz/data.sketches/issues/32)).

- `req(k =)` now honours widths of 256 and above. The library stored `k`
  in 8 bits, so `k = 500` built a sketch of width 244 and `k = 256` or
  `k = 1024` one of width 4, with correspondingly worse accuracy.

### Breaking changes

- [`varopt()`](https://pedrobtz.github.io/data.sketches/dev/reference/varopt.md)
  and `$update()` on a VarOpt sketch reject a `weight` of zero, with
  `datasketches_invalid_weight`. The library now requires positive
  weights, as datasketches-java and the VarOpt paper do; zero-weight
  items never contributed to an estimate.

- Results from the updated library can differ slightly from 0.1.1:
  t-Digest ranks and quantiles in the tails, and HLL union estimates,
  which no longer depend on merge order. Serialized HLL sketches and
  single-item Theta sketches now match datasketches-java byte for byte;
  payloads written by 0.1.1 still load.

## data.sketches 0.1.1

CRAN release: 2026-09-23

### Bug fixes

- Interrupting a long `$update()` or query no longer leaks its input
  vector. The native loops probed for interrupts with
  `R_CheckUserInterrupt()`, which longjmps past C++ destructors and so
  skipped the release of cpp11’s preserve token on the input; an
  interrupted 40M-element update pinned ~320 MB in R’s precious list for
  the rest of the session. All 25 probe sites now use
  `cpp11::check_user_interrupt()`, which unwinds through
  `R_UnwindProtect`.

- [`theta()`](https://pedrobtz.github.io/data.sketches/dev/reference/theta.md)
  and
  [`array_of_doubles()`](https://pedrobtz.github.io/data.sketches/dev/reference/array_of_doubles.md)
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
  [`theta_union()`](https://pedrobtz.github.io/data.sketches/dev/reference/theta_set_operations.md)
  and
  [`array_of_doubles_union()`](https://pedrobtz.github.io/data.sketches/dev/reference/array_of_doubles_set_operations.md).
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
  [`hll()`](https://pedrobtz.github.io/data.sketches/dev/reference/hll.md)
  now raises `datasketches_invalid_bytes` rather than
  `datasketches_invalid_args`, so a malformed payload has one class
  across all sketch families. Both classes inherit `datasketches_error`.

## data.sketches 0.1.0

CRAN release: 2026-07-09

- Initial release. Provides an R interface to the Apache DataSketches
  C++ library:
  - Quantile sketches:
    [`kll_doubles()`](https://pedrobtz.github.io/data.sketches/dev/reference/kll_doubles.md),
    [`kll_floats()`](https://pedrobtz.github.io/data.sketches/dev/reference/kll_floats.md),
    [`req()`](https://pedrobtz.github.io/data.sketches/dev/reference/req.md),
    and
    [`tdigest_double()`](https://pedrobtz.github.io/data.sketches/dev/reference/tdigest_double.md).
  - Cardinality sketches:
    [`hll()`](https://pedrobtz.github.io/data.sketches/dev/reference/hll.md),
    [`cpc()`](https://pedrobtz.github.io/data.sketches/dev/reference/cpc.md),
    and
    [`theta()`](https://pedrobtz.github.io/data.sketches/dev/reference/theta.md)
    (with set operations).
  - Frequency sketches:
    [`frequent_items()`](https://pedrobtz.github.io/data.sketches/dev/reference/frequent_items.md)
    and
    [`count_min()`](https://pedrobtz.github.io/data.sketches/dev/reference/count_min.md).
  - Tuple sketches:
    [`array_of_doubles()`](https://pedrobtz.github.io/data.sketches/dev/reference/array_of_doubles.md)
    (with set operations).
  - Sampling sketches:
    [`varopt()`](https://pedrobtz.github.io/data.sketches/dev/reference/varopt.md)
    and
    [`ebpps()`](https://pedrobtz.github.io/data.sketches/dev/reference/ebpps.md).
  - Filters:
    [`bloom_filter()`](https://pedrobtz.github.io/data.sketches/dev/reference/bloom_filter.md).

  All sketches provide `$update()`, `$merge()`, `$summary()`,
  `$inspect()`, and native `$serialize()` / `bytes =` round-tripping,
  plus [`format()`](https://rdrr.io/r/base/format.html),
  [`print()`](https://rdrr.io/r/base/print.html),
  [`as.character()`](https://rdrr.io/r/base/character.html), and
  [`summary()`](https://rdrr.io/r/base/summary.html) methods.
