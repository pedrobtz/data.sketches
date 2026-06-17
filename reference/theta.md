# Theta sketch for approximate distinct counting and set operations

Creates a
[Theta](https://datasketches.apache.org/docs/Theta/ThetaSketches.html)
sketch, a mergeable summary that estimates the number of distinct values
seen in a stream far larger than memory. Unlike
[`hll()`](https://pedrobtz.github.io/data.sketches/reference/hll.md) and
[`cpc()`](https://pedrobtz.github.io/data.sketches/reference/cpc.md),
Theta sketches natively support set operations:
[`theta_union()`](https://pedrobtz.github.io/data.sketches/reference/theta_set_operations.md),
[`theta_intersection()`](https://pedrobtz.github.io/data.sketches/reference/theta_set_operations.md),
[`theta_difference()`](https://pedrobtz.github.io/data.sketches/reference/theta_set_operations.md),
and
[`theta_jaccard()`](https://pedrobtz.github.io/data.sketches/reference/theta_set_operations.md)
combine two sketches into a new result without mutating either input.

## Usage

``` r
theta(x = NULL, lg_k = NULL, seed = NULL, bytes = NULL)
```

## Arguments

- x:

  Optional numeric or character vector to update the new sketch with.
  Each element is hashed and contributes to the distinct-count estimate.

- lg_k:

  log2 of the nominal number of entries, a single whole number in
  `[5, 26]`. Larger `lg_k` is more accurate and larger. Defaults to `12`
  (resolved when a fresh sketch is built). Must not be set when `bytes`
  is supplied.

- seed:

  Hash seed, a single non-negative whole number up to `2^53`. Defaults
  to `9001` (the upstream default), resolved whether or not `bytes` is
  supplied.

- bytes:

  Optional [raw](https://rdrr.io/r/base/raw.html) vector holding a
  native serialized sketch to reconstruct. The result is always a
  compact sketch.

## Value

A `theta_sketch` object. Key methods:

- `$update(x)`:

  Add numeric or character values (mutates, returns the sketch). Errors
  if the sketch is compact.

- `$merge(other)`:

  Absorb another sketch with the same `seed`, becoming compact (mutates,
  returns the sketch).

- `$estimate()`:

  Approximate number of distinct values seen.

- `$lower_bound(num_std_dev = 1)` / `$upper_bound(num_std_dev = 1)`:

  Approximate confidence bounds on `estimate()`, at 1, 2, or 3 standard
  deviations.

- `$lg_k()`, `$seed()`, `$theta()`, `$num_retained()`, `$is_empty()`,
  `$is_estimation_mode()`, `$is_ordered()`, `$is_compact()`:

  Metadata accessors.

- `$summary()`, `$inspect()`, `$serialize()`:

  Structured metadata, verbose debug output, and the native byte
  payload.

## Details

At most one of `x` or `bytes` may be supplied:

- Pass `x` to build a sketch and immediately update it with a numeric or
  character vector.

- Pass `bytes` to reconstruct a sketch from a native serialized payload
  (as produced by `sketch$serialize()`). The result is always a
  *compact* sketch (see below); `lg_k` must not be supplied alongside
  `bytes`. Unlike `lg_k`, the hash `seed` is *not* stored in the payload
  and must be supplied if the original sketch did not use the default.

- Pass neither for an empty (mutable) sketch with the given `lg_k` and
  `seed`.

[`update()`](https://rdrr.io/r/stats/update.html) silently ignores
`NA`/`NaN`/`NA_character_`, matching the missing-value policy used
across families; there is no `na_rm` argument.

A Theta sketch is either an *update* sketch (mutable, `$is_compact()` is
`FALSE`) or a *compact* sketch (immutable, `$is_compact()` is `TRUE`).
Fresh sketches built from `x`/`lg_k` are update sketches and can be
grown with `$update()`. Compact sketches arise from `bytes =`
reconstruction, `$merge()`, or any of the `theta_*()` set operations,
and cannot be updated further. `$lg_k()` is only defined for update
sketches.

Two sketches can only be merged with `$merge()`, or combined with a
`theta_*()` set operation, if they share the same `seed`; a mismatch
raises `datasketches_seed_mismatch`. `$merge()` mutates the receiver
into a compact sketch holding the union of both inputs (so it can no
longer be `$update()`d afterward).

## Examples

``` r
sketch <- theta(sample(1000, 5000, replace = TRUE))
sketch$estimate()
#> [1] 991
sketch$lower_bound()
#> [1] 991
sketch$upper_bound()
#> [1] 991

# Round-trip through the native byte format (always compact).
restored <- theta(bytes = sketch$serialize())
restored$is_compact()
#> [1] TRUE
identical(restored$estimate(), sketch$estimate())
#> [1] TRUE

# Set operations.
a <- theta(1:1000)
b <- theta(501:1500)
theta_union(a, b)$estimate()
#> [1] 1500
theta_intersection(a, b)$estimate()
#> [1] 500
theta_difference(a, b)$estimate()
#> [1] 500
theta_jaccard(a, b)
#> lower_bound    estimate upper_bound 
#>   0.3333333   0.3333333   0.3333333 
```
