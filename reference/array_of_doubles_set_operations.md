# Array of Doubles sketch set operations

Combine two
[`array_of_doubles()`](https://pedrobtz.github.io/data.sketches/reference/array_of_doubles.md)
sketches into a new compact `array_of_doubles_sketch` result, without
mutating either input. `a` and `b` must be Array of Doubles sketches
created with the same `seed` (a mismatch raises
`datasketches_seed_mismatch`).

## Usage

``` r
array_of_doubles_union(a, b, lg_k = NULL)

array_of_doubles_intersection(a, b)

array_of_doubles_difference(a, b)
```

## Arguments

- a, b:

  `array_of_doubles_sketch` objects created with the same `seed`.

- lg_k:

  For `array_of_doubles_union()`, log2 of the nominal number of entries
  for the union's internal sketch, a single whole number in `[5, 26]`.
  Defaults to the larger of `a` and `b`'s configured `lg_k` (or `12` for
  compact inputs).

## Value

A compact `array_of_doubles_sketch` object.

## Details

- `array_of_doubles_union(a, b)` estimates the size of the union
  `union(A, B)`. `a` and `b` must also share the same `num_values` (a
  mismatch raises `datasketches_incompatible_sketch`); value arrays for
  matching keys are combined by element-wise sum.

- `array_of_doubles_intersection(a, b)` estimates the size of the
  intersection `intersection(A, B)`, with the same `num_values`
  requirement and combining rule as `array_of_doubles_union()`.

- `array_of_doubles_difference(a, b)` estimates the size of the set
  difference `A \\ B` (elements in `A` but not `B`), retaining `a`'s
  value arrays unchanged for the retained keys.

## Examples

``` r
a <- array_of_doubles(1:1000, runif(1000))
b <- array_of_doubles(501:1500, runif(1000))
array_of_doubles_union(a, b)$column_sums()
#> [1] 1005.581
array_of_doubles_intersection(a, b)$estimate()
#> [1] 500
array_of_doubles_difference(a, b)$estimate()
#> [1] 500
```
