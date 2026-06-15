# Tests for the Array of Doubles (Tuple) public surface, including the
# set-operation functions (array_of_doubles_union/intersection/difference).
# Estimates are approximate and depend on internal hashing, so assertions use
# error-bound brackets (`lower_bound()`/`upper_bound()`) rather than exact
# counts (see `_dev/WORKING-ON.md`, Randomness and Seeds).

test_that("array_of_doubles() builds an empty sketch with defaults", {
  s <- array_of_doubles()
  expect_s3_class(s, "array_of_doubles_sketch")
  expect_true(s$is_empty())
  expect_false(s$is_compact())
  expect_equal(s$lg_k(), 12L)
  expect_equal(s$num_values(), 1L)
  expect_equal(s$seed(), 9001)
  expect_equal(s$estimate(), 0)
})

test_that("array_of_doubles(lg_k =) sets the configuration and validates the range", {
  expect_equal(array_of_doubles(lg_k = 10)$lg_k(), 10L)

  expect_error(array_of_doubles(lg_k = 4), class = "datasketches_invalid_lg_k")
  expect_error(array_of_doubles(lg_k = 27), class = "datasketches_invalid_lg_k")
  expect_error(
    array_of_doubles(lg_k = c(10, 12)),
    class = "datasketches_invalid_lg_k"
  )
})

test_that("array_of_doubles(num_values =) sets the configuration and validates the range", {
  expect_equal(array_of_doubles(num_values = 3)$num_values(), 3L)

  expect_error(
    array_of_doubles(num_values = 0),
    class = "datasketches_invalid_num_values"
  )
  expect_error(
    array_of_doubles(num_values = 256),
    class = "datasketches_invalid_num_values"
  )
  expect_error(
    array_of_doubles(num_values = 1.5),
    class = "datasketches_invalid_num_values"
  )
  expect_error(
    array_of_doubles(num_values = NA),
    class = "datasketches_invalid_num_values"
  )
})

test_that("array_of_doubles(seed =) sets the hash seed and validates it", {
  expect_equal(array_of_doubles(seed = 123)$seed(), 123)
  expect_equal(array_of_doubles(seed = 2^53)$seed(), 2^53)

  expect_error(array_of_doubles(seed = -1), class = "datasketches_invalid_seed")
  expect_error(
    array_of_doubles(seed = 1.5),
    class = "datasketches_invalid_seed"
  )
  expect_error(array_of_doubles(seed = NA), class = "datasketches_invalid_seed")
  expect_error(
    array_of_doubles(seed = Inf),
    class = "datasketches_invalid_seed"
  )
  expect_error(
    array_of_doubles(seed = 2^53 + 2),
    class = "datasketches_invalid_seed"
  )
})

test_that("array_of_doubles(x =) updates the sketch with numeric input", {
  s <- array_of_doubles(as.double(1:1000))
  expect_false(s$is_empty())
  expect_true(s$estimate() >= s$lower_bound())
  expect_true(s$estimate() <= s$upper_bound())
  # 3 std dev (~99.7%) bound around the estimate brackets the true count.
  expect_true(s$lower_bound(3) <= 1000 && s$upper_bound(3) >= 1000)
  # default values are 1s, so column_sums() ~ estimate()
  expect_equal(s$column_sums(), s$estimate())
})

test_that("update() accepts character input", {
  s <- array_of_doubles()
  s$update(letters)
  expect_false(s$is_empty())
  expect_true(s$estimate() > 0)
})

test_that("update() with default values sums to estimate()", {
  s <- array_of_doubles()
  s$update(1:100)
  expect_equal(s$column_sums(), s$estimate())
})

test_that("update(values =) accepts a numeric vector for num_values == 1", {
  s <- array_of_doubles(num_values = 1)
  s$update(1:5, values = c(10, 20, 30, 40, 50))
  expect_equal(s$column_sums(), 150)
})

test_that("update(values =) recycles a single value to all elements", {
  s <- array_of_doubles(num_values = 1)
  s$update(1:5, values = 2)
  expect_equal(s$column_sums(), 10)
})

test_that("update(values =) accepts a matrix with num_values columns", {
  s <- array_of_doubles(num_values = 3)
  s$update(1:3, values = matrix(1:9, ncol = 3, byrow = TRUE))
  expect_equal(s$column_sums(), c(12, 15, 18))
})

test_that("update(values =) recycles a single matrix row to all elements", {
  s <- array_of_doubles(num_values = 2)
  s$update(1:4, values = matrix(c(1, 2), nrow = 1))
  expect_equal(s$column_sums(), c(4, 8))
})

test_that("update(values =) validates shape and content", {
  s <- array_of_doubles(num_values = 2)
  expect_error(
    s$update(1:3, values = matrix(1:9, ncol = 3)),
    class = "datasketches_invalid_input"
  )
  expect_error(
    s$update(1:3, values = 1:2),
    class = "datasketches_invalid_input"
  )
  expect_error(
    s$update(1:3, values = c(1, NA, 3)),
    class = "datasketches_invalid_input"
  )
  expect_error(
    s$update(1:3, values = "a"),
    class = "datasketches_invalid_input"
  )

  s1 <- array_of_doubles(num_values = 1)
  expect_error(
    s1$update(1:3, values = matrix(1:6, ncol = 2)),
    class = "datasketches_invalid_input"
  )
})

test_that("array_of_doubles() rejects values without x", {
  expect_error(
    array_of_doubles(values = 1),
    class = "datasketches_invalid_args"
  )
})

test_that("update() silently ignores NA, NaN, and NA_character_", {
  s <- array_of_doubles()
  s$update(c(1, 2, NA, NaN, 3))
  expect_true(s$estimate() > 0)
  expect_invisible(s$update(4))

  s2 <- array_of_doubles()
  expect_invisible(s2$update(c("a", NA, "b")))
  expect_true(s2$estimate() > 0)
})

test_that("update() drops the values row for NA elements of x", {
  s <- array_of_doubles(num_values = 1)
  s$update(c(1, NA, 3), values = c(10, 999, 30))
  expect_equal(s$column_sums(), 40)
})

test_that("update() rejects input that is neither numeric nor character", {
  s <- array_of_doubles()
  expect_error(s$update(TRUE), class = "datasketches_invalid_input")
  expect_error(s$update(list(1, 2)), class = "datasketches_invalid_input")
})

test_that("update() errors on a compact sketch", {
  s <- array_of_doubles(bytes = array_of_doubles(as.double(1:100))$serialize())
  expect_true(s$is_compact())
  expect_error(s$update(1), class = "datasketches_invalid_op")
})

test_that("lower_bound()/upper_bound() bracket estimate() and validate num_std_dev", {
  s <- array_of_doubles(as.double(1:10000))
  lo <- s$lower_bound()
  hi <- s$upper_bound()
  expect_true(lo <= s$estimate())
  expect_true(hi >= s$estimate())

  expect_error(
    s$lower_bound(num_std_dev = 4),
    class = "datasketches_invalid_num_std_dev"
  )
  expect_error(
    s$upper_bound(num_std_dev = NA),
    class = "datasketches_invalid_num_std_dev"
  )
})

test_that("lg_k() errors on a compact sketch", {
  s <- array_of_doubles(bytes = array_of_doubles(as.double(1:100))$serialize())
  expect_error(s$lg_k(), class = "datasketches_invalid_op")
})

test_that("metadata accessors agree with summary()", {
  s <- array_of_doubles(as.double(1:1000), num_values = 1)
  info <- summary(s)
  expect_type(info, "list")
  expect_equal(info$type, "array_of_doubles")
  expect_equal(info$is_compact, s$is_compact())
  expect_equal(info$lg_k, s$lg_k())
  expect_equal(info$num_values, s$num_values())
  expect_equal(info$seed, s$seed())
  expect_equal(info$is_empty, s$is_empty())
  expect_equal(info$is_estimation_mode, s$is_estimation_mode())
  expect_equal(info$estimate, s$estimate())
  expect_equal(info$lower_bound, s$lower_bound())
  expect_equal(info$upper_bound, s$upper_bound())
  expect_equal(info$theta, s$theta())
  expect_equal(info$num_retained, s$num_retained())
  expect_equal(info$column_sums, s$column_sums())
})

test_that("summary() reports NA lg_k for a compact sketch", {
  s <- array_of_doubles(bytes = array_of_doubles(as.double(1:100))$serialize())
  info <- summary(s)
  expect_true(info$is_compact)
  expect_identical(info$lg_k, NA_integer_)
})

test_that("merge() combines sketches, mutates the receiver, and becomes compact", {
  a <- array_of_doubles(as.double(1:500))
  b <- array_of_doubles(as.double(501:1000))
  expect_invisible(a$merge(b))
  expect_true(a$is_compact())
  expect_true(a$lower_bound(3) <= 1000 && a$upper_bound(3) >= 1000)
})

test_that("merge() combines value arrays by element-wise sum", {
  a <- array_of_doubles(num_values = 1)
  a$update(1:5, values = rep(1, 5))
  b <- array_of_doubles(num_values = 1)
  b$update(1:5, values = rep(10, 5))

  a$merge(b)
  expect_equal(a$column_sums(), 55)
})

test_that("merge() rejects self-merge, including aliases", {
  a <- array_of_doubles(as.double(1:100))
  expect_error(a$merge(a), class = "datasketches_self_merge")
  alias <- a
  expect_error(a$merge(alias), class = "datasketches_self_merge")
})

test_that("merge() rejects a non-sketch argument", {
  a <- array_of_doubles(as.double(1:100))
  expect_error(a$merge(42), class = "datasketches_invalid_sketch")

  fake <- structure(new.env(), class = "array_of_doubles_sketch")
  expect_error(a$merge(fake), class = "datasketches_invalid_sketch")
})

test_that("merge() rejects sketches with different seeds", {
  a <- array_of_doubles(as.double(1:100), seed = 1)
  b <- array_of_doubles(as.double(101:200), seed = 2)
  expect_error(a$merge(b), class = "datasketches_seed_mismatch")
})

test_that("merge() rejects sketches with different num_values", {
  a <- array_of_doubles(as.double(1:100), num_values = 1)
  b <- array_of_doubles(as.double(101:200), num_values = 2)
  expect_error(a$merge(b), class = "datasketches_incompatible_sketch")
})

test_that("merge() combines sketches with different lg_k", {
  a <- array_of_doubles(as.double(1:500), lg_k = 10)
  b <- array_of_doubles(as.double(501:1000), lg_k = 14)
  expect_invisible(a$merge(b))
  expect_true(a$lower_bound(3) <= 1000 && a$upper_bound(3) >= 1000)
})

test_that("format() and as.character() give the same concise representation", {
  s <- array_of_doubles(as.double(1:1000))
  expect_identical(format(s), as.character(s))
  expect_match(
    format(s),
    "^<array_of_doubles_sketch\\[lg_k=12, num_values=1, estimate=.+\\]>$"
  )

  empty <- array_of_doubles()
  expect_match(
    format(empty),
    "^<array_of_doubles_sketch\\[lg_k=12, num_values=1, empty\\]>$"
  )

  compact <- array_of_doubles(bytes = s$serialize())
  expect_match(
    format(compact),
    "^<array_of_doubles_sketch\\[compact, num_values=1, estimate=.+\\]>$"
  )
})

test_that("print() returns the sketch invisibly", {
  s <- array_of_doubles(as.double(1:100))
  expect_output(out <- print(s), "array_of_doubles_sketch")
  expect_identical(out, s)
})

test_that("inspect() writes the upstream debug string", {
  s <- array_of_doubles(as.double(1:100))
  expect_output(s$inspect(), "Tuple sketch")
  expect_output(s$inspect(items = TRUE), "Retained entries")
})

test_that("serialize() round-trips through the bytes constructor as a compact sketch", {
  s <- array_of_doubles(as.double(1:1000))
  bytes <- s$serialize()
  expect_type(bytes, "raw")

  restored <- array_of_doubles(bytes = bytes)
  expect_true(restored$is_compact())
  expect_equal(restored$estimate(), s$estimate())
  expect_equal(restored$column_sums(), s$column_sums())
  expect_equal(restored$num_values(), s$num_values())
})

test_that("serialize() round-trips with a non-default seed", {
  s <- array_of_doubles(as.double(1:1000), seed = 123)
  bytes <- s$serialize()

  restored <- array_of_doubles(bytes = bytes, seed = 123)
  expect_equal(restored$estimate(), s$estimate())
})

test_that("constructor exclusivity is enforced", {
  bytes <- array_of_doubles(as.double(1:100))$serialize()
  expect_error(
    array_of_doubles(x = 1:10, bytes = bytes),
    class = "datasketches_invalid_args"
  )
  expect_error(
    array_of_doubles(bytes = bytes, lg_k = 12),
    class = "datasketches_invalid_args"
  )
  expect_error(
    array_of_doubles(bytes = bytes, num_values = 2),
    class = "datasketches_invalid_args"
  )
  expect_error(
    array_of_doubles(bytes = "not raw"),
    class = "datasketches_invalid_args"
  )
})

# Set operations -------------------------------------------------------------

test_that("array_of_doubles_union() estimates the size of the union without mutating inputs", {
  a <- array_of_doubles(as.double(1:1000))
  b <- array_of_doubles(as.double(501:1500))
  u <- array_of_doubles_union(a, b)

  expect_s3_class(u, "array_of_doubles_sketch")
  expect_true(u$is_compact())
  expect_true(u$lower_bound(3) <= 1500 && u$upper_bound(3) >= 1500)

  # inputs are unmutated
  expect_false(a$is_compact())
  expect_true(a$lower_bound(3) <= 1000 && a$upper_bound(3) >= 1000)
})

test_that("array_of_doubles_union(lg_k =) validates and overrides the default", {
  a <- array_of_doubles(as.double(1:1000), lg_k = 10)
  b <- array_of_doubles(as.double(501:1500), lg_k = 10)
  u <- array_of_doubles_union(a, b, lg_k = 14)
  expect_true(u$lower_bound(3) <= 1500 && u$upper_bound(3) >= 1500)

  expect_error(
    array_of_doubles_union(a, b, lg_k = 4),
    class = "datasketches_invalid_lg_k"
  )
})

test_that("array_of_doubles_union() sums value arrays for matching keys", {
  a <- array_of_doubles(num_values = 1)
  a$update(1:1000, values = rep(1, 1000))
  b <- array_of_doubles(num_values = 1)
  b$update(501:1500, values = rep(10, 1000))

  u <- array_of_doubles_union(a, b)
  expect_true(u$lower_bound(3) <= 1500 && u$upper_bound(3) >= 1500)
})

test_that("array_of_doubles_intersection() estimates the size of the intersection", {
  a <- array_of_doubles(as.double(1:1000))
  b <- array_of_doubles(as.double(501:1500))
  i <- array_of_doubles_intersection(a, b)

  expect_s3_class(i, "array_of_doubles_sketch")
  expect_true(i$is_compact())
  expect_true(i$lower_bound(3) <= 500 && i$upper_bound(3) >= 500)
})

test_that("array_of_doubles_difference() estimates the size of the set difference", {
  a <- array_of_doubles(as.double(1:1000))
  b <- array_of_doubles(as.double(501:1500))
  d <- array_of_doubles_difference(a, b)

  expect_s3_class(d, "array_of_doubles_sketch")
  expect_true(d$is_compact())
  expect_true(d$lower_bound(3) <= 500 && d$upper_bound(3) >= 500)
})

test_that("set operations reject non-sketch arguments and seed mismatches", {
  a <- array_of_doubles(as.double(1:100))
  b <- array_of_doubles(as.double(1:100), seed = 123)

  expect_error(
    array_of_doubles_union(a, 42),
    class = "datasketches_invalid_sketch"
  )
  expect_error(
    array_of_doubles_intersection(a, 42),
    class = "datasketches_invalid_sketch"
  )
  expect_error(
    array_of_doubles_difference(a, 42),
    class = "datasketches_invalid_sketch"
  )

  expect_error(
    array_of_doubles_union(a, b),
    class = "datasketches_seed_mismatch"
  )
  expect_error(
    array_of_doubles_intersection(a, b),
    class = "datasketches_seed_mismatch"
  )
  expect_error(
    array_of_doubles_difference(a, b),
    class = "datasketches_seed_mismatch"
  )
})

test_that("set operations reject num_values mismatches", {
  a <- array_of_doubles(as.double(1:100), num_values = 1)
  b <- array_of_doubles(as.double(1:100), num_values = 2)

  expect_error(
    array_of_doubles_union(a, b),
    class = "datasketches_incompatible_sketch"
  )
  expect_error(
    array_of_doubles_intersection(a, b),
    class = "datasketches_incompatible_sketch"
  )
})

test_that("set operations work on compact (deserialized) sketches", {
  a <- array_of_doubles(bytes = array_of_doubles(as.double(1:1000))$serialize())
  b <- array_of_doubles(
    bytes = array_of_doubles(as.double(501:1500))$serialize()
  )

  u <- array_of_doubles_union(a, b)
  expect_true(u$lower_bound(3) <= 1500 && u$upper_bound(3) >= 1500)
})
