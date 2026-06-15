# Tests for the REQ public surface. Mirrors test-quantiles-kll-doubles.R where
# the API overlaps; REQ-specific behavior (hra, rank bounds) gets its own
# tests. REQ compaction is randomized, so assertions use exact streams
# (n < k stays exact) or error bounds rather than exact retained samples (see
# `_dev/WORKING-ON.md`, Randomness and Seeds).

test_that("req() builds an empty sketch with the default width and hra", {
  s <- req()
  expect_s3_class(s, "req_sketch")
  expect_true(s$is_empty())
  expect_equal(s$n(), 0)
  expect_equal(s$k(), 12L)
  expect_true(s$is_hra())
  expect_false(s$is_estimation_mode())
})

test_that("req(k =) sets the width and validates the range and parity", {
  expect_equal(req(k = 20)$k(), 20L)

  expect_error(req(k = 2), class = "datasketches_invalid_k")
  expect_error(req(k = 2000), class = "datasketches_invalid_k")
  expect_error(req(k = 13), class = "datasketches_invalid_k")
  expect_error(req(k = c(12, 20)), class = "datasketches_invalid_k")
})

test_that("req(hra =) sets the high-rank-accuracy flag", {
  expect_true(req(hra = TRUE)$is_hra())
  expect_false(req(hra = FALSE)$is_hra())
  expect_error(req(hra = NA), class = "datasketches_invalid_flag")
})

test_that("req(x =) updates the sketch and reports exact stats below k", {
  s <- req(as.double(1:10))
  expect_equal(s$n(), 10)
  expect_false(s$is_estimation_mode())
  expect_equal(s$min(), 1)
  expect_equal(s$max(), 10)
})

test_that("update() silently ignores NA and NaN", {
  s <- req()
  s$update(c(1, 2, NA, NaN, 5))
  expect_equal(s$n(), 3)
  expect_invisible(s$update(10))
})

test_that("update() rejects non-numeric input", {
  s <- req()
  expect_error(s$update("a"), class = "datasketches_invalid_input")
})

test_that("quantile() is vectorized, shape-preserving, and ordered", {
  s <- req(as.double(1:1000))
  q <- s$quantile(c(0.25, 0.5, 0.75))
  expect_length(q, 3)
  expect_false(is.unsorted(q))
  expect_length(s$quantile(0.5), 1)
})

test_that("quantile() rejects probabilities outside [0, 1] and missing values", {
  s <- req(as.double(1:100))
  expect_error(s$quantile(NA), class = "datasketches_invalid_prob")
  expect_error(s$quantile(1.5), class = "datasketches_invalid_prob")
  expect_error(s$quantile(-0.1), class = "datasketches_invalid_prob")
})

test_that("rank() is vectorized and propagates NA to the output position", {
  s <- req(as.double(1:1000))
  r <- s$rank(c(250, NA, 750))
  expect_length(r, 3)
  expect_true(is.na(r[2]))
  expect_true(r[1] < r[3])
  expect_true(all(r[c(1, 3)] >= 0 & r[c(1, 3)] <= 1))
})

test_that("cdf() and pmf() return length(split_points) + 1 values", {
  s <- req(as.double(1:1000))
  expect_length(s$cdf(c(250, 500, 750)), 4)
  expect_length(s$pmf(c(250, 500, 750)), 4)
  expect_equal(sum(s$pmf(c(250, 500, 750))), 1)
  cdf <- s$cdf(c(250, 500, 750))
  expect_false(is.unsorted(cdf))
  expect_equal(cdf[length(cdf)], 1)
})

test_that("cdf()/pmf() reject unordered, non-finite, or missing split points", {
  s <- req(as.double(1:100))
  expect_error(s$cdf(c(3, 1, 2)), class = "datasketches_invalid_split_points")
  expect_error(s$pmf(c(1, NA, 3)), class = "datasketches_invalid_split_points")
  expect_error(s$cdf(c(1, Inf)), class = "datasketches_invalid_split_points")
})

test_that("inclusive flag must be a single non-missing logical", {
  s <- req(as.double(1:100))
  expect_error(
    s$quantile(0.5, inclusive = NA),
    class = "datasketches_invalid_flag"
  )
  expect_error(
    s$rank(1, inclusive = "yes"),
    class = "datasketches_invalid_flag"
  )
})

test_that("rank_lower_bound()/rank_upper_bound() are vectorized and bracket the rank", {
  s <- req(as.double(1:10000))
  probs <- c(0.1, 0.5, 0.9)
  lo <- s$rank_lower_bound(probs)
  hi <- s$rank_upper_bound(probs)
  expect_length(lo, 3)
  expect_length(hi, 3)
  expect_true(all(lo <= probs))
  expect_true(all(hi >= probs))
})

test_that("rank_lower_bound()/rank_upper_bound() validate num_std_dev", {
  s <- req(as.double(1:100))
  expect_error(
    s$rank_lower_bound(0.5, num_std_dev = 4),
    class = "datasketches_invalid_num_std_dev"
  )
  expect_error(
    s$rank_upper_bound(0.5, num_std_dev = NA),
    class = "datasketches_invalid_num_std_dev"
  )
})

test_that("metadata accessors agree with summary()", {
  s <- req(as.double(1:1000))
  info <- summary(s)
  expect_type(info, "list")
  expect_equal(info$type, "req")
  expect_equal(info$n, s$n())
  expect_equal(info$k, s$k())
  expect_equal(info$hra, s$is_hra())
  expect_equal(info$num_retained, s$num_retained())
  expect_equal(info$min, s$min())
  expect_equal(info$max, s$max())
})

test_that("summary() is safe on an empty sketch", {
  info <- summary(req())
  expect_true(info$is_empty)
  expect_identical(info$min, NA_real_)
  expect_identical(info$max, NA_real_)
})

test_that("merge() combines sketches and mutates the receiver", {
  a <- req(as.double(1:500))
  b <- req(as.double(501:1000))
  expect_invisible(a$merge(b))
  expect_equal(a$n(), 1000)
  expect_equal(a$max(), 1000)
})

test_that("merge() rejects self-merge, including aliases", {
  a <- req(as.double(1:100))
  expect_error(a$merge(a), class = "datasketches_self_merge")
  alias <- a
  expect_error(a$merge(alias), class = "datasketches_self_merge")
})

test_that("merge() rejects a non-sketch argument", {
  a <- req(as.double(1:100))
  expect_error(a$merge(42), class = "datasketches_invalid_sketch")

  fake <- structure(new.env(), class = "req_sketch")
  expect_error(a$merge(fake), class = "datasketches_invalid_sketch")
})

test_that("format() and as.character() give the same concise representation", {
  s <- req(as.double(1:100))
  expect_identical(format(s), as.character(s))
  expect_match(format(s), "^<req_sketch\\[n=100, k=12, hra(, estimation)?\\]>$")
})

test_that("print() returns the sketch invisibly", {
  s <- req(as.double(1:100))
  expect_output(out <- print(s), "req_sketch")
  expect_identical(out, s)
})

test_that("inspect() writes the upstream debug string", {
  s <- req(as.double(1:100))
  expect_output(s$inspect(), "REQ sketch summary")
})

test_that("serialize() round-trips through the bytes constructor", {
  s <- req(as.double(1:1000))
  bytes <- s$serialize()
  expect_type(bytes, "raw")

  restored <- req(bytes = bytes)
  expect_equal(restored$n(), s$n())
  expect_equal(restored$is_hra(), s$is_hra())
  expect_equal(
    restored$quantile(c(0.1, 0.5, 0.9)),
    s$quantile(c(0.1, 0.5, 0.9))
  )
})

test_that("constructor exclusivity is enforced", {
  bytes <- req(as.double(1:100))$serialize()
  expect_error(
    req(x = 1:10, bytes = bytes),
    class = "datasketches_invalid_args"
  )
  expect_error(
    req(bytes = bytes, k = 12),
    class = "datasketches_invalid_args"
  )
  expect_error(
    req(bytes = bytes, hra = TRUE),
    class = "datasketches_invalid_args"
  )
  expect_error(
    req(bytes = "not raw"),
    class = "datasketches_invalid_args"
  )
})
