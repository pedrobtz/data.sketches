# Count-Min sketch for approximate point-frequency estimation

Creates a
[Count-Min](https://apache.github.io/datasketches-cpp/5.2.0/classdatasketches_1_1count__min__sketch.html)
sketch, a mergeable summary that estimates the frequency (sum of
weights) of individual items in a numeric or character stream far larger
than memory, with one-sided error: `$estimate()` never under-estimates
the true frequency.

## Usage

``` r
count_min(
  x = NULL,
  weight = NULL,
  num_hashes = NULL,
  num_buckets = NULL,
  seed = NULL,
  bytes = NULL
)
```

## Arguments

- x:

  Optional numeric or character vector to update the new sketch with.

- weight:

  Optional weight(s) for `x`: a single finite number (recycled, may be
  negative or fractional), or a vector of such values matching the
  length of `x`. Defaults to `1` (each occurrence counts once). Cannot
  be set without `x`.

- num_hashes:

  Number of hash functions, a single whole number in `[1, 255]`. Larger
  values increase confidence but also memory use. Defaults to `3`. Must
  not be set when `bytes` is supplied. See
  [`count_min_suggest_num_hashes()`](https://pedrobtz.github.io/data.sketches/reference/count_min_suggest.md).

- num_buckets:

  Number of buckets per hash function, a single whole number of at least
  `3` (and such that `num_buckets * num_hashes < 2^30`). Larger values
  are more accurate and larger. Defaults to `55`. Must not be set when
  `bytes` is supplied. See
  [`count_min_suggest_num_buckets()`](https://pedrobtz.github.io/data.sketches/reference/count_min_suggest.md).

- seed:

  Hash seed, a single non-negative whole number up to `2^53`. Defaults
  to `9001`. Two sketches can only be merged if their `seed` (and
  `num_hashes` and `num_buckets`) match.

- bytes:

  Optional [raw](https://rdrr.io/r/base/raw.html) vector holding a
  native serialized sketch to reconstruct.

## Value

A `count_min_sketch` object. Key methods:

- `$update(x, weight = NULL)`:

  Add numeric or character values with an optional weight (mutates,
  returns the sketch).

- `$merge(other)`:

  Absorb another sketch with matching `num_hashes`, `num_buckets`, and
  `seed` (mutates, returns the sketch).

- `$estimate(item)`, `$lower_bound(item)`, `$upper_bound(item)`:

  Estimated frequency and guaranteed bounds for one or more items.

- `$total_weight()`, `$relative_error()`, `$num_hashes()`,
  `$num_buckets()`, `$seed()`, `$is_empty()`:

  Metadata accessors.

- `$summary()`, `$inspect()`, `$serialize()`:

  Structured metadata, verbose debug output, and the native byte
  payload.

## Details

At most one of `x` or `bytes` may be supplied:

- Pass `x` to build a sketch and immediately update it with a numeric or
  character vector (optionally with `weight`).

- Pass `bytes` to reconstruct a sketch from a native serialized payload
  (as produced by `sketch$serialize()`). `num_hashes` and `num_buckets`
  are restored from the payload and must not be supplied alongside
  `bytes`.

- Pass neither for an empty sketch with the given `num_hashes` and
  `num_buckets`.

Numeric items are hashed via the raw bytes of their IEEE-754 double
representation; this is internally consistent between
[`update()`](https://rdrr.io/r/stats/update.html) and the
`estimate()`/`lower_bound()`/`upper_bound()` queries, but is not
guaranteed to match hashes produced by other DataSketches language
implementations for the same numeric value.

`NA`/`NaN`/`NA_character_` are silently ignored by
[`update()`](https://rdrr.io/r/stats/update.html), matching the
missing-value policy used across families; there is no `na_rm` argument.

Two sketches can only be `$merge()`d if they share the same
`num_hashes`, `num_buckets`, and `seed`; a mismatch raises
`datasketches_incompatible_sketch`.

## Examples

``` r
words <- sample(letters[1:5], 1000, replace = TRUE, prob = c(.5, .25, .1, .1, .05))
sketch <- count_min(words)
sketch$estimate("a")
#> [1] 487
sketch$relative_error()
#> [1] 0.04942331

# Round-trip through the native byte format.
restored <- count_min(bytes = sketch$serialize())
identical(restored$total_weight(), sketch$total_weight())
#> [1] TRUE
```
