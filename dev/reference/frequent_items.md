# Frequent Items sketch for approximate frequency estimation

Creates a [Frequent
Items](https://datasketches.apache.org/docs/Frequency/FrequencySketches.html)
sketch, a mergeable summary that estimates the frequencies of the most
frequent items in a character stream far larger than memory, with
guaranteed error bounds.

## Usage

``` r
frequent_items(
  x = NULL,
  weight = NULL,
  lg_max_map_size = NULL,
  lg_start_map_size = NULL,
  bytes = NULL
)
```

## Arguments

- x:

  Optional character vector to update the new sketch with.

- weight:

  Optional weight(s) for `x`: a single non-negative whole number
  (recycled), or a vector of such values matching the length of `x`.
  Defaults to `1` (each occurrence counts once). Cannot be set without
  `x`.

- lg_max_map_size:

  log2 of the maximum size of the internal hash map, a single whole
  number in `[3, 30]`. Larger values are more accurate and larger.
  Defaults to `8`. Must not be set when `bytes` is supplied.

- lg_start_map_size:

  log2 of the starting size of the internal hash map, a single whole
  number in `[3, lg_max_map_size]`. Defaults to `3`. Must not be set
  when `bytes` is supplied.

- bytes:

  Optional [raw](https://rdrr.io/r/base/raw.html) vector holding a
  native serialized sketch to reconstruct.

## Value

A `frequent_items_sketch` object. Key methods:

- `$update(x, weight = NULL)`:

  Add character values with an optional weight (mutates, returns the
  sketch).

- `$merge(other)`:

  Absorb another sketch (mutates, returns the sketch).

- `$estimate(item)`, `$lower_bound(item)`, `$upper_bound(item)`:

  Estimated frequency and guaranteed bounds for one or more items.

- `$frequent_items(error_type = "no_false_positives", threshold = NULL)`:

  A data frame of items whose estimated frequency exceeds `threshold`
  (defaults to `$maximum_error()`), with columns `item`, `estimate`,
  `lower_bound`, and `upper_bound`.

- `$maximum_error()`, `$epsilon()`, `$total_weight()`,
  `$num_active_items()`, `$is_empty()`:

  Metadata accessors.

- `$summary()`, `$inspect()`, `$serialize()`:

  Structured metadata, verbose debug output, and the native byte
  payload.

## Details

At most one of `x` or `bytes` may be supplied:

- Pass `x` to build a sketch and immediately update it with a character
  vector (optionally with `weight`).

- Pass `bytes` to reconstruct a sketch from a native serialized payload
  (as produced by `sketch$serialize()`). `lg_max_map_size` and
  `lg_start_map_size` are restored from the payload and must not be
  supplied alongside `bytes`.

- Pass neither for an empty sketch with the given `lg_max_map_size` and
  `lg_start_map_size`.

`NA_character_` is silently ignored by
[`update()`](https://rdrr.io/r/stats/update.html), matching the
missing-value policy used across families; there is no `na_rm` argument.

## Examples

``` r
words <- sample(letters[1:5], 1000, replace = TRUE, prob = c(.5, .25, .1, .1, .05))
sketch <- frequent_items(words)
sketch$frequent_items()
#>   item estimate lower_bound upper_bound
#> 1    a      518         518         518
#> 2    b      236         236         236
#> 3    d       98          98          98
#> 4    c       96          96          96
#> 5    e       52          52          52
sketch$estimate("a")
#> [1] 518

# Round-trip through the native byte format.
restored <- frequent_items(bytes = sketch$serialize())
identical(restored$total_weight(), sketch$total_weight())
#> [1] TRUE
```
