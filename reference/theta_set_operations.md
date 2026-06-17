# Theta sketch set operations

Combine two
[`theta()`](https://pedrobtz.github.io/data.sketches/reference/theta.md)
sketches into a new compact `theta_sketch` result, without mutating
either input. `a` and `b` must be Theta sketches created with the same
`seed` (a mismatch raises `datasketches_seed_mismatch`).

## Usage

``` r
theta_union(a, b, lg_k = NULL)

theta_intersection(a, b)

theta_difference(a, b)

theta_jaccard(a, b)
```

## Arguments

- a, b:

  `theta_sketch` objects created with the same `seed`.

- lg_k:

  For `theta_union()`, log2 of the nominal number of entries for the
  union's internal sketch, a single whole number in `[5, 26]`. Defaults
  to the larger of `a` and `b`'s configured `lg_k` (or `12` for compact
  inputs).

## Value

A compact `theta_sketch` object (`theta_union()`,
`theta_intersection()`, `theta_difference()`), or a named numeric vector
`c(lower_bound, estimate, upper_bound)` (`theta_jaccard()`).

## Details

- `theta_union(a, b)` estimates the size of the union `union(A, B)`.

- `theta_intersection(a, b)` estimates the size of the intersection
  `intersection(A, B)`.

- `theta_difference(a, b)` estimates the size of the set difference
  `A \\ B` (elements in `A` but not `B`).

- `theta_jaccard(a, b)` estimates the [Jaccard similarity
  index](https://en.wikipedia.org/wiki/Jaccard_index)
  `J(A, B) = |intersection(A, B)| / |union(A, B)|`, returning a named
  numeric vector `c(lower_bound, estimate, upper_bound)` for a ~95%
  confidence interval.

## Examples

``` r
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
