# Tests for the HLL public surface. HLL estimates are approximate and depend
# on internal hashing, so assertions use error-bound brackets
# (`lower_bound()`/`upper_bound()`) rather than exact counts (see
# `_dev/WORKING-ON.md`, Randomness and Seeds).

test_that("hll() builds an empty sketch with the default lg_k and type", {
  s <- hll()
  expect_s3_class(s, "hll_sketch")
  expect_true(s$is_empty())
  expect_equal(s$lg_k(), 12L)
  expect_equal(s$hll_type(), "HLL_4")
  expect_equal(s$estimate(), 0)
})

test_that("hll(lg_k =) sets the configuration and validates the range", {
  expect_equal(hll(lg_k = 10)$lg_k(), 10L)

  expect_error(hll(lg_k = 3), class = "datasketches_invalid_lg_k")
  expect_error(hll(lg_k = 22), class = "datasketches_invalid_lg_k")
  expect_error(hll(lg_k = c(10, 12)), class = "datasketches_invalid_lg_k")
})

test_that("hll(type =) sets the target encoding and validates the choice", {
  expect_equal(hll(type = "HLL_4")$hll_type(), "HLL_4")
  expect_equal(hll(type = "HLL_6")$hll_type(), "HLL_6")
  expect_equal(hll(type = "HLL_8")$hll_type(), "HLL_8")

  expect_error(hll(type = "HLL_2"), class = "datasketches_invalid_type")
  expect_error(
    hll(type = c("HLL_4", "HLL_8")),
    class = "datasketches_invalid_type"
  )
})

test_that("hll(x =) updates the sketch with numeric input", {
  s <- hll(as.double(1:1000))
  expect_false(s$is_empty())
  expect_true(s$estimate() >= s$lower_bound())
  expect_true(s$estimate() <= s$upper_bound())
  # 3 std dev (~99.7%) bound around the estimate brackets the true count.
  expect_true(s$lower_bound(3) <= 1000 && s$upper_bound(3) >= 1000)
})

test_that("update() accepts character input", {
  s <- hll()
  s$update(letters)
  expect_false(s$is_empty())
  expect_true(s$estimate() > 0)
})

test_that("update() silently ignores NA, NaN, and NA_character_", {
  s <- hll()
  s$update(c(1, 2, NA, NaN, 3))
  expect_true(s$estimate() > 0)
  expect_invisible(s$update(4))

  s2 <- hll()
  expect_invisible(s2$update(c("a", NA, "b")))
  expect_true(s2$estimate() > 0)
})

test_that("update() rejects input that is neither numeric nor character", {
  s <- hll()
  expect_error(s$update(TRUE), class = "datasketches_invalid_input")
  expect_error(s$update(list(1, 2)), class = "datasketches_invalid_input")
})

test_that("lower_bound()/upper_bound() bracket estimate() and validate num_std_dev", {
  s <- hll(as.double(1:10000))
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

test_that("metadata accessors agree with summary()", {
  s <- hll(as.double(1:1000))
  info <- summary(s)
  expect_type(info, "list")
  expect_equal(info$type, "hll")
  expect_equal(info$lg_k, s$lg_k())
  expect_equal(info$hll_type, s$hll_type())
  expect_equal(info$is_empty, s$is_empty())
  expect_equal(info$is_compact, s$is_compact())
  expect_equal(info$estimate, s$estimate())
  expect_equal(info$lower_bound, s$lower_bound())
  expect_equal(info$upper_bound, s$upper_bound())
})

test_that("merge() combines sketches and mutates the receiver", {
  a <- hll(as.double(1:500))
  b <- hll(as.double(501:1000))
  expect_invisible(a$merge(b))
  expect_true(a$lower_bound(3) <= 1000 && a$upper_bound(3) >= 1000)
})

test_that("merge() rejects self-merge, including aliases", {
  a <- hll(as.double(1:100))
  expect_error(a$merge(a), class = "datasketches_self_merge")
  alias <- a
  expect_error(a$merge(alias), class = "datasketches_self_merge")
})

test_that("merge() rejects a non-sketch argument", {
  a <- hll(as.double(1:100))
  expect_error(a$merge(42), class = "datasketches_invalid_sketch")

  fake <- structure(new.env(), class = "hll_sketch")
  expect_error(a$merge(fake), class = "datasketches_invalid_sketch")
})

test_that("merge() combines sketches with different lg_k", {
  a <- hll(as.double(1:500), lg_k = 10)
  b <- hll(as.double(501:1000), lg_k = 14)
  expect_invisible(a$merge(b))
  expect_true(a$lower_bound(3) <= 1000 && a$upper_bound(3) >= 1000)
})

test_that("format() and as.character() give the same concise representation", {
  s <- hll(as.double(1:1000))
  expect_identical(format(s), as.character(s))
  expect_match(
    format(s),
    "^<hll_sketch\\[lg_k=12, type=HLL_4, estimate=.+\\]>$"
  )

  empty <- hll()
  expect_match(format(empty), "^<hll_sketch\\[lg_k=12, type=HLL_4, empty\\]>$")
})

test_that("print() returns the sketch invisibly", {
  s <- hll(as.double(1:100))
  expect_output(out <- print(s), "hll_sketch")
  expect_identical(out, s)
})

test_that("inspect() writes the upstream debug string", {
  s <- hll(as.double(1:100))
  expect_output(s$inspect(), "HLL sketch summary")
})

test_that("serialize() round-trips through the bytes constructor", {
  s <- hll(as.double(1:1000))
  bytes <- s$serialize()
  expect_type(bytes, "raw")

  restored <- hll(bytes = bytes)
  expect_equal(restored$lg_k(), s$lg_k())
  expect_equal(restored$hll_type(), s$hll_type())
  expect_equal(restored$estimate(), s$estimate())
})

test_that("constructor exclusivity is enforced", {
  bytes <- hll(as.double(1:100))$serialize()
  expect_error(
    hll(x = 1:10, bytes = bytes),
    class = "datasketches_invalid_args"
  )
  expect_error(
    hll(bytes = bytes, lg_k = 12),
    class = "datasketches_invalid_args"
  )
  expect_error(
    hll(bytes = bytes, type = "HLL_4"),
    class = "datasketches_invalid_args"
  )
  expect_error(
    hll(bytes = "not raw"),
    class = "datasketches_invalid_args"
  )
  expect_error(
    hll(bytes = raw(0)),
    class = "datasketches_invalid_args"
  )
  expect_error(
    hll(bytes = raw(7)),
    class = "datasketches_invalid_args"
  )
  malformed <- bytes
  malformed[[1]] <- as.raw(0xff)
  expect_error(hll(bytes = malformed))
})
