# Combine two VarOpt sketches

Combines two
[`varopt()`](https://pedrobtz.github.io/data.sketches/reference/varopt.md)
sketches into a new `varopt_sketch` result, without mutating either
input. `a` and `b` must hold the same item type (a mismatch raises
`datasketches_incompatible_sketch`). The result is sized for the larger
of `a` and `b`'s configured `k`.

## Usage

``` r
varopt_union(a, b)
```

## Arguments

- a, b:

  `varopt_sketch` objects holding the same item type.

## Value

A `varopt_sketch` object.

## Examples

``` r
a <- varopt(1:1000, runif(1000), k = 50)
b <- varopt(501:1500, runif(1000), k = 50)
u <- varopt_union(a, b)
u$k()
#> [1] 50
u$n()
#> [1] 2000
```
