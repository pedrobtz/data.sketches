# Tests for the KLL doubles public surface. KLL compaction is randomized, so
# assertions use exact streams (n < k stays exact) or error bounds rather than
# exact retained samples (see `_dev/WORKING-ON.md`, Randomness and Seeds).

test_that("kll_doubles() builds an empty sketch of the default width", {
  s <- kll_doubles()
  expect_s3_class(s, "kll_doubles_sketch")
  expect_true(s$is_empty())
  expect_equal(s$n(), 0)
  expect_equal(s$k(), 200L)
  expect_false(s$is_estimation_mode())
})

test_that("kll_doubles(k =) sets the width and validates the range", {
  expect_equal(kll_doubles(k = 64)$k(), 64L)

  expect_error(kll_doubles(k = 2), class = "datasketches_invalid_k")
  expect_error(kll_doubles(k = 70000), class = "datasketches_invalid_k")
  expect_error(kll_doubles(k = 100.5), class = "datasketches_invalid_k")
  expect_error(kll_doubles(k = c(200, 300)), class = "datasketches_invalid_k")
})

test_that("kll_doubles(x =) updates the sketch and reports exact stats below k", {
  s <- kll_doubles(as.double(1:100))
  expect_equal(s$n(), 100)
  expect_false(s$is_estimation_mode())
  expect_equal(s$min(), 1)
  expect_equal(s$max(), 100)
})

test_that("update() silently ignores NA and NaN", {
  s <- kll_doubles()
  s$update(c(1, 2, NA, NaN, 5))
  expect_equal(s$n(), 3)
  expect_invisible(s$update(10))
})

test_that("update() rejects non-numeric input", {
  s <- kll_doubles()
  expect_error(s$update("a"), class = "datasketches_invalid_input")
})

test_that("quantile() is vectorized, shape-preserving, and ordered", {
  s <- kll_doubles(as.double(1:1000))
  q <- s$quantile(c(0.25, 0.5, 0.75))
  expect_length(q, 3)
  expect_false(is.unsorted(q))
  expect_length(s$quantile(0.5), 1)
})

test_that("quantile() rejects probabilities outside [0, 1] and missing values", {
  s <- kll_doubles(as.double(1:100))
  expect_error(s$quantile(NA), class = "datasketches_invalid_prob")
  expect_error(s$quantile(1.5), class = "datasketches_invalid_prob")
  expect_error(s$quantile(-0.1), class = "datasketches_invalid_prob")
})

test_that("rank() is vectorized and propagates NA to the output position", {
  s <- kll_doubles(as.double(1:1000))
  r <- s$rank(c(250, NA, 750))
  expect_length(r, 3)
  expect_true(is.na(r[2]))
  expect_true(r[1] < r[3])
  # ranks are normalized to [0, 1]
  expect_true(all(r[c(1, 3)] >= 0 & r[c(1, 3)] <= 1))
})

test_that("cdf() and pmf() return length(split_points) + 1 values", {
  s <- kll_doubles(as.double(1:1000))
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
  s <- kll_doubles(as.double(1:100))
  expect_error(s$cdf(c(3, 1, 2)), class = "datasketches_invalid_split_points")
  expect_error(s$pmf(c(1, NA, 3)), class = "datasketches_invalid_split_points")
  expect_error(s$cdf(c(1, Inf)), class = "datasketches_invalid_split_points")
})

test_that("inclusive flag must be a single non-missing logical", {
  s <- kll_doubles(as.double(1:100))
  expect_error(
    s$quantile(0.5, inclusive = NA),
    class = "datasketches_invalid_flag"
  )
  expect_error(
    s$rank(1, inclusive = "yes"),
    class = "datasketches_invalid_flag"
  )
})

test_that("metadata accessors agree with summary()", {
  s <- kll_doubles(as.double(1:1000))
  info <- summary(s)
  expect_type(info, "list")
  expect_equal(info$type, "kll_doubles")
  expect_equal(info$n, s$n())
  expect_equal(info$k, s$k())
  expect_equal(info$num_retained, s$num_retained())
  expect_equal(info$min, s$min())
  expect_equal(info$max, s$max())
  expect_equal(info$rank_error, s$rank_error())
})

test_that("summary() is safe on an empty sketch", {
  info <- summary(kll_doubles())
  expect_true(info$is_empty)
  expect_identical(info$min, NA_real_)
  expect_identical(info$max, NA_real_)
})

test_that("rank_error() reflects k and the pmf flag", {
  loose <- kll_doubles(k = 50)$rank_error()
  tight <- kll_doubles(k = 400)$rank_error()
  expect_true(tight < loose)
  expect_error(
    kll_doubles()$rank_error(pmf = NA),
    class = "datasketches_invalid_flag"
  )
})

test_that("rank_error() reflects effective k after a mixed-width merge", {
  tight <- kll_doubles(as.double(1:10000), k = 400)
  loose <- kll_doubles(as.double(10001:20000), k = 50)
  tight_error <- tight$rank_error()
  loose_error <- loose$rank_error()

  tight$merge(loose)

  expect_gt(tight$rank_error(), tight_error)
  expect_equal(tight$rank_error(), loose_error)
  expect_equal(tight$k(), 400L)
})

test_that("merge() combines sketches and mutates the receiver", {
  a <- kll_doubles(as.double(1:500))
  b <- kll_doubles(as.double(501:1000))
  expect_invisible(a$merge(b))
  expect_equal(a$n(), 1000)
  expect_equal(a$max(), 1000)
})

test_that("merge() rejects self-merge, including aliases", {
  a <- kll_doubles(as.double(1:100))
  expect_error(a$merge(a), class = "datasketches_self_merge")
  alias <- a
  expect_error(a$merge(alias), class = "datasketches_self_merge")
})

test_that("merge() rejects a non-sketch argument", {
  a <- kll_doubles(as.double(1:100))
  expect_error(a$merge(42), class = "datasketches_invalid_sketch")

  fake <- structure(new.env(), class = "kll_doubles_sketch")
  expect_error(a$merge(fake), class = "datasketches_invalid_sketch")
})

test_that("format() and as.character() give the same concise representation", {
  s <- kll_doubles(as.double(1:100))
  expect_identical(format(s), as.character(s))
  expect_match(format(s), "^<kll_doubles_sketch\\[n=100, k=200\\]>$")
})

test_that("print() returns the sketch invisibly", {
  s <- kll_doubles(as.double(1:100))
  expect_output(out <- print(s), "kll_doubles_sketch")
  expect_identical(out, s)
})

test_that("inspect() writes the upstream debug string", {
  s <- kll_doubles(as.double(1:100))
  expect_output(s$inspect(), "KLL sketch summary")
})

test_that("serialize() round-trips through the bytes constructor", {
  s <- kll_doubles(as.double(1:1000))
  bytes <- s$serialize()
  expect_type(bytes, "raw")

  restored <- kll_doubles(bytes = bytes)
  expect_equal(restored$n(), s$n())
  expect_equal(
    restored$quantile(c(0.1, 0.5, 0.9)),
    s$quantile(c(0.1, 0.5, 0.9))
  )
})

test_that("constructor exclusivity is enforced", {
  bytes <- kll_doubles(as.double(1:100))$serialize()
  expect_error(
    kll_doubles(x = 1:10, bytes = bytes),
    class = "datasketches_invalid_args"
  )
  expect_error(
    kll_doubles(bytes = bytes, k = 200),
    class = "datasketches_invalid_args"
  )
  expect_error(
    kll_doubles(bytes = "not raw"),
    class = "datasketches_invalid_args"
  )
})
