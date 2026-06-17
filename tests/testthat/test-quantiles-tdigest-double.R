# Tests for the t-Digest double public surface. t-Digest compaction is
# deterministic given an input order, but assertions favor error bounds and
# ordering checks over exact retained samples, mirroring the KLL doubles tests.

test_that("tdigest_double() builds an empty sketch of the default width", {
  s <- tdigest_double()
  expect_s3_class(s, "tdigest_double_sketch")
  expect_true(s$is_empty())
  expect_equal(s$n(), 0)
  expect_equal(s$k(), 200L)
})

test_that("tdigest_double(k =) sets the width and validates the range", {
  expect_equal(tdigest_double(k = 64)$k(), 64L)

  expect_error(tdigest_double(k = 9), class = "datasketches_invalid_k")
  expect_error(tdigest_double(k = 70000), class = "datasketches_invalid_k")
  expect_error(tdigest_double(k = 100.5), class = "datasketches_invalid_k")
  expect_error(
    tdigest_double(k = c(200, 300)),
    class = "datasketches_invalid_k"
  )
})

test_that("tdigest_double(x =) updates the sketch and reports exact min/max", {
  s <- tdigest_double(as.double(1:100))
  expect_equal(s$n(), 100)
  expect_equal(s$min(), 1)
  expect_equal(s$max(), 100)
})

test_that("update() silently ignores NA and NaN", {
  s <- tdigest_double()
  s$update(c(1, 2, NA, NaN, 5))
  expect_equal(s$n(), 3)
  expect_invisible(s$update(10))
})

test_that("update() rejects non-numeric input", {
  s <- tdigest_double()
  expect_error(s$update("a"), class = "datasketches_invalid_input")
})

test_that("quantile() is vectorized, shape-preserving, and ordered", {
  s <- tdigest_double(as.double(1:1000))
  q <- s$quantile(c(0.25, 0.5, 0.75))
  expect_length(q, 3)
  expect_false(is.unsorted(q))
  expect_length(s$quantile(0.5), 1)
})

test_that("quantile() is accurate near the tails", {
  set.seed(123)
  x <- rnorm(50000)
  s <- tdigest_double(x)
  expect_equal(
    s$quantile(0.999),
    quantile(x, 0.999, names = FALSE),
    tolerance = 0.05
  )
  expect_equal(
    s$quantile(0.001),
    quantile(x, 0.001, names = FALSE),
    tolerance = 0.05
  )
})

test_that("quantile() rejects probabilities outside [0, 1] and missing values", {
  s <- tdigest_double(as.double(1:100))
  expect_error(s$quantile(NA), class = "datasketches_invalid_prob")
  expect_error(s$quantile(1.5), class = "datasketches_invalid_prob")
  expect_error(s$quantile(-0.1), class = "datasketches_invalid_prob")
})

test_that("rank() is vectorized and propagates NA to the output position", {
  s <- tdigest_double(as.double(1:1000))
  r <- s$rank(c(250, NA, 750))
  expect_length(r, 3)
  expect_true(is.na(r[2]))
  expect_true(r[1] < r[3])
  expect_true(all(r[c(1, 3)] >= 0 & r[c(1, 3)] <= 1))
})

test_that("quantile() and rank() on an empty sketch raise an error", {
  s <- tdigest_double()
  expect_error(s$quantile(0.5))
  expect_error(s$rank(1))
  expect_error(s$min())
  expect_error(s$max())
})

test_that("cdf() and pmf() return length(split_points) + 1 values", {
  s <- tdigest_double(as.double(1:1000))
  expect_length(s$cdf(c(250, 500, 750)), 4)
  expect_length(s$pmf(c(250, 500, 750)), 4)
  # pmf is a distribution over bins
  expect_equal(sum(s$pmf(c(250, 500, 750))), 1)
  # cdf is non-decreasing and ends at 1
  cdf <- s$cdf(c(250, 500, 750))
  expect_false(is.unsorted(cdf))
  expect_equal(cdf[length(cdf)], 1)
})

test_that("cdf()/pmf() reject unordered, non-finite, or missing split points", {
  s <- tdigest_double(as.double(1:100))
  expect_error(s$cdf(c(3, 1, 2)), class = "datasketches_invalid_split_points")
  expect_error(s$pmf(c(1, NA, 3)), class = "datasketches_invalid_split_points")
  expect_error(s$cdf(c(1, Inf)), class = "datasketches_invalid_split_points")
})

test_that("metadata accessors agree with summary()", {
  s <- tdigest_double(as.double(1:1000))
  info <- summary(s)
  expect_type(info, "list")
  expect_equal(info$type, "tdigest_double")
  expect_equal(info$n, s$n())
  expect_equal(info$k, s$k())
  expect_equal(info$min, s$min())
  expect_equal(info$max, s$max())
})

test_that("summary() is safe on an empty sketch", {
  info <- summary(tdigest_double())
  expect_true(info$is_empty)
  expect_identical(info$min, NA_real_)
  expect_identical(info$max, NA_real_)
})

test_that("merge() combines sketches and mutates the receiver", {
  a <- tdigest_double(as.double(1:500))
  b <- tdigest_double(as.double(501:1000))
  expect_invisible(a$merge(b))
  expect_equal(a$n(), 1000)
  expect_equal(a$max(), 1000)
})

test_that("merge() rejects self-merge, including aliases", {
  a <- tdigest_double(as.double(1:100))
  expect_error(a$merge(a), class = "datasketches_self_merge")
  alias <- a
  expect_error(a$merge(alias), class = "datasketches_self_merge")
})

test_that("merge() rejects a non-sketch argument", {
  a <- tdigest_double(as.double(1:100))
  expect_error(a$merge(42), class = "datasketches_invalid_sketch")

  fake <- structure(new.env(), class = "tdigest_double_sketch")
  expect_error(a$merge(fake), class = "datasketches_invalid_sketch")
})

test_that("format() and as.character() give the same concise representation", {
  s <- tdigest_double(as.double(1:100))
  expect_identical(format(s), as.character(s))
  expect_match(format(s), "^<tdigest_double_sketch\\[n=100, k=200\\]>$")
})

test_that("print() returns the sketch invisibly", {
  s <- tdigest_double(as.double(1:100))
  expect_output(out <- print(s), "tdigest_double_sketch")
  expect_identical(out, s)
})

test_that("inspect() writes the upstream debug string", {
  s <- tdigest_double(as.double(1:100))
  expect_output(s$inspect(), "t-Digest summary")
})

test_that("inspect(centroids = TRUE) includes the centroid/buffer list", {
  s <- tdigest_double(as.double(1:100))
  expect_output(s$inspect(centroids = TRUE), "Buffer:")
  expect_error(s$inspect(centroids = NA), class = "datasketches_invalid_flag")
})

test_that("serialize() round-trips through the bytes constructor", {
  s <- tdigest_double(as.double(1:1000))
  bytes <- s$serialize()
  expect_type(bytes, "raw")

  restored <- tdigest_double(bytes = bytes)
  expect_equal(restored$n(), s$n())
  expect_equal(
    restored$quantile(c(0.1, 0.5, 0.9)),
    s$quantile(c(0.1, 0.5, 0.9))
  )
})

test_that("constructor exclusivity is enforced", {
  bytes <- tdigest_double(as.double(1:100))$serialize()
  expect_error(
    tdigest_double(x = 1:10, bytes = bytes),
    class = "datasketches_invalid_args"
  )
  expect_error(
    tdigest_double(bytes = bytes, k = 200),
    class = "datasketches_invalid_args"
  )
  expect_error(
    tdigest_double(bytes = "not raw"),
    class = "datasketches_invalid_args"
  )
})
