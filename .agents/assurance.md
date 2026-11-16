# Assurance

How this package meets the shared `assurance.md` rules. CI checks this
file (r-actions `assurance.yml`), so keep the headings and table
columns as they are.

- **Statuses:** a cell is a fact, `gap #<issue>` or `n/a: <reason>`.
- **Kinds:** delete the ones that do not apply.
- **Tables:** delete a table only when no kind requires it. Delete the
  example rows.

## Kinds

`compiled` `untrusted-input` `spec` `lifecycle` `emits`

## Required checks

`Where` names the workflow file under `.github/workflows/` that runs the
check. Add `(own)` when that workflow is the package's own rather than a
call to r-actions.

| Check         | Status | Where               |
| ------------- | ------ | ------------------- |
| sanitizers    | done   | native-checks.yaml  |
| valgrind      | done   | native-checks.yaml  |
| rchk          | done   | native-checks.yaml  |
| gctorture     | done   | gctorture.yaml      |
| analyzers     | done   | native-checks.yaml  |
| alloc-failure | done   | alloc-failure.yaml  |
| mutation      | gap #27 |                     |
| fuzz          | done   | fuzz.yaml           |
| fuzz-reach    | gap #28 | fuzz.yaml           |

## Boundaries

One row per boundary the package crosses. An oracle knows the answer:

- a conformance suite or test vectors;
- a reference implementation;
- a round trip;
- equivalent inputs compared;
- the bytes the other side received.

"No crash" is not an oracle.

Each family's `$serialize()` / `bytes =` pair is the Apache DataSketches
binary format for that sketch, which the Java and Python implementations
also read and write. The round trips compare the restored sketch's answers
with the original's in R, and `tools/fuzz/` requires every payload the
library accepts to re-serialize to the same bytes (Frequent Items: the same
items, estimates and bounds). Neither knows whether the bytes are the
format other implementations expect.

<!-- markdownlint-disable MD013 -->
| Boundary                                 | Oracle                                                         | Carried by                                                   |
| ---------------------------------------- | -------------------------------------------------------------- | ------------------------------------------------------------ |
| KLL doubles format, decode and encode    | round trip: `n()` and quantiles of the restored sketch         | tests/testthat/test-quantiles-kll-doubles.R, tools/fuzz      |
| KLL floats format, decode and encode     | round trip: `n()` and quantiles of the restored sketch         | tests/testthat/test-quantiles-kll-floats.R, tools/fuzz       |
| REQ format, decode and encode            | round trip: `n()` and quantiles of the restored sketch         | tests/testthat/test-quantiles-req.R, tools/fuzz              |
| t-Digest format, decode and encode       | round trip: `n()` and quantiles of the restored sketch         | tests/testthat/test-quantiles-tdigest-double.R, tools/fuzz   |
| HLL format, decode and encode            | round trip: estimate and bounds of the restored sketch         | tests/testthat/test-cardinality-hll.R, tools/fuzz            |
| CPC format, decode and encode            | round trip, default and non-default seed                       | tests/testthat/test-cardinality-cpc.R, tools/fuzz            |
| Theta compact format, decode and encode  | round trip, seeds, and unions of round-tripped vs live sketches | tests/testthat/test-cardinality-theta.R, tools/fuzz          |
| Array of Doubles format, decode and encode | round trip, seeds, and set operations on restored sketches   | tests/testthat/test-tuple.R, tools/fuzz                      |
| Frequent Items format, decode and encode | round trip: items and estimates of the restored sketch         | tests/testthat/test-frequent-items.R, tools/fuzz             |
| Count-Min format, decode and encode      | round trip: estimates of the restored sketch                   | tests/testthat/test-count-min.R, tools/fuzz                  |
| VarOpt format (tagged), decode and encode | round trip, numeric and character items                       | tests/testthat/test-sampling-varopt.R, tools/fuzz            |
| EBPPS format (tagged), decode and encode | round trip, numeric and character items                        | tests/testthat/test-sampling-reservoir.R, tools/fuzz         |
| Bloom filter format, decode and encode   | round trip: membership of the restored filter                  | tests/testthat/test-filters-bloom.R, tools/fuzz              |
| every format, decode                     | sketches serialized by Apache DataSketches Java and Python     | gap #25                                                       |
| every format, encode                     | the Python `datasketches` package decoding what we serialize   | gap #26                                                       |
<!-- markdownlint-enable MD013 -->

## Objects

One row per object that outlives the call that made it. "Sequences" is
the test of its out-of-order use (abort then read, use after end, use
after free). The guard columns name the test, or say why the guard
cannot apply.

Every family's R6 object holds one `cpp11::external_pointer` to the native
sketch. None holds a file, socket, thread or other OS resource, and none
keeps a pointer it did not allocate: the bindings copy every R vector
before handing it to the library. The cpp11 finalizer deletes the sketch;
valgrind and ASan (native-checks.yaml) report a sketch it fails to free.
The `readRDS()` path (a dead pointer) is tested for every family, but only
through `print()`, `format()`, `summary()` and `as.character()`.

<!-- markdownlint-disable MD013 -->
| Object                     | Sequences | Fork                                     | Unwind                                  | Owner                                       |
| -------------------------- | --------- | ---------------------------------------- | --------------------------------------- | ------------------------------------------- |
| `kll_doubles_sketch`       | gap #30    | n/a: heap memory only, copied by fork    | tests/testthat/test-interrupt-safety.R  | cpp11 finalizer; valgrind, ASan             |
| `kll_floats_sketch`        | gap #30    | n/a: heap memory only, copied by fork    | gap #29                                  | cpp11 finalizer; valgrind, ASan             |
| `req_sketch`               | gap #30    | n/a: heap memory only, copied by fork    | gap #29                                  | cpp11 finalizer; valgrind, ASan             |
| `tdigest_double_sketch`    | gap #30    | n/a: heap memory only, copied by fork    | gap #29                                  | cpp11 finalizer; valgrind, ASan             |
| `hll_sketch`               | gap #30    | n/a: heap memory only, copied by fork    | gap #29                                  | cpp11 finalizer; valgrind, ASan             |
| `cpc_sketch`               | gap #30    | n/a: heap memory only, copied by fork    | gap #29                                  | cpp11 finalizer; valgrind, ASan             |
| `theta_sketch`             | gap #30    | n/a: heap memory only, copied by fork    | gap #29                                  | cpp11 finalizer; valgrind, ASan             |
| `array_of_doubles_sketch`  | gap #30    | n/a: heap memory only, copied by fork    | gap #29                                  | cpp11 finalizer; valgrind, ASan             |
| `frequent_items_sketch`    | gap #30    | n/a: heap memory only, copied by fork    | gap #29                                  | cpp11 finalizer; valgrind, ASan             |
| `count_min_sketch`         | gap #30    | n/a: heap memory only, copied by fork    | gap #29                                  | cpp11 finalizer; valgrind, ASan             |
| `varopt_sketch`            | gap #30    | n/a: heap memory only, copied by fork    | gap #29                                  | cpp11 finalizer; valgrind, ASan             |
| `ebpps_sketch`             | gap #30    | n/a: heap memory only, copied by fork    | gap #29                                  | cpp11 finalizer; valgrind, ASan             |
| `bloom_filter`             | gap #30    | n/a: heap memory only, copied by fork    | gap #29                                  | cpp11 finalizer; valgrind, ASan             |
<!-- markdownlint-enable MD013 -->

## Limits

One row per limit the package enforces. "Straddled by" is the test of
`limit - 1`, `limit` and `limit + 1` on every path that reaches it.

The tests reject a value outside each range (`k = 2`, `lg_k = 27`) but
seldom accept the bound itself or reject its neighbour; the seeds, tested
at `2^53` and `2^53 + 2`, come closest.

<!-- markdownlint-disable MD013 -->
| Limit                                                        | Unit                    | Straddled by |
| ------------------------------------------------------------ | ----------------------- | ------------ |
| `k` in 8..65535, `kll_doubles()`, `kll_floats()`             | items per level         | gap #31       |
| `k` in 4..1024 and even, `req()`                             | items per section       | gap #31       |
| `k` in 10..65535, `tdigest_double()`                         | centroids (compression) | gap #31       |
| `lg_k` in 4..21, `hll()`                                     | log2 buckets            | gap #31       |
| `lg_k` in 4..26, `cpc()`                                     | log2 buckets            | gap #31       |
| `lg_k` in 5..26, `theta()`, `theta_union()`, `$merge()`      | log2 entries            | gap #31       |
| `lg_k` in 5..26, `array_of_doubles()`, its union, `$merge()` | log2 entries            | gap #31       |
| `num_values` in 1..255, `array_of_doubles()`                 | values per key          | gap #31       |
| `lg_max_map_size` in 3..30, `lg_start_map_size` in 3..max    | log2 map slots          | gap #31       |
| `num_hashes` in 1..255, `num_buckets` >= 3, product < 2^30   | counters                | gap #31       |
| `k` in 1..2^31 - 2, `varopt()`, `ebpps()`                    | items                   | gap #31       |
| `num_hashes` in 1..65535, `bloom_filter()`                   | hash functions          | gap #31       |
| `num_bits`, `max_items` up to 2^53, `bloom_filter()`         | bits, items             | gap #31       |
| `seed` in 0..2^53, every hashed family                       | integer                 | gap #31       |
| `weight` up to 2^53, `frequent_items()`, `count_min()`       | integer weight          | gap #31       |
<!-- markdownlint-enable MD013 -->
