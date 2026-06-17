# Tests for the EBPPS sampling sketch public surface. Sample contents depend
# on internal randomness, so assertions check structure, invariants, and
# bounds rather than exact retained samples (see `_dev/WORKING-ON.md`,
# Randomness and Seeds).

test_that("ebpps() builds an empty sketch with defaults", {
  s <- ebpps()
  expect_s3_class(s, "ebpps_sketch")
  expect_true(s$is_empty())
  expect_equal(s$k(), 256L)
  expect_equal(s$n(), 0)
  expect_equal(s$cumulative_weight(), 0)
  expect_equal(s$c(), 0)
  expect_false(s$is_character())
})

test_that("ebpps(k =) sets the configuration and validates the range", {
  expect_equal(ebpps(k = 10)$k(), 10L)

  expect_error(ebpps(k = 0), class = "datasketches_invalid_k")
  expect_error(ebpps(k = 2147483647), class = "datasketches_invalid_k")
  expect_error(ebpps(k = 1.5), class = "datasketches_invalid_k")
  expect_error(ebpps(k = NA), class = "datasketches_invalid_k")
  expect_error(ebpps(k = c(10, 20)), class = "datasketches_invalid_k")
})

test_that("ebpps(type =) sets the item type and validates the choice", {
  expect_false(ebpps(type = "double")$is_character())
  expect_true(ebpps(type = "character")$is_character())

  expect_error(ebpps(type = "int"), class = "datasketches_invalid_type")
  expect_error(ebpps(type = NA), class = "datasketches_invalid_type")
})

test_that("ebpps(x =) infers the item type and updates the sketch", {
  s <- ebpps(as.double(1:1000), k = 50)
  expect_false(s$is_character())
  expect_equal(s$n(), 1000)
  expect_equal(s$cumulative_weight(), 1000)
  expect_equal(length(s$result()), 50L)

  s <- ebpps(letters)
  expect_true(s$is_character())
  expect_equal(s$n(), 26)
})

test_that("update() rejects input of the wrong item type", {
  s <- ebpps(k = 10)
  expect_error(s$update("a"), class = "datasketches_invalid_input")

  s <- ebpps(type = "character", k = 10)
  expect_error(s$update(1), class = "datasketches_invalid_input")
})

test_that("update(weight =) validates non-negative finite weights", {
  s <- ebpps(k = 10)
  expect_error(s$update(1, weight = -1), class = "datasketches_invalid_weight")
  expect_error(s$update(1, weight = NA), class = "datasketches_invalid_weight")
  expect_error(s$update(1, weight = Inf), class = "datasketches_invalid_weight")
  expect_error(s$update(1, weight = NaN), class = "datasketches_invalid_weight")
  expect_error(
    s$update(1:3, weight = c(1, 2)),
    class = "datasketches_invalid_weight"
  )

  # zero is allowed, but does not contribute to cumulative weight or n
  expect_invisible(s$update(1, weight = 0))
  expect_equal(s$n(), 0)
  expect_equal(s$cumulative_weight(), 0)
})

test_that("ebpps() rejects weight without x", {
  expect_error(ebpps(weight = 1), class = "datasketches_invalid_args")
})

test_that("update() silently ignores NA, NaN, and NA_character_", {
  s <- ebpps(k = 10)
  s$update(c(1, NA, NaN, 4))
  expect_equal(s$n(), 2)

  s <- ebpps(type = "character", k = 10)
  s$update(c("a", NA, "b"))
  expect_equal(s$n(), 2)
})

test_that("result() returns a numeric or character vector of up to k items", {
  s <- ebpps(as.double(1:1000), k = 50)
  result <- s$result()
  expect_type(result, "double")
  expect_equal(length(result), 50L)

  s <- ebpps(letters, k = 10)
  result <- s$result()
  expect_type(result, "character")
  expect_equal(length(result), 10L)
})

test_that("result() on an empty sketch returns an empty vector", {
  s <- ebpps(k = 10)
  expect_equal(length(s$result()), 0L)

  s <- ebpps(type = "character", k = 10)
  expect_type(s$result(), "character")
  expect_equal(length(s$result()), 0L)
})

test_that("c() is bounded by k() and reflects the weighted sample size", {
  s <- ebpps(as.double(1:1000), k = 50)
  expect_lte(s$c(), s$k() + 1e-9)
  expect_gte(s$c(), 0)

  # when n < k, c() equals n (no downsampling has occurred)
  s <- ebpps(as.double(1:10), k = 50)
  expect_equal(s$c(), 10)
})

test_that("metadata accessors agree with summary()", {
  s <- ebpps(as.double(1:1000), k = 50)
  info <- s$summary()

  expect_equal(info$type, "ebpps")
  expect_equal(info$item_type, "double")
  expect_equal(info$k, s$k())
  expect_equal(info$n, s$n())
  expect_equal(info$cumulative_weight, s$cumulative_weight())
  expect_equal(info$c, s$c())
  expect_equal(info$is_empty, s$is_empty())
})

test_that("merge() combines sketches and mutates the receiver", {
  a <- ebpps(as.double(1:500), k = 50)
  b <- ebpps(as.double(501:1000), k = 50)
  expect_invisible(a$merge(b))
  expect_equal(a$n(), 1000)
  expect_equal(a$cumulative_weight(), 1000)
})

test_that("merge() resizes the receiver to the smaller configured k", {
  a <- ebpps(as.double(1:500), k = 30)
  b <- ebpps(as.double(501:1000), k = 50)
  a$merge(b)
  expect_equal(a$k(), 30L)
})

test_that("merge() rejects self-merge, including aliases", {
  a <- ebpps(as.double(1:100), k = 10)
  expect_error(a$merge(a), class = "datasketches_self_merge")
  alias <- a
  expect_error(a$merge(alias), class = "datasketches_self_merge")
})

test_that("merge() rejects a non-sketch argument", {
  a <- ebpps(as.double(1:100), k = 10)
  expect_error(a$merge(42), class = "datasketches_invalid_sketch")

  fake <- structure(new.env(), class = "ebpps_sketch")
  expect_error(a$merge(fake), class = "datasketches_invalid_sketch")
})

test_that("merge() rejects sketches with different item types", {
  a <- ebpps(as.double(1:100), k = 10)
  b <- ebpps(letters, k = 10)
  expect_error(a$merge(b), class = "datasketches_incompatible_sketch")
})

test_that("format() and as.character() give the same concise representation", {
  s <- ebpps(as.double(1:1000), k = 50)
  expect_identical(format(s), as.character(s))
  expect_match(
    format(s),
    "^<ebpps_sketch\\[k=50, double, n=1000, c=50\\]>$"
  )

  empty <- ebpps(k = 10)
  expect_match(format(empty), "^<ebpps_sketch\\[k=10, double, empty\\]>$")
})

test_that("print() returns the sketch invisibly", {
  s <- ebpps(as.double(1:100), k = 10)
  expect_output(out <- print(s), "ebpps_sketch")
  expect_identical(out, s)
})

test_that("summary() returns the structured metadata list", {
  s <- ebpps(as.double(1:100), k = 10)
  expect_identical(summary(s), s$summary())
})

test_that("inspect() writes the upstream debug string", {
  s <- ebpps(as.double(1:100), k = 10)
  expect_output(s$inspect(), "EBPPS Sketch SUMMARY")
})

test_that("serialize() round-trips through the bytes constructor", {
  s <- ebpps(as.double(1:1000), k = 50)
  bytes <- s$serialize()
  expect_type(bytes, "raw")

  restored <- ebpps(bytes = bytes)
  expect_equal(restored$k(), s$k())
  expect_equal(restored$n(), s$n())
  expect_equal(restored$cumulative_weight(), s$cumulative_weight())
  expect_equal(restored$c(), s$c())
  expect_equal(restored$result(), s$result())
})

test_that("serialize() round-trips a character sketch", {
  s <- ebpps(letters, k = 10)
  bytes <- s$serialize()

  restored <- ebpps(bytes = bytes)
  expect_true(restored$is_character())
  expect_equal(restored$result(), s$result())
})

test_that("constructor exclusivity is enforced", {
  bytes <- ebpps(as.double(1:100), k = 10)$serialize()
  expect_error(
    ebpps(x = 1:10, bytes = bytes),
    class = "datasketches_invalid_args"
  )
  expect_error(
    ebpps(bytes = bytes, k = 10),
    class = "datasketches_invalid_args"
  )
  expect_error(
    ebpps(bytes = bytes, type = "double"),
    class = "datasketches_invalid_args"
  )
  expect_error(
    ebpps(bytes = bytes, weight = 1),
    class = "datasketches_invalid_args"
  )
  expect_error(
    ebpps(bytes = "not raw"),
    class = "datasketches_invalid_args"
  )
})
