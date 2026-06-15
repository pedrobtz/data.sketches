# Tests for the CPC public surface. Mirrors test-cardinality-hll.R where the
# API overlaps; CPC-specific behavior (seed) gets its own tests. CPC estimates
# are approximate and depend on internal hashing, so assertions use
# error-bound brackets (`lower_bound()`/`upper_bound()`) rather than exact
# counts (see `_dev/WORKING-ON.md`, Randomness and Seeds).

test_that("cpc() builds an empty sketch with the default lg_k and seed", {
  s <- cpc()
  expect_s3_class(s, "cpc_sketch")
  expect_true(s$is_empty())
  expect_equal(s$lg_k(), 11L)
  expect_equal(s$seed(), 9001)
  expect_equal(s$estimate(), 0)
})

test_that("cpc(lg_k =) sets the configuration and validates the range", {
  expect_equal(cpc(lg_k = 10)$lg_k(), 10L)

  expect_error(cpc(lg_k = 3), class = "datasketches_invalid_lg_k")
  expect_error(cpc(lg_k = 27), class = "datasketches_invalid_lg_k")
  expect_error(cpc(lg_k = c(10, 12)), class = "datasketches_invalid_lg_k")
})

test_that("cpc(seed =) sets the hash seed and validates it", {
  expect_equal(cpc(seed = 123)$seed(), 123)
  expect_equal(cpc(seed = 2^53)$seed(), 2^53)

  expect_error(cpc(seed = -1), class = "datasketches_invalid_seed")
  expect_error(cpc(seed = 1.5), class = "datasketches_invalid_seed")
  expect_error(cpc(seed = NA), class = "datasketches_invalid_seed")
  expect_error(cpc(seed = Inf), class = "datasketches_invalid_seed")
  expect_error(cpc(seed = 2^53 + 2), class = "datasketches_invalid_seed")
})

test_that("cpc(x =) updates the sketch with numeric input", {
  s <- cpc(as.double(1:1000))
  expect_false(s$is_empty())
  expect_true(s$estimate() >= s$lower_bound())
  expect_true(s$estimate() <= s$upper_bound())
  # 3 std dev (~99.7%) bound around the estimate brackets the true count.
  expect_true(s$lower_bound(3) <= 1000 && s$upper_bound(3) >= 1000)
})

test_that("update() accepts character input", {
  s <- cpc()
  s$update(letters)
  expect_false(s$is_empty())
  expect_true(s$estimate() > 0)
})

test_that("update() silently ignores NA, NaN, and NA_character_", {
  s <- cpc()
  s$update(c(1, 2, NA, NaN, 3))
  expect_true(s$estimate() > 0)
  expect_invisible(s$update(4))

  s2 <- cpc()
  expect_invisible(s2$update(c("a", NA, "b")))
  expect_true(s2$estimate() > 0)
})

test_that("update() rejects input that is neither numeric nor character", {
  s <- cpc()
  expect_error(s$update(TRUE), class = "datasketches_invalid_input")
  expect_error(s$update(list(1, 2)), class = "datasketches_invalid_input")
})

test_that("lower_bound()/upper_bound() bracket estimate() and validate num_std_dev", {
  s <- cpc(as.double(1:10000))
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
  s <- cpc(as.double(1:1000))
  info <- summary(s)
  expect_type(info, "list")
  expect_equal(info$type, "cpc")
  expect_equal(info$lg_k, s$lg_k())
  expect_equal(info$seed, s$seed())
  expect_equal(info$is_empty, s$is_empty())
  expect_equal(info$estimate, s$estimate())
  expect_equal(info$lower_bound, s$lower_bound())
  expect_equal(info$upper_bound, s$upper_bound())
})

test_that("merge() combines sketches and mutates the receiver", {
  a <- cpc(as.double(1:500))
  b <- cpc(as.double(501:1000))
  expect_invisible(a$merge(b))
  expect_true(a$lower_bound(3) <= 1000 && a$upper_bound(3) >= 1000)
})

test_that("merge() rejects self-merge, including aliases", {
  a <- cpc(as.double(1:100))
  expect_error(a$merge(a), class = "datasketches_self_merge")
  alias <- a
  expect_error(a$merge(alias), class = "datasketches_self_merge")
})

test_that("merge() rejects a non-sketch argument", {
  a <- cpc(as.double(1:100))
  expect_error(a$merge(42), class = "datasketches_invalid_sketch")

  fake <- structure(new.env(), class = "cpc_sketch")
  expect_error(a$merge(fake), class = "datasketches_invalid_sketch")
})

test_that("merge() rejects sketches with different seeds", {
  a <- cpc(as.double(1:100), seed = 1)
  b <- cpc(as.double(101:200), seed = 2)
  expect_error(a$merge(b), class = "datasketches_seed_mismatch")
})

test_that("merge() combines sketches with different lg_k", {
  a <- cpc(as.double(1:500), lg_k = 10)
  b <- cpc(as.double(501:1000), lg_k = 14)
  expect_invisible(a$merge(b))
  expect_true(a$lower_bound(3) <= 1000 && a$upper_bound(3) >= 1000)
})

test_that("format() and as.character() give the same concise representation", {
  s <- cpc(as.double(1:1000))
  expect_identical(format(s), as.character(s))
  expect_match(format(s), "^<cpc_sketch\\[lg_k=11, estimate=.+\\]>$")

  empty <- cpc()
  expect_match(format(empty), "^<cpc_sketch\\[lg_k=11, empty\\]>$")
})

test_that("print() returns the sketch invisibly", {
  s <- cpc(as.double(1:100))
  expect_output(out <- print(s), "cpc_sketch")
  expect_identical(out, s)
})

test_that("inspect() writes the upstream debug string", {
  s <- cpc(as.double(1:100))
  expect_output(s$inspect(), "CPC sketch")
})

test_that("serialize() round-trips through the bytes constructor", {
  s <- cpc(as.double(1:1000))
  bytes <- s$serialize()
  expect_type(bytes, "raw")

  restored <- cpc(bytes = bytes)
  expect_equal(restored$lg_k(), s$lg_k())
  expect_equal(restored$estimate(), s$estimate())
})

test_that("serialize() round-trips with a non-default seed", {
  s <- cpc(as.double(1:1000), seed = 123)
  bytes <- s$serialize()

  restored <- cpc(bytes = bytes, seed = 123)
  expect_equal(restored$estimate(), s$estimate())
})

test_that("constructor exclusivity is enforced", {
  bytes <- cpc(as.double(1:100))$serialize()
  expect_error(
    cpc(x = 1:10, bytes = bytes),
    class = "datasketches_invalid_args"
  )
  expect_error(
    cpc(bytes = bytes, lg_k = 12),
    class = "datasketches_invalid_args"
  )
  expect_error(
    cpc(bytes = "not raw"),
    class = "datasketches_invalid_args"
  )
})
