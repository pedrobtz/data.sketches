# Tests for the Count-Min public surface. Mirrors the structure of
# test-frequent-items.R where the API overlaps, with family-specific coverage
# for numeric/character items, weights (including negative/fractional), and
# the seeded direct merge() with `num_hashes`/`num_buckets`/`seed`
# compatibility (see `_dev/WORKING-ON.md`).

test_that("count_min() builds an empty sketch with the default parameters", {
  s <- count_min()
  expect_s3_class(s, "count_min_sketch")
  expect_true(s$is_empty())
  expect_equal(s$total_weight(), 0)
  expect_equal(s$num_hashes(), 3L)
  expect_equal(s$num_buckets(), 55L)
  expect_equal(s$seed(), 9001)
})

test_that("count_min(num_hashes =, num_buckets =, seed =) validate inputs", {
  s <- count_min(num_hashes = 4, num_buckets = 10, seed = 123)
  expect_equal(s$num_hashes(), 4L)
  expect_equal(s$num_buckets(), 10L)
  expect_equal(s$seed(), 123)
  expect_equal(count_min(seed = 2^53)$seed(), 2^53)

  expect_error(
    count_min(num_hashes = 0),
    class = "datasketches_invalid_num_hashes"
  )
  expect_error(
    count_min(num_hashes = 256),
    class = "datasketches_invalid_num_hashes"
  )
  expect_error(
    count_min(num_hashes = c(2, 3)),
    class = "datasketches_invalid_num_hashes"
  )

  expect_error(
    count_min(num_buckets = 2),
    class = "datasketches_invalid_num_buckets"
  )
  expect_error(
    count_min(num_hashes = 30, num_buckets = 2^30),
    class = "datasketches_invalid_num_buckets"
  )

  expect_error(
    count_min(seed = -1),
    class = "datasketches_invalid_seed"
  )
  expect_error(
    count_min(seed = Inf),
    class = "datasketches_invalid_seed"
  )
  expect_error(
    count_min(seed = 2^53 + 2),
    class = "datasketches_invalid_seed"
  )
})

test_that("count_min(x =) updates the sketch with numeric input", {
  values <- c(rep(1, 100), rep(2, 10), 3)
  s <- count_min(values)
  expect_false(s$is_empty())
  expect_equal(s$total_weight(), length(values))
  expect_true(s$estimate(1) >= 100)
})

test_that("count_min(x =) updates the sketch with character input", {
  words <- c(rep("a", 100), rep("b", 10), "c")
  s <- count_min(words)
  expect_false(s$is_empty())
  expect_equal(s$total_weight(), length(words))
  expect_true(s$estimate("a") >= 100)
})

test_that("update() accepts a weight argument, recycled or per-element", {
  s <- count_min()
  s$update(c("a", "b"), weight = 5)
  expect_equal(s$total_weight(), 10)

  s2 <- count_min()
  s2$update(c("a", "b"), weight = c(3, 7))
  expect_equal(s2$total_weight(), 10)
  expect_true(s2$estimate("b") >= 7)
})

test_that("update() accepts negative and fractional weights", {
  s <- count_min()
  s$update("a", weight = 2.5)
  s$update("a", weight = -0.5)
  expect_equal(s$total_weight(), 3)
})

test_that("update() silently ignores NA and NaN", {
  s <- count_min()
  expect_invisible(s$update(c(1, NA, NaN, 2)))
  expect_equal(s$total_weight(), 2)

  s2 <- count_min()
  expect_invisible(s2$update(c("a", NA, "b")))
  expect_equal(s2$total_weight(), 2)
})

test_that("update() rejects non-numeric/non-character input", {
  s <- count_min()
  expect_error(s$update(TRUE), class = "datasketches_invalid_input")
  expect_error(s$update(list(1)), class = "datasketches_invalid_input")
})

test_that("update() rejects invalid weight", {
  s <- count_min()
  expect_error(
    s$update("a", weight = NA),
    class = "datasketches_invalid_weight"
  )
  expect_error(
    s$update("a", weight = Inf),
    class = "datasketches_invalid_weight"
  )
  expect_error(
    s$update(c("a", "b"), weight = c(1, 2, 3)),
    class = "datasketches_invalid_weight"
  )
})

test_that("weight cannot be set without x", {
  expect_error(count_min(weight = 5), class = "datasketches_invalid_args")
})

test_that("estimate()/lower_bound()/upper_bound() bracket the true frequency and vectorize", {
  words <- c(rep("a", 100), rep("b", 10))
  s <- count_min(words)

  est <- s$estimate(c("a", "b", "z"))
  lo <- s$lower_bound(c("a", "b", "z"))
  hi <- s$upper_bound(c("a", "b", "z"))

  expect_length(est, 3)
  expect_true(all(lo <= est))
  expect_true(all(hi >= est))
  expect_true(lo[[1]] <= 100 && hi[[1]] >= 100)
  expect_true(lo[[3]] <= 0)
})

test_that("estimate()/lower_bound()/upper_bound() work with numeric items", {
  values <- c(rep(1, 100), rep(2, 10))
  s <- count_min(values)

  est <- s$estimate(c(1, 2, 99))
  expect_length(est, 3)
  expect_true(est[[1]] >= 100)
  expect_true(est[[2]] >= 10)
})

test_that("estimate() rejects non-numeric/non-character input and missing values", {
  s <- count_min("a")
  expect_error(s$estimate(TRUE), class = "datasketches_invalid_input")
  expect_error(s$estimate(NA_character_), class = "datasketches_invalid_input")
  expect_error(s$estimate(NA_real_), class = "datasketches_invalid_input")
})

test_that("total_weight(), relative_error(), and is_empty() behave as documented", {
  s <- count_min(num_buckets = 100)
  expect_equal(s$total_weight(), 0)
  expect_equal(s$relative_error(), exp(1) / 100)
  expect_true(s$is_empty())

  s$update("a")
  expect_false(s$is_empty())
  expect_equal(s$total_weight(), 1)
})

test_that("summary() reports the documented fields", {
  s <- count_min(c(rep("a", 100), rep("b", 10)))
  info <- summary(s)
  expect_type(info, "list")
  expect_equal(info$type, "count_min")
  expect_equal(info$is_empty, s$is_empty())
  expect_equal(info$num_hashes, s$num_hashes())
  expect_equal(info$num_buckets, s$num_buckets())
  expect_equal(info$seed, s$seed())
  expect_equal(info$relative_error, s$relative_error())
  expect_equal(info$total_weight, s$total_weight())
})

test_that("merge() combines sketches and mutates the receiver", {
  a <- count_min(rep("a", 100))
  b <- count_min(rep("a", 50))
  expect_invisible(a$merge(b))
  expect_equal(a$total_weight(), 150)
})

test_that("merge() rejects self-merge, including aliases", {
  a <- count_min("a")
  expect_error(a$merge(a), class = "datasketches_self_merge")
  alias <- a
  expect_error(a$merge(alias), class = "datasketches_self_merge")
})

test_that("merge() rejects a non-sketch argument", {
  a <- count_min("a")
  expect_error(a$merge(42), class = "datasketches_invalid_sketch")

  fake <- structure(new.env(), class = "count_min_sketch")
  expect_error(a$merge(fake), class = "datasketches_invalid_sketch")
})

test_that("merge() rejects incompatible sketch configurations", {
  a <- count_min(rep("a", 100), num_hashes = 3, num_buckets = 50)

  b_hashes <- count_min(rep("a", 50), num_hashes = 4, num_buckets = 50)
  expect_error(a$merge(b_hashes), class = "datasketches_incompatible_sketch")

  b_buckets <- count_min(rep("a", 50), num_hashes = 3, num_buckets = 60)
  expect_error(a$merge(b_buckets), class = "datasketches_incompatible_sketch")

  b_seed <- count_min(rep("a", 50), num_hashes = 3, num_buckets = 50, seed = 42)
  expect_error(a$merge(b_seed), class = "datasketches_incompatible_sketch")
})

test_that("format() and as.character() give the same concise representation", {
  s <- count_min(c(rep("a", 100), rep("b", 10)))
  expect_identical(format(s), as.character(s))
  expect_match(
    format(s),
    "^<count_min_sketch\\[num_hashes=3, num_buckets=55, total_weight=110\\]>$"
  )

  empty <- count_min()
  expect_match(
    format(empty),
    "^<count_min_sketch\\[num_hashes=3, num_buckets=55, empty\\]>$"
  )
})

test_that("print() returns the sketch invisibly", {
  s <- count_min(c("a", "b"))
  expect_output(out <- print(s), "count_min_sketch")
  expect_identical(out, s)
})

test_that("inspect() writes the upstream debug string", {
  s <- count_min(c("a", "b"))
  expect_output(s$inspect())
})

test_that("serialize() round-trips through the bytes constructor", {
  s <- count_min(c(rep("a", 100), rep("b", 10)))
  bytes <- s$serialize()
  expect_type(bytes, "raw")

  restored <- count_min(bytes = bytes)
  expect_equal(restored$total_weight(), s$total_weight())
  expect_equal(restored$estimate("a"), s$estimate("a"))
  expect_equal(restored$num_hashes(), s$num_hashes())
  expect_equal(restored$num_buckets(), s$num_buckets())
})

test_that("constructor exclusivity is enforced", {
  bytes <- count_min(c("a", "b"))$serialize()
  expect_error(
    count_min(x = "c", bytes = bytes),
    class = "datasketches_invalid_args"
  )
  expect_error(
    count_min(bytes = bytes, num_hashes = 4),
    class = "datasketches_invalid_args"
  )
  expect_error(
    count_min(bytes = "not raw"),
    class = "datasketches_invalid_args"
  )
})

test_that("count_min_suggest_num_buckets() and count_min_suggest_num_hashes() work", {
  expect_equal(count_min_suggest_num_buckets(0.05), ceiling(exp(1) / 0.05))
  expect_equal(count_min_suggest_num_hashes(0.95), ceiling(log(20)))

  expect_error(
    count_min_suggest_num_buckets(-1),
    class = "datasketches_invalid_relative_error"
  )
  expect_error(
    count_min_suggest_num_hashes(1.5),
    class = "datasketches_invalid_confidence"
  )
  expect_error(
    count_min_suggest_num_hashes(0),
    class = "datasketches_invalid_confidence"
  )
})
