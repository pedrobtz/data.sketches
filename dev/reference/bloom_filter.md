# Bloom filter for approximate set membership

Creates a [Bloom
filter](https://github.com/apache/datasketches-cpp/tree/master/filters),
a probabilistic data structure for approximate set membership. Querying
an item that has been added always returns `TRUE` (no false negatives);
querying an item that has never been added may return `TRUE` with
probability up to the configured false-positive probability.

## Usage

``` r
bloom_filter(
  x = NULL,
  max_items = NULL,
  fpp = NULL,
  num_bits = NULL,
  num_hashes = NULL,
  seed = NULL,
  bytes = NULL
)
```

## Arguments

- x:

  Optional numeric or character vector of items to update the new filter
  with.

- max_items:

  Target maximum number of distinct items, a single positive whole
  number up to `2^53`. Must be supplied together with `fpp`, and cannot
  be combined with `num_bits`/`num_hashes`. Must not be set when `bytes`
  is supplied.

- fpp:

  Target false-positive probability, a single number in `(0, 1]`. Must
  be supplied together with `max_items`. Must not be set when `bytes` is
  supplied.

- num_bits:

  Number of bits in the filter, a single positive whole number up to
  `2^53`. Must be supplied together with `num_hashes`, and cannot be
  combined with `max_items`/`fpp`. Must not be set when `bytes` is
  supplied.

- num_hashes:

  Number of hash functions applied per item, a single whole number in
  `[1, 65535]`. Must be supplied together with `num_bits`. Must not be
  set when `bytes` is supplied.

- seed:

  Hash seed, a single non-negative whole number up to `2^53`. Defaults
  to `9001`. Two filters can only be combined if their `seed` (and
  `num_hashes` and `capacity`) match. Must not be set when `bytes` is
  supplied.

- bytes:

  Optional [raw](https://rdrr.io/r/base/raw.html) vector holding a
  native serialized filter to reconstruct.

## Value

A `bloom_filter` object. Key methods:

- `$update(x)`:

  Add items (mutates, returns the filter).

- `$query(x)`:

  Logical vector: might each element have been seen?

- `$query_and_update(x)`:

  `$query()` against the prior state, then `$update()` (mutates, returns
  the query result).

- `$merge(other)`:

  In-place logical OR with a compatible filter (mutates, returns the
  filter).

- `$intersect(other)`:

  In-place logical AND with a compatible filter (mutates, returns the
  filter).

- `$invert()`:

  In-place logical NOT (mutates, returns the filter).

- `$reset()`:

  Clear all bits, keeping sizing and `seed` (mutates, returns the
  filter).

- `$is_compatible(other)`:

  Whether `other` may be combined with this filter.

- `$capacity()`, `$num_hashes()`, `$seed()`, `$bits_used()`,
  `$is_empty()`:

  Metadata accessors.

- `$summary()`, `$inspect()`, `$serialize()`:

  Structured metadata, verbose debug output, and the native byte
  payload.

## Details

Unlike the other sketch families, a Bloom filter is not sub-linear in
size: it is sized up front and does not resize itself. There are two
sizing strategies, which cannot be combined:

- `max_items` and `fpp` size the filter for a target number of distinct
  items and a target false-positive probability.

- `num_bits` and `num_hashes` size the filter explicitly.

If neither strategy is specified, the filter defaults to
`max_items = 10000` and `fpp = 0.01`.

At most one of `x` or `bytes` may be supplied:

- Pass `x` to build a filter and immediately update it with a numeric or
  character vector of items.

- Pass `bytes` to reconstruct a filter from a native serialized payload
  (as produced by `filter$serialize()`). `max_items`, `fpp`, `num_bits`,
  `num_hashes`, and `seed` must not be supplied alongside `bytes`; they
  are restored from the payload.

- Pass neither for an empty (mutable) filter with the given sizing.

[`update()`](https://rdrr.io/r/stats/update.html), `query()`, and
`query_and_update()` silently ignore (or return `NA` for)
`NA`/`NaN`/`NA_character_` in `x`, matching the missing-value policy
used across families.

Two filters can only be combined with `$merge()` (logical OR) or
`$intersect()` (logical AND) if they are "compatible": they share the
same `seed`, `num_hashes`, and `capacity` (a mismatch raises
`datasketches_incompatible_sketch`).

## Examples

``` r
bf <- bloom_filter(letters, max_items = 1000, fpp = 0.01)
bf$query(c("a", "z", "!"))
#> [1]  TRUE  TRUE FALSE

# Round-trip through the native byte format.
restored <- bloom_filter(bytes = bf$serialize())
restored$query("a")
#> [1] TRUE
```
