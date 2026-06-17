# Array of Doubles (Tuple) sketch for estimating sums alongside distinct counts

Creates an [Array of
Doubles](https://datasketches.apache.org/docs/Tuple/TupleOverview.html)
sketch, a Tuple sketch that extends a
[`theta()`](https://pedrobtz.github.io/data.sketches/reference/theta.md)
sketch by associating a fixed-length array of `num_values` doubles with
each retained key. It estimates not only the number of distinct keys
(`$estimate()`, as for
[`theta()`](https://pedrobtz.github.io/data.sketches/reference/theta.md))
but also the sum of each value column over the full input stream
(`$column_sums()`), e.g. to estimate the total of a numeric measure
across distinct users.

## Usage

``` r
array_of_doubles(
  x = NULL,
  values = NULL,
  lg_k = NULL,
  num_values = NULL,
  seed = NULL,
  bytes = NULL
)
```

## Arguments

- x:

  Optional numeric or character vector of keys to update the new sketch
  with. Each element is hashed and contributes to the distinct-count
  estimate.

- values:

  Optional value(s) associated with each element of `x`: a numeric
  vector (when `num_values == 1`) or a numeric matrix with `num_values`
  columns, recycled to `length(x)` rows if a single value/row is
  supplied. Defaults to `1`s (so `$column_sums()` estimates the count of
  each key, like `$estimate()`). Cannot be set without `x`.

- lg_k:

  log2 of the nominal number of entries, a single whole number in
  `[5, 26]`. Larger `lg_k` is more accurate and larger. Defaults to `12`
  (resolved when a fresh sketch is built). Must not be set when `bytes`
  is supplied.

- num_values:

  Number of double values associated with each retained key, a single
  whole number in `[1, 255]`. Defaults to `1`. Must not be set when
  `bytes` is supplied.

- seed:

  Hash seed, a single non-negative whole number up to `2^53`. Defaults
  to `9001` (the upstream default), resolved whether or not `bytes` is
  supplied.

- bytes:

  Optional [raw](https://rdrr.io/r/base/raw.html) vector holding a
  native serialized sketch to reconstruct. The result is always a
  compact sketch.

## Value

An `array_of_doubles_sketch` object. Key methods:

- `$update(x, values = NULL)`:

  Add keys with associated values (mutates, returns the sketch). Errors
  if the sketch is compact.

- `$merge(other)`:

  Absorb another sketch with the same `seed` and `num_values`, becoming
  compact (mutates, returns the sketch).

- `$estimate()`:

  Approximate number of distinct keys seen.

- `$lower_bound(num_std_dev = 1)` / `$upper_bound(num_std_dev = 1)`:

  Approximate confidence bounds on `estimate()`, at 1, 2, or 3 standard
  deviations.

- `$column_sums()`:

  Estimated sum of each value column over the full input stream.

- `$lg_k()`, `$num_values()`, `$seed()`, `$theta()`, `$num_retained()`,
  `$is_empty()`, `$is_estimation_mode()`, `$is_ordered()`,
  `$is_compact()`:

  Metadata accessors.

- `$summary()`, `$inspect()`, `$serialize()`:

  Structured metadata, verbose debug output, and the native byte
  payload.

## Details

At most one of `x` or `bytes` may be supplied:

- Pass `x` to build a sketch and immediately update it with a numeric or
  character vector of keys (optionally with `values`).

- Pass `bytes` to reconstruct a sketch from a native serialized payload
  (as produced by `sketch$serialize()`). The result is always a
  *compact* sketch (see below); `lg_k` and `num_values` must not be
  supplied alongside `bytes`. Unlike `lg_k`, the hash `seed` is *not*
  stored in the payload and must be supplied if the original sketch did
  not use the default.

- Pass neither for an empty (mutable) sketch with the given `lg_k`,
  `num_values`, and `seed`.

[`update()`](https://rdrr.io/r/stats/update.html) silently ignores
`NA`/`NaN`/`NA_character_` in `x` (and the corresponding row of
`values`), matching the missing-value policy used across families; there
is no `na_rm` argument.

An Array of Doubles sketch is either an *update* sketch (mutable,
`$is_compact()` is `FALSE`) or a *compact* sketch (immutable,
`$is_compact()` is `TRUE`). Fresh sketches built from `x`/`lg_k` are
update sketches and can be grown with `$update()`. Compact sketches
arise from `bytes =` reconstruction, `$merge()`, or any of the
`array_of_doubles_*()` set operations, and cannot be updated further.
`$lg_k()` is only defined for update sketches.

Two sketches can only be merged with `$merge()`, or combined with
[`array_of_doubles_union()`](https://pedrobtz.github.io/data.sketches/reference/array_of_doubles_set_operations.md)
/
[`array_of_doubles_intersection()`](https://pedrobtz.github.io/data.sketches/reference/array_of_doubles_set_operations.md),
if they share the same `seed` (a mismatch raises
`datasketches_seed_mismatch`) and the same `num_values` (a mismatch
raises `datasketches_incompatible_sketch`). Value arrays for matching
keys are combined by element-wise sum. `$merge()` mutates the receiver
into a compact sketch holding the union of both inputs (so it can no
longer be `$update()`d afterward).

## Examples

``` r
keys <- sample(1000, 5000, replace = TRUE)
values <- runif(length(keys))
sketch <- array_of_doubles(keys, values)
sketch$estimate()
#> [1] 994
sketch$column_sums()
#> [1] 2526.101

# Round-trip through the native byte format (always compact).
restored <- array_of_doubles(bytes = sketch$serialize())
restored$is_compact()
#> [1] TRUE
identical(restored$column_sums(), sketch$column_sums())
#> [1] TRUE
```
