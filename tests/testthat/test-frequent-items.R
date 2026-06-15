# Tests for the Frequent Items public surface. Mirrors the structure of
# test-cardinality-cpc.R where the API overlaps, with family-specific
# coverage for weights, the frequent_items() table, and the unseeded direct
# merge() (see `_dev/WORKING-ON.md`).

test_that("frequent_items() builds an empty sketch with the default map sizes", {
  s <- frequent_items()
  expect_s3_class(s, "frequent_items_sketch")
  expect_true(s$is_empty())
  expect_equal(s$num_active_items(), 0)
  expect_equal(s$total_weight(), 0)
})

test_that("frequent_items(lg_max_map_size =, lg_start_map_size =) validate ranges", {
  expect_true(is.numeric(frequent_items(lg_max_map_size = 6)$maximum_error()))

  expect_error(
    frequent_items(lg_max_map_size = 2),
    class = "datasketches_invalid_lg_k"
  )
  expect_error(
    frequent_items(lg_max_map_size = 31),
    class = "datasketches_invalid_lg_k"
  )
  expect_error(
    frequent_items(lg_max_map_size = c(6, 8)),
    class = "datasketches_invalid_lg_k"
  )

  expect_error(
    frequent_items(lg_start_map_size = 2),
    class = "datasketches_invalid_lg_k"
  )
  expect_error(
    frequent_items(lg_max_map_size = 6, lg_start_map_size = 8),
    class = "datasketches_invalid_lg_k"
  )
})

test_that("frequent_items(x =) updates the sketch with character input", {
  words <- c(rep("a", 100), rep("b", 10), rep("c", 1))
  s <- frequent_items(words)
  expect_false(s$is_empty())
  expect_equal(s$total_weight(), length(words))
  expect_true(s$estimate("a") >= 100)
})

test_that("update() accepts a weight argument, recycled or per-element", {
  s <- frequent_items()
  s$update(c("a", "b"), weight = 5)
  expect_equal(s$total_weight(), 10)

  s2 <- frequent_items()
  s2$update(c("a", "b"), weight = c(3, 7))
  expect_equal(s2$total_weight(), 10)
  expect_true(s2$estimate("b") >= 7)
})

test_that("update() silently ignores NA_character_", {
  s <- frequent_items()
  expect_invisible(s$update(c("a", NA, "b")))
  expect_equal(s$total_weight(), 2)
})

test_that("update() rejects non-character input", {
  s <- frequent_items()
  expect_error(s$update(1:10), class = "datasketches_invalid_input")
  expect_error(s$update(TRUE), class = "datasketches_invalid_input")
})

test_that("update() rejects invalid weight", {
  s <- frequent_items()
  expect_error(
    s$update("a", weight = -1),
    class = "datasketches_invalid_weight"
  )
  expect_error(
    s$update("a", weight = 1.5),
    class = "datasketches_invalid_weight"
  )
  expect_error(
    s$update("a", weight = NA),
    class = "datasketches_invalid_weight"
  )
  expect_error(
    s$update(c("a", "b"), weight = c(1, 2, 3)),
    class = "datasketches_invalid_weight"
  )
  expect_error(
    s$update("a", weight = Inf),
    class = "datasketches_invalid_weight"
  )
  expect_error(
    s$update("a", weight = 2^53 + 2),
    class = "datasketches_invalid_weight"
  )
})

test_that("weight cannot be set without x", {
  expect_error(frequent_items(weight = 5), class = "datasketches_invalid_args")
})

test_that("estimate()/lower_bound()/upper_bound() bracket the true frequency and vectorize", {
  words <- c(rep("a", 100), rep("b", 10))
  s <- frequent_items(words)

  est <- s$estimate(c("a", "b", "z"))
  lo <- s$lower_bound(c("a", "b", "z"))
  hi <- s$upper_bound(c("a", "b", "z"))

  expect_length(est, 3)
  expect_true(all(lo <= est))
  expect_true(all(hi >= est))
  expect_true(lo[[1]] <= 100 && hi[[1]] >= 100)
  expect_true(lo[[3]] <= 0)
})

test_that("estimate() rejects non-character input", {
  s <- frequent_items("a")
  expect_error(s$estimate(1), class = "datasketches_invalid_input")
})

test_that("frequent_items() returns a data frame of the heaviest items", {
  words <- c(rep("a", 1000), rep("b", 500), rep("c", 1))
  s <- frequent_items(words)

  tbl <- s$frequent_items()
  expect_s3_class(tbl, "data.frame")
  expect_named(tbl, c("item", "estimate", "lower_bound", "upper_bound"))
  expect_true("a" %in% tbl$item)
  expect_true("b" %in% tbl$item)
})

test_that("frequent_items() validates error_type and threshold", {
  s <- frequent_items(c(rep("a", 100), rep("b", 10)))

  tbl_fn <- s$frequent_items(error_type = "no_false_negatives")
  expect_s3_class(tbl_fn, "data.frame")

  tbl_thr <- s$frequent_items(threshold = 50)
  expect_true(all(tbl_thr$estimate > 0))

  expect_error(
    s$frequent_items(error_type = "bogus"),
    class = "datasketches_invalid_error_type"
  )
  expect_error(
    s$frequent_items(threshold = -1),
    class = "datasketches_invalid_weight"
  )
  expect_error(
    s$frequent_items(threshold = Inf),
    class = "datasketches_invalid_weight"
  )
  expect_error(
    s$frequent_items(threshold = 2^53 + 2),
    class = "datasketches_invalid_weight"
  )
})

test_that("maximum_error() and epsilon() are non-negative numbers", {
  s <- frequent_items(c(rep("a", 100), rep("b", 10)))
  expect_true(is.numeric(s$maximum_error()) && s$maximum_error() >= 0)
  expect_true(is.numeric(s$epsilon()) && s$epsilon() >= 0)
})

test_that("summary() reports the documented fields", {
  s <- frequent_items(c(rep("a", 100), rep("b", 10)))
  info <- summary(s)
  expect_type(info, "list")
  expect_equal(info$type, "frequent_items")
  expect_equal(info$is_empty, s$is_empty())
  expect_equal(info$num_active_items, s$num_active_items())
  expect_equal(info$total_weight, s$total_weight())
  expect_equal(info$maximum_error, s$maximum_error())
  expect_equal(info$epsilon, s$epsilon())
})

test_that("merge() combines sketches and mutates the receiver", {
  a <- frequent_items(rep("a", 100))
  b <- frequent_items(rep("a", 50))
  expect_invisible(a$merge(b))
  expect_equal(a$total_weight(), 150)
})

test_that("merge() rejects self-merge, including aliases", {
  a <- frequent_items("a")
  expect_error(a$merge(a), class = "datasketches_self_merge")
  alias <- a
  expect_error(a$merge(alias), class = "datasketches_self_merge")
})

test_that("merge() rejects a non-sketch argument", {
  a <- frequent_items("a")
  expect_error(a$merge(42), class = "datasketches_invalid_sketch")

  fake <- structure(new.env(), class = "frequent_items_sketch")
  expect_error(a$merge(fake), class = "datasketches_invalid_sketch")
})

test_that("merge() combines sketches with different map sizes", {
  a <- frequent_items(rep("a", 100), lg_max_map_size = 6)
  b <- frequent_items(rep("a", 50), lg_max_map_size = 10)
  expect_invisible(a$merge(b))
  expect_equal(a$total_weight(), 150)
})

test_that("format() and as.character() give the same concise representation", {
  s <- frequent_items(c(rep("a", 100), rep("b", 10)))
  expect_identical(format(s), as.character(s))
  expect_match(
    format(s),
    "^<frequent_items_sketch\\[num_active_items=2, total_weight=110\\]>$"
  )

  empty <- frequent_items()
  expect_match(format(empty), "^<frequent_items_sketch\\[empty\\]>$")
})

test_that("print() returns the sketch invisibly", {
  s <- frequent_items(c("a", "b"))
  expect_output(out <- print(s), "frequent_items_sketch")
  expect_identical(out, s)
})

test_that("inspect() writes the upstream debug string", {
  s <- frequent_items(c("a", "b"))
  expect_output(s$inspect())
})

test_that("serialize() round-trips through the bytes constructor", {
  s <- frequent_items(c(rep("a", 100), rep("b", 10)))
  bytes <- s$serialize()
  expect_type(bytes, "raw")

  restored <- frequent_items(bytes = bytes)
  expect_equal(restored$total_weight(), s$total_weight())
  expect_equal(restored$estimate("a"), s$estimate("a"))
})

test_that("constructor exclusivity is enforced", {
  bytes <- frequent_items(c("a", "b"))$serialize()
  expect_error(
    frequent_items(x = "c", bytes = bytes),
    class = "datasketches_invalid_args"
  )
  expect_error(
    frequent_items(bytes = bytes, lg_max_map_size = 10),
    class = "datasketches_invalid_args"
  )
  expect_error(
    frequent_items(bytes = "not raw"),
    class = "datasketches_invalid_args"
  )
})
