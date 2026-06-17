# Tests for the Bloom filter public surface. Bloom filters are not
# sub-linear (sized up front), have no item-type duality, and have no
# notion of an estimate/bounds; assertions focus on construction,
# membership semantics, set operations, and serialization.

test_that("bloom_filter() builds an empty filter with accuracy defaults", {
  bf <- bloom_filter()
  expect_s3_class(bf, "bloom_filter")
  expect_true(bf$is_empty())
  expect_equal(bf$bits_used(), 0)
  expect_equal(bf$seed(), 9001)
  expect_gt(bf$capacity(), 0)
  expect_gt(bf$num_hashes(), 0)
})

test_that("max_items/fpp size the filter and validate inputs", {
  bf <- bloom_filter(max_items = 1000, fpp = 0.01)
  expect_gt(bf$capacity(), 0)

  expect_error(
    bloom_filter(max_items = 1000),
    class = "datasketches_invalid_args"
  )
  expect_error(bloom_filter(fpp = 0.01), class = "datasketches_invalid_args")

  expect_error(
    bloom_filter(max_items = 0, fpp = 0.01),
    class = "datasketches_invalid_max_items"
  )
  expect_error(
    bloom_filter(max_items = 1.5, fpp = 0.01),
    class = "datasketches_invalid_max_items"
  )
  expect_error(
    bloom_filter(max_items = NA, fpp = 0.01),
    class = "datasketches_invalid_max_items"
  )
  expect_error(
    bloom_filter(max_items = Inf, fpp = 0.01),
    class = "datasketches_invalid_max_items"
  )
  expect_error(
    bloom_filter(max_items = 2^53 + 2, fpp = 0.01),
    class = "datasketches_invalid_max_items"
  )

  expect_error(
    bloom_filter(max_items = 1000, fpp = 0),
    class = "datasketches_invalid_fpp"
  )
  expect_error(
    bloom_filter(max_items = 1000, fpp = 1.5),
    class = "datasketches_invalid_fpp"
  )
  expect_error(
    bloom_filter(max_items = 1000, fpp = NA),
    class = "datasketches_invalid_fpp"
  )
})

test_that("num_bits/num_hashes size the filter explicitly and validate inputs", {
  bf <- bloom_filter(num_bits = 9600, num_hashes = 7)
  expect_equal(bf$capacity(), 9600)
  expect_equal(bf$num_hashes(), 7L)

  expect_error(
    bloom_filter(num_bits = 9600),
    class = "datasketches_invalid_args"
  )
  expect_error(
    bloom_filter(num_hashes = 7),
    class = "datasketches_invalid_args"
  )

  expect_error(
    bloom_filter(num_bits = 0, num_hashes = 7),
    class = "datasketches_invalid_num_bits"
  )
  expect_error(
    bloom_filter(num_bits = 1.5, num_hashes = 7),
    class = "datasketches_invalid_num_bits"
  )
  expect_error(
    bloom_filter(num_bits = Inf, num_hashes = 7),
    class = "datasketches_invalid_num_bits"
  )
  expect_error(
    bloom_filter(num_bits = 2^53 + 2, num_hashes = 7),
    class = "datasketches_invalid_num_bits"
  )

  expect_error(
    bloom_filter(num_bits = 1000, num_hashes = 0),
    class = "datasketches_invalid_num_hashes"
  )
  expect_error(
    bloom_filter(num_bits = 1000, num_hashes = 65536),
    class = "datasketches_invalid_num_hashes"
  )
  expect_error(
    bloom_filter(num_bits = 1000, num_hashes = 1.5),
    class = "datasketches_invalid_num_hashes"
  )
})

test_that("the two sizing strategies cannot be combined", {
  expect_error(
    bloom_filter(max_items = 1000, fpp = 0.01, num_bits = 9600, num_hashes = 7),
    class = "datasketches_invalid_args"
  )
  expect_error(
    bloom_filter(max_items = 1000, num_bits = 9600),
    class = "datasketches_invalid_args"
  )
})

test_that("seed = validates and defaults to 9001", {
  expect_equal(bloom_filter()$seed(), 9001)
  expect_equal(bloom_filter(seed = 42)$seed(), 42)
  expect_equal(bloom_filter(seed = 2^53)$seed(), 2^53)

  expect_error(bloom_filter(seed = -1), class = "datasketches_invalid_seed")
  expect_error(bloom_filter(seed = 1.5), class = "datasketches_invalid_seed")
  expect_error(bloom_filter(seed = NA), class = "datasketches_invalid_seed")
  expect_error(bloom_filter(seed = Inf), class = "datasketches_invalid_seed")
  expect_error(
    bloom_filter(seed = 2^53 + 2),
    class = "datasketches_invalid_seed"
  )
})

test_that("bloom_filter(x =) updates the new filter", {
  bf <- bloom_filter(x = letters[1:5], max_items = 100, fpp = 0.01)
  expect_false(bf$is_empty())
  expect_true(all(bf$query(letters[1:5])))
})

test_that("update()/query() round-trip for numeric items", {
  bf <- bloom_filter(max_items = 100, fpp = 0.01, seed = 123)
  bf$update(1:50)
  expect_true(all(bf$query(1:50)))
  expect_false(bf$query(1e9))
})

test_that("update()/query() round-trip for character items", {
  bf <- bloom_filter(max_items = 100, fpp = 0.01)
  bf$update(c("a", "b", "c"))
  expect_equal(bf$query(c("a", "b", "c", "d")), c(TRUE, TRUE, TRUE, FALSE))
})

test_that("update()/query() silently ignore/return NA for missing values", {
  bf <- bloom_filter(max_items = 100, fpp = 0.01)
  expect_invisible(bf$update(c(1, NA, NaN)))
  expect_equal(
    bf$bits_used(),
    bloom_filter(max_items = 100, fpp = 0.01, x = 1)$bits_used()
  )

  expect_identical(bf$query(c(1, NA)), c(TRUE, NA))

  bf2 <- bloom_filter(max_items = 100, fpp = 0.01)
  bf2$update(c("a", NA_character_))
  expect_identical(bf2$query(c("a", NA_character_)), c(TRUE, NA))
})

test_that("query() returns a logical vector the same length as x", {
  bf <- bloom_filter(max_items = 100, fpp = 0.01)
  bf$update(1:5)
  out <- bf$query(1:10)
  expect_type(out, "logical")
  expect_length(out, 10)
})

test_that("query_and_update() reflects pre-update state and updates the filter", {
  bf <- bloom_filter(max_items = 100, fpp = 0.01, seed = 123)
  res <- bf$query_and_update(c(1, 2, 1, 3))
  expect_equal(res, c(FALSE, FALSE, TRUE, FALSE))
  expect_true(all(bf$query(c(1, 2, 3))))
})

test_that("query_and_update() handles NA without updating the filter", {
  bf <- bloom_filter(max_items = 100, fpp = 0.01)
  res <- bf$query_and_update(c(1, NA))
  expect_identical(res, c(FALSE, NA))
  expect_identical(bf$query(NA_real_), NA)
})

test_that("merge() performs an in-place logical OR and mutates the receiver", {
  a <- bloom_filter(max_items = 100, fpp = 0.01, seed = 42)
  b <- bloom_filter(max_items = 100, fpp = 0.01, seed = 42)
  a$update(1:10)
  b$update(11:20)

  expect_invisible(a$merge(b))
  expect_true(all(a$query(1:20)))
})

test_that("intersect() performs an in-place logical AND and mutates the receiver", {
  a <- bloom_filter(max_items = 100, fpp = 0.01, seed = 42)
  b <- bloom_filter(max_items = 100, fpp = 0.01, seed = 42)
  a$update(1:10)
  b$update(5:15)

  expect_invisible(a$intersect(b))
  expect_true(all(a$query(5:10)))
})

test_that("merge()/intersect() reject self-merge, including aliases", {
  a <- bloom_filter(max_items = 100, fpp = 0.01)
  expect_error(a$merge(a), class = "datasketches_self_merge")
  expect_error(a$intersect(a), class = "datasketches_self_merge")

  alias <- a
  expect_error(a$merge(alias), class = "datasketches_self_merge")
})

test_that("merge()/intersect() reject a non-filter argument", {
  a <- bloom_filter(max_items = 100, fpp = 0.01)
  expect_error(a$merge(42), class = "datasketches_invalid_sketch")
  expect_error(a$intersect(42), class = "datasketches_invalid_sketch")

  fake <- structure(new.env(), class = "bloom_filter")
  expect_error(a$merge(fake), class = "datasketches_invalid_sketch")
})

test_that("merge()/intersect() reject incompatible filters", {
  a <- bloom_filter(max_items = 100, fpp = 0.01, seed = 1)
  b_seed <- bloom_filter(max_items = 100, fpp = 0.01, seed = 2)
  b_size <- bloom_filter(max_items = 200, fpp = 0.01, seed = 1)
  b_hashes <- bloom_filter(
    num_bits = a$capacity(),
    num_hashes = a$num_hashes() + 1,
    seed = 1
  )

  expect_false(a$is_compatible(b_seed))
  expect_false(a$is_compatible(b_size))
  expect_false(a$is_compatible(b_hashes))

  expect_error(a$merge(b_seed), class = "datasketches_incompatible_sketch")
  expect_error(a$intersect(b_size), class = "datasketches_incompatible_sketch")
})

test_that("is_compatible() is TRUE for filters with matching seed/num_hashes/capacity", {
  a <- bloom_filter(max_items = 100, fpp = 0.01, seed = 5)
  b <- bloom_filter(max_items = 100, fpp = 0.01, seed = 5)
  expect_true(a$is_compatible(b))
})

test_that("invert() flips all bits in place", {
  bf <- bloom_filter(max_items = 100, fpp = 0.01)
  bf$update(1:5)
  used_before <- bf$bits_used()
  cap <- bf$capacity()

  expect_invisible(bf$invert())
  expect_equal(bf$bits_used(), cap - used_before)
})

test_that("reset() clears the filter back to empty", {
  bf <- bloom_filter(max_items = 100, fpp = 0.01)
  bf$update(1:5)
  expect_invisible(bf$reset())
  expect_true(bf$is_empty())
  expect_equal(bf$bits_used(), 0)
})

test_that("metadata accessors agree with summary()", {
  bf <- bloom_filter(max_items = 100, fpp = 0.01, seed = 7)
  bf$update(1:10)
  info <- bf$summary()

  expect_equal(info$type, "bloom_filter")
  expect_equal(info$capacity, bf$capacity())
  expect_equal(info$num_hashes, bf$num_hashes())
  expect_equal(info$seed, bf$seed())
  expect_equal(info$bits_used, bf$bits_used())
  expect_equal(info$is_empty, bf$is_empty())
})

test_that("format() and as.character() give the same concise representation", {
  bf <- bloom_filter(num_bits = 9600, num_hashes = 7)
  bf$update(1:10)
  expect_identical(format(bf), as.character(bf))
  expect_match(
    format(bf),
    "^<bloom_filter\\[capacity=9600, num_hashes=7, bits_used=\\d+\\]>$"
  )

  empty <- bloom_filter(num_bits = 9600, num_hashes = 7)
  expect_match(
    format(empty),
    "^<bloom_filter\\[capacity=9600, num_hashes=7, empty\\]>$"
  )
})

test_that("print() returns the filter invisibly", {
  bf <- bloom_filter(max_items = 100, fpp = 0.01)
  bf$update(1:10)
  expect_output(out <- print(bf), "bloom_filter")
  expect_identical(out, bf)
})

test_that("summary() returns the structured metadata list", {
  bf <- bloom_filter(max_items = 100, fpp = 0.01)
  expect_identical(summary(bf), bf$summary())
})

test_that("inspect() writes the upstream debug string", {
  bf <- bloom_filter(max_items = 100, fpp = 0.01)
  expect_output(bf$inspect(), "Bloom Filter Summary")
})

test_that("serialize() round-trips through the bytes constructor", {
  bf <- bloom_filter(max_items = 100, fpp = 0.01, seed = 77)
  bf$update(1:20)
  bytes <- bf$serialize()
  expect_type(bytes, "raw")

  restored <- bloom_filter(bytes = bytes)
  expect_equal(restored$capacity(), bf$capacity())
  expect_equal(restored$num_hashes(), bf$num_hashes())
  expect_equal(restored$seed(), bf$seed())
  expect_equal(restored$bits_used(), bf$bits_used())
  expect_true(all(restored$query(1:20)))
})

test_that("serialize() round-trips a character filter", {
  bf <- bloom_filter(max_items = 100, fpp = 0.01)
  bf$update(letters[1:5])
  bytes <- bf$serialize()

  restored <- bloom_filter(bytes = bytes)
  expect_true(all(restored$query(letters[1:5])))
})

test_that("constructor exclusivity is enforced", {
  bytes <- bloom_filter(max_items = 100, fpp = 0.01)$serialize()

  expect_error(
    bloom_filter(x = 1:10, bytes = bytes),
    class = "datasketches_invalid_args"
  )
  expect_error(
    bloom_filter(bytes = bytes, max_items = 100),
    class = "datasketches_invalid_args"
  )
  expect_error(
    bloom_filter(bytes = bytes, fpp = 0.01),
    class = "datasketches_invalid_args"
  )
  expect_error(
    bloom_filter(bytes = bytes, num_bits = 9600),
    class = "datasketches_invalid_args"
  )
  expect_error(
    bloom_filter(bytes = bytes, num_hashes = 7),
    class = "datasketches_invalid_args"
  )
  expect_error(
    bloom_filter(bytes = bytes, seed = 1),
    class = "datasketches_invalid_args"
  )
  expect_error(
    bloom_filter(bytes = "not raw"),
    class = "datasketches_invalid_args"
  )
})

test_that("bloom_filter_suggest_num_filter_bits() and bloom_filter_suggest_num_hashes() compute sizing", {
  num_bits <- bloom_filter_suggest_num_filter_bits(1000, 0.01)
  expect_type(num_bits, "double")
  expect_gt(num_bits, 0)

  num_hashes <- bloom_filter_suggest_num_hashes(1000, num_bits)
  expect_type(num_hashes, "integer")
  expect_gt(num_hashes, 0)

  bf <- bloom_filter(num_bits = num_bits, num_hashes = num_hashes)
  expect_equal(bf$num_hashes(), num_hashes)

  expect_error(
    bloom_filter_suggest_num_filter_bits(0, 0.01),
    class = "datasketches_invalid_max_items"
  )
  expect_error(
    bloom_filter_suggest_num_filter_bits(Inf, 0.01),
    class = "datasketches_invalid_max_items"
  )
  expect_error(
    bloom_filter_suggest_num_filter_bits(1000, 0),
    class = "datasketches_invalid_fpp"
  )
  expect_error(
    bloom_filter_suggest_num_filter_bits(2^53 + 2, 0.01),
    class = "datasketches_invalid_max_items"
  )
  expect_error(
    bloom_filter_suggest_num_hashes(0, 1000),
    class = "datasketches_invalid_max_items"
  )
  expect_error(
    bloom_filter_suggest_num_hashes(1000, 0),
    class = "datasketches_invalid_num_bits"
  )
  expect_error(
    bloom_filter_suggest_num_hashes(1000, Inf),
    class = "datasketches_invalid_num_bits"
  )
  expect_error(
    bloom_filter_suggest_num_hashes(1000, 2^53 + 2),
    class = "datasketches_invalid_num_bits"
  )
})
