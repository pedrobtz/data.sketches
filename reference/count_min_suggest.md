# Suggest Count-Min sketch parameters

Helpers to translate a desired accuracy into the `num_buckets` and
`num_hashes` arguments of
[`count_min()`](https://pedrobtz.github.io/data.sketches/reference/count_min.md).

## Usage

``` r
count_min_suggest_num_buckets(relative_error)

count_min_suggest_num_hashes(confidence)
```

## Arguments

- relative_error:

  Desired relative error, a single positive number.
  `count_min_suggest_num_buckets()` returns the smallest `num_buckets`
  such that the sketch's `$relative_error()` does not exceed this value.

- confidence:

  Desired confidence, a single number in `(0, 1]`.
  `count_min_suggest_num_hashes()` returns the smallest `num_hashes`
  such that, with this probability, `$estimate()` is within
  `$relative_error()` of the true frequency.

## Value

A single integer.

## Examples

``` r
num_buckets <- count_min_suggest_num_buckets(0.05)
num_hashes <- count_min_suggest_num_hashes(0.95)
sketch <- count_min(num_hashes = num_hashes, num_buckets = num_buckets)
```
