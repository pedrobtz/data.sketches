# Tests for the Theta public surface, including the set-operation functions
# (theta_union/intersection/difference/jaccard). Theta estimates are
# approximate and depend on internal hashing, so assertions use error-bound
# brackets (`lower_bound()`/`upper_bound()`) rather than exact counts (see
# `_dev/WORKING-ON.md`, Randomness and Seeds).

test_that("theta() builds an empty sketch with the default lg_k and seed", {
  s <- theta()
  expect_s3_class(s, "theta_sketch")
  expect_true(s$is_empty())
  expect_false(s$is_compact())
  expect_equal(s$lg_k(), 12L)
  expect_equal(s$seed(), 9001)
  expect_equal(s$estimate(), 0)
})

test_that("theta(lg_k =) sets the configuration and validates the range", {
  expect_equal(theta(lg_k = 10)$lg_k(), 10L)

  expect_error(theta(lg_k = 4), class = "datasketches_invalid_lg_k")
  expect_error(theta(lg_k = 27), class = "datasketches_invalid_lg_k")
  expect_error(theta(lg_k = c(10, 12)), class = "datasketches_invalid_lg_k")
})

test_that("theta(seed =) sets the hash seed and validates it", {
  expect_equal(theta(seed = 123)$seed(), 123)
  expect_equal(theta(seed = 2^53)$seed(), 2^53)

  expect_error(theta(seed = -1), class = "datasketches_invalid_seed")
  expect_error(theta(seed = 1.5), class = "datasketches_invalid_seed")
  expect_error(theta(seed = NA), class = "datasketches_invalid_seed")
  expect_error(theta(seed = Inf), class = "datasketches_invalid_seed")
  expect_error(theta(seed = 2^53 + 2), class = "datasketches_invalid_seed")
})

test_that("theta(x =) updates the sketch with numeric input", {
  s <- theta(as.double(1:1000))
  expect_false(s$is_empty())
  expect_true(s$estimate() >= s$lower_bound())
  expect_true(s$estimate() <= s$upper_bound())
  # 3 std dev (~99.7%) bound around the estimate brackets the true count.
  expect_true(s$lower_bound(3) <= 1000 && s$upper_bound(3) >= 1000)
})

test_that("update() accepts character input", {
  s <- theta()
  s$update(letters)
  expect_false(s$is_empty())
  expect_true(s$estimate() > 0)
})

test_that("update() silently ignores NA, NaN, and NA_character_", {
  s <- theta()
  s$update(c(1, 2, NA, NaN, 3))
  expect_true(s$estimate() > 0)
  expect_invisible(s$update(4))

  s2 <- theta()
  expect_invisible(s2$update(c("a", NA, "b")))
  expect_true(s2$estimate() > 0)
})

test_that("update() rejects input that is neither numeric nor character", {
  s <- theta()
  expect_error(s$update(TRUE), class = "datasketches_invalid_input")
  expect_error(s$update(list(1, 2)), class = "datasketches_invalid_input")
})

test_that("update() errors on a compact sketch", {
  s <- theta(bytes = theta(as.double(1:100))$serialize())
  expect_true(s$is_compact())
  expect_error(s$update(1), class = "datasketches_invalid_op")
})

test_that("lower_bound()/upper_bound() bracket estimate() and validate num_std_dev", {
  s <- theta(as.double(1:10000))
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
  s <- theta(bytes = theta(as.double(1:100))$serialize())
  expect_error(s$lg_k(), class = "datasketches_invalid_op")
})

test_that("metadata accessors agree with summary()", {
  s <- theta(as.double(1:1000))
  info <- summary(s)
  expect_type(info, "list")
  expect_equal(info$type, "theta")
  expect_equal(info$is_compact, s$is_compact())
  expect_equal(info$lg_k, s$lg_k())
  expect_equal(info$seed, s$seed())
  expect_equal(info$is_empty, s$is_empty())
  expect_equal(info$is_estimation_mode, s$is_estimation_mode())
  expect_equal(info$estimate, s$estimate())
  expect_equal(info$lower_bound, s$lower_bound())
  expect_equal(info$upper_bound, s$upper_bound())
  expect_equal(info$theta, s$theta())
  expect_equal(info$num_retained, s$num_retained())
})

test_that("summary() reports NA lg_k for a compact sketch", {
  s <- theta(bytes = theta(as.double(1:100))$serialize())
  info <- summary(s)
  expect_true(info$is_compact)
  expect_identical(info$lg_k, NA_integer_)
})

test_that("merge() combines sketches, mutates the receiver, and becomes compact", {
  a <- theta(as.double(1:500))
  b <- theta(as.double(501:1000))
  expect_invisible(a$merge(b))
  expect_true(a$is_compact())
  expect_true(a$lower_bound(3) <= 1000 && a$upper_bound(3) >= 1000)
})

test_that("merge() rejects self-merge, including aliases", {
  a <- theta(as.double(1:100))
  expect_error(a$merge(a), class = "datasketches_self_merge")
  alias <- a
  expect_error(a$merge(alias), class = "datasketches_self_merge")
})

test_that("merge() rejects a non-sketch argument", {
  a <- theta(as.double(1:100))
  expect_error(a$merge(42), class = "datasketches_invalid_sketch")

  fake <- structure(new.env(), class = "theta_sketch")
  expect_error(a$merge(fake), class = "datasketches_invalid_sketch")
})

test_that("merge() rejects sketches with different seeds", {
  a <- theta(as.double(1:100), seed = 1)
  b <- theta(as.double(101:200), seed = 2)
  expect_error(a$merge(b), class = "datasketches_seed_mismatch")
})

test_that("merge() combines sketches with different lg_k", {
  a <- theta(as.double(1:500), lg_k = 10)
  b <- theta(as.double(501:1000), lg_k = 14)
  expect_invisible(a$merge(b))
  expect_true(a$lower_bound(3) <= 1000 && a$upper_bound(3) >= 1000)
})

test_that("format() and as.character() give the same concise representation", {
  s <- theta(as.double(1:1000))
  expect_identical(format(s), as.character(s))
  expect_match(format(s), "^<theta_sketch\\[lg_k=12, estimate=.+\\]>$")

  empty <- theta()
  expect_match(format(empty), "^<theta_sketch\\[lg_k=12, empty\\]>$")

  compact <- theta(bytes = s$serialize())
  expect_match(format(compact), "^<theta_sketch\\[compact, estimate=.+\\]>$")
})

test_that("print() returns the sketch invisibly", {
  s <- theta(as.double(1:100))
  expect_output(out <- print(s), "theta_sketch")
  expect_identical(out, s)
})

test_that("inspect() writes the upstream debug string", {
  s <- theta(as.double(1:100))
  expect_output(s$inspect(), "Theta sketch")
})

test_that("serialize() round-trips through the bytes constructor as a compact sketch", {
  s <- theta(as.double(1:1000))
  bytes <- s$serialize()
  expect_type(bytes, "raw")

  restored <- theta(bytes = bytes)
  expect_true(restored$is_compact())
  expect_equal(restored$estimate(), s$estimate())
})

test_that("serialize() round-trips with a non-default seed", {
  s <- theta(as.double(1:1000), seed = 123)
  bytes <- s$serialize()

  restored <- theta(bytes = bytes, seed = 123)
  expect_equal(restored$estimate(), s$estimate())
})

test_that("constructor exclusivity is enforced", {
  bytes <- theta(as.double(1:100))$serialize()
  expect_error(
    theta(x = 1:10, bytes = bytes),
    class = "datasketches_invalid_args"
  )
  expect_error(
    theta(bytes = bytes, lg_k = 12),
    class = "datasketches_invalid_args"
  )
  expect_error(
    theta(bytes = "not raw"),
    class = "datasketches_invalid_args"
  )
})

# Set operations -------------------------------------------------------------

test_that("theta_union() estimates the size of the union without mutating inputs", {
  a <- theta(as.double(1:1000))
  b <- theta(as.double(501:1500))
  u <- theta_union(a, b)

  expect_s3_class(u, "theta_sketch")
  expect_true(u$is_compact())
  expect_true(u$lower_bound(3) <= 1500 && u$upper_bound(3) >= 1500)

  # inputs are unmutated
  expect_false(a$is_compact())
  expect_true(a$lower_bound(3) <= 1000 && a$upper_bound(3) >= 1000)
})

test_that("theta_union(lg_k =) validates and overrides the default", {
  a <- theta(as.double(1:1000), lg_k = 10)
  b <- theta(as.double(501:1500), lg_k = 10)
  u <- theta_union(a, b, lg_k = 14)
  expect_true(u$lower_bound(3) <= 1500 && u$upper_bound(3) >= 1500)

  expect_error(theta_union(a, b, lg_k = 4), class = "datasketches_invalid_lg_k")
})

test_that("theta_intersection() estimates the size of the intersection", {
  a <- theta(as.double(1:1000))
  b <- theta(as.double(501:1500))
  i <- theta_intersection(a, b)

  expect_s3_class(i, "theta_sketch")
  expect_true(i$is_compact())
  expect_true(i$lower_bound(3) <= 500 && i$upper_bound(3) >= 500)
})

test_that("theta_difference() estimates the size of the set difference", {
  a <- theta(as.double(1:1000))
  b <- theta(as.double(501:1500))
  d <- theta_difference(a, b)

  expect_s3_class(d, "theta_sketch")
  expect_true(d$is_compact())
  expect_true(d$lower_bound(3) <= 500 && d$upper_bound(3) >= 500)
})

test_that("theta_jaccard() returns lower/estimate/upper bounds", {
  a <- theta(as.double(1:1000))
  b <- theta(as.double(1:1000))
  j <- theta_jaccard(a, b)

  expect_named(j, c("lower_bound", "estimate", "upper_bound"))
  expect_equal(j[["lower_bound"]], 1)
  expect_equal(j[["estimate"]], 1)
  expect_equal(j[["upper_bound"]], 1)

  disjoint <- theta(as.double(1001:2000))
  j2 <- theta_jaccard(a, disjoint)
  expect_equal(j2[["estimate"]], 0)
})

test_that("set operations reject non-sketch arguments and seed mismatches", {
  a <- theta(as.double(1:100))
  b <- theta(as.double(1:100), seed = 123)

  expect_error(theta_union(a, 42), class = "datasketches_invalid_sketch")
  expect_error(theta_intersection(a, 42), class = "datasketches_invalid_sketch")
  expect_error(theta_difference(a, 42), class = "datasketches_invalid_sketch")
  expect_error(theta_jaccard(a, 42), class = "datasketches_invalid_sketch")

  expect_error(theta_union(a, b), class = "datasketches_seed_mismatch")
  expect_error(theta_intersection(a, b), class = "datasketches_seed_mismatch")
  expect_error(theta_difference(a, b), class = "datasketches_seed_mismatch")
  expect_error(theta_jaccard(a, b), class = "datasketches_seed_mismatch")
})

test_that("set operations work on compact (deserialized) sketches", {
  a <- theta(bytes = theta(as.double(1:1000))$serialize())
  b <- theta(bytes = theta(as.double(501:1500))$serialize())

  u <- theta_union(a, b)
  expect_true(u$lower_bound(3) <= 1500 && u$upper_bound(3) >= 1500)
})
