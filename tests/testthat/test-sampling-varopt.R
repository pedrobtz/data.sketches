# Tests for the VarOpt sampling sketch public surface, including
# varopt_union(). Sample contents and subset-sum estimates depend on internal
# randomness, so assertions check structure, invariants, and error bounds
# rather than exact retained samples (see `_dev/WORKING-ON.md`, Randomness
# and Seeds).

test_that("varopt() builds an empty sketch with defaults", {
  s <- varopt()
  expect_s3_class(s, "varopt_sketch")
  expect_true(s$is_empty())
  expect_equal(s$k(), 256L)
  expect_equal(s$n(), 0)
  expect_equal(s$num_samples(), 0L)
  expect_false(s$is_character())
})

test_that("varopt(k =) sets the configuration and validates the range", {
  expect_equal(varopt(k = 10)$k(), 10L)

  expect_error(varopt(k = 0), class = "datasketches_invalid_k")
  expect_error(varopt(k = 2147483647), class = "datasketches_invalid_k")
  expect_error(varopt(k = 1.5), class = "datasketches_invalid_k")
  expect_error(varopt(k = NA), class = "datasketches_invalid_k")
  expect_error(varopt(k = c(10, 20)), class = "datasketches_invalid_k")
})

test_that("varopt(type =) sets the item type and validates the choice", {
  expect_false(varopt(type = "double")$is_character())
  expect_true(varopt(type = "character")$is_character())

  expect_error(varopt(type = "int"), class = "datasketches_invalid_type")
  expect_error(varopt(type = NA), class = "datasketches_invalid_type")
})

test_that("varopt(x =) infers the item type and updates the sketch", {
  s <- varopt(as.double(1:1000))
  expect_false(s$is_character())
  expect_equal(s$n(), 1000)
  expect_equal(s$num_samples(), 256L)

  s <- varopt(letters)
  expect_true(s$is_character())
  expect_equal(s$n(), 26)
})

test_that("update() rejects input of the wrong item type", {
  s <- varopt(k = 10)
  expect_error(s$update("a"), class = "datasketches_invalid_input")

  s <- varopt(type = "character", k = 10)
  expect_error(s$update(1), class = "datasketches_invalid_input")
})

test_that("update(weight =) validates non-negative finite weights", {
  s <- varopt(k = 10)
  expect_error(s$update(1, weight = -1), class = "datasketches_invalid_weight")
  expect_error(s$update(1, weight = NA), class = "datasketches_invalid_weight")
  expect_error(s$update(1, weight = Inf), class = "datasketches_invalid_weight")
  expect_error(s$update(1, weight = NaN), class = "datasketches_invalid_weight")
  expect_error(
    s$update(1:3, weight = c(1, 2)),
    class = "datasketches_invalid_weight"
  )

  # zero is allowed
  expect_invisible(s$update(1, weight = 0))
})

test_that("varopt() rejects weight without x", {
  expect_error(varopt(weight = 1), class = "datasketches_invalid_args")
})

test_that("update() silently ignores NA, NaN, and NA_character_", {
  s <- varopt(k = 10)
  s$update(c(1, NA, NaN, 4))
  expect_equal(s$n(), 2)

  s <- varopt(type = "character", k = 10)
  s$update(c("a", NA, "b"))
  expect_equal(s$n(), 2)
})

test_that("update() drops the weight for NA elements of x", {
  s <- varopt(k = 10)
  s$update(c(1, NA, 3), weight = c(10, 20, 30))
  expect_equal(s$n(), 2)
  expect_equal(sum(s$samples()$weight), 40)
})

test_that("samples() returns one row per retained item with item and weight columns", {
  s <- varopt(as.double(1:1000), k = 50)
  samples <- s$samples()
  expect_s3_class(samples, "data.frame")
  expect_named(samples, c("item", "weight"))
  expect_equal(nrow(samples), 50L)
  expect_type(samples$item, "double")
  expect_type(samples$weight, "double")
})

test_that("samples() returns character items for a character sketch", {
  s <- varopt(letters, k = 10)
  samples <- s$samples()
  expect_type(samples$item, "character")
  expect_equal(nrow(samples), 10L)
})

test_that("estimate_subset_sum() brackets the true subset sum and reports total_weight", {
  items <- as.double(1:1000)
  weights <- rep(1, 1000)
  s <- varopt(items, weights, k = 200)

  res <- s$estimate_subset_sum(\(x) x <= 500)
  expect_named(res, c("lower_bound", "estimate", "upper_bound", "total_weight"))
  expect_true(res$lower_bound <= res$estimate)
  expect_true(res$estimate <= res$upper_bound)
  expect_equal(res$total_weight, 1000)
})

test_that("estimate_subset_sum() on an empty sketch returns zeros", {
  s <- varopt(k = 10)
  res <- s$estimate_subset_sum(\(x) TRUE)
  expect_equal(res$lower_bound, 0)
  expect_equal(res$estimate, 0)
  expect_equal(res$upper_bound, 0)
  expect_equal(res$total_weight, 0)
})

test_that("estimate_subset_sum() is exact when the sample holds the full stream", {
  items <- as.double(1:50)
  s <- varopt(items, k = 100)

  # When the sketch holds the entire stream (no sampling), the native
  # implementation reports `total_weight` as the matched-subset weight too.
  res <- s$estimate_subset_sum(\(x) x <= 25)
  expect_equal(res$lower_bound, 25)
  expect_equal(res$estimate, 25)
  expect_equal(res$upper_bound, 25)
  expect_equal(res$total_weight, 25)
})

test_that("metadata accessors agree with summary()", {
  s <- varopt(as.double(1:1000), k = 50)
  info <- s$summary()

  expect_equal(info$type, "varopt")
  expect_equal(info$item_type, "double")
  expect_equal(info$k, s$k())
  expect_equal(info$n, s$n())
  expect_equal(info$num_samples, s$num_samples())
  expect_equal(info$is_empty, s$is_empty())
})

test_that("merge() combines sketches and mutates the receiver", {
  a <- varopt(as.double(1:500), k = 50)
  b <- varopt(as.double(501:1000), k = 50)
  expect_invisible(a$merge(b))
  expect_equal(a$n(), 1000)
})

test_that("merge() rejects self-merge, including aliases", {
  a <- varopt(as.double(1:100), k = 10)
  expect_error(a$merge(a), class = "datasketches_self_merge")
  alias <- a
  expect_error(a$merge(alias), class = "datasketches_self_merge")
})

test_that("merge() rejects a non-sketch argument", {
  a <- varopt(as.double(1:100), k = 10)
  expect_error(a$merge(42), class = "datasketches_invalid_sketch")

  fake <- structure(new.env(), class = "varopt_sketch")
  expect_error(a$merge(fake), class = "datasketches_invalid_sketch")
})

test_that("merge() rejects sketches with different item types", {
  a <- varopt(as.double(1:100), k = 10)
  b <- varopt(letters, k = 10)
  expect_error(a$merge(b), class = "datasketches_incompatible_sketch")
})

test_that("format() and as.character() give the same concise representation", {
  s <- varopt(as.double(1:1000), k = 50)
  expect_identical(format(s), as.character(s))
  expect_match(
    format(s),
    "^<varopt_sketch\\[k=50, double, n=1000, num_samples=50\\]>$"
  )

  empty <- varopt(k = 10)
  expect_match(format(empty), "^<varopt_sketch\\[k=10, double, empty\\]>$")
})

test_that("print() returns the sketch invisibly", {
  s <- varopt(as.double(1:100), k = 10)
  expect_output(out <- print(s), "varopt_sketch")
  expect_identical(out, s)
})

test_that("summary() returns the structured metadata list", {
  s <- varopt(as.double(1:100), k = 10)
  expect_identical(summary(s), s$summary())
})

test_that("inspect() writes the upstream debug string", {
  s <- varopt(as.double(1:100), k = 10)
  expect_output(s$inspect(), "VarOpt SUMMARY")
})

test_that("serialize() round-trips through the bytes constructor", {
  s <- varopt(as.double(1:1000), k = 50)
  bytes <- s$serialize()
  expect_type(bytes, "raw")

  restored <- varopt(bytes = bytes)
  expect_equal(restored$k(), s$k())
  expect_equal(restored$n(), s$n())
  expect_equal(restored$samples(), s$samples())
})

test_that("serialize() round-trips a character sketch", {
  s <- varopt(letters, k = 10)
  bytes <- s$serialize()

  restored <- varopt(bytes = bytes)
  expect_true(restored$is_character())
  expect_equal(restored$samples(), s$samples())
})

test_that("constructor exclusivity is enforced", {
  bytes <- varopt(as.double(1:100), k = 10)$serialize()
  expect_error(
    varopt(x = 1:10, bytes = bytes),
    class = "datasketches_invalid_args"
  )
  expect_error(
    varopt(bytes = bytes, k = 10),
    class = "datasketches_invalid_args"
  )
  expect_error(
    varopt(bytes = bytes, type = "double"),
    class = "datasketches_invalid_args"
  )
  expect_error(
    varopt(bytes = bytes, weight = 1),
    class = "datasketches_invalid_args"
  )
  expect_error(
    varopt(bytes = "not raw"),
    class = "datasketches_invalid_args"
  )
})

test_that("varopt_union() combines two sketches without mutating inputs", {
  a <- varopt(as.double(1:500), k = 50)
  b <- varopt(as.double(501:1000), k = 50)

  u <- varopt_union(a, b)
  expect_s3_class(u, "varopt_sketch")
  expect_equal(u$n(), 1000)
  expect_equal(a$n(), 500)
  expect_equal(b$n(), 500)
})

test_that("varopt_union() uses the larger of the two configured k values", {
  a <- varopt(as.double(1:500), k = 30)
  b <- varopt(as.double(501:1000), k = 50)

  u <- varopt_union(a, b)
  expect_equal(u$k(), 50L)
})

test_that("varopt_union() rejects sketches with different item types", {
  a <- varopt(as.double(1:100), k = 10)
  b <- varopt(letters, k = 10)
  expect_error(varopt_union(a, b), class = "datasketches_incompatible_sketch")
})

test_that("varopt_union() rejects non-sketch arguments", {
  a <- varopt(as.double(1:100), k = 10)
  expect_error(varopt_union(a, 42), class = "datasketches_invalid_sketch")
  expect_error(varopt_union(42, a), class = "datasketches_invalid_sketch")
})
