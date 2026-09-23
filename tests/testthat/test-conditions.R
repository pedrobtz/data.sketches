# Errors that originate in the C++ bridge are translated onto the same
# `datasketches_error` hierarchy as the Tier-1 R validators, so a single
# `tryCatch(datasketches_error = )` catches every failure the package can
# raise. These tests pin the three categories that used to surface as bare
# `simpleError`s: a corrupt `bytes` payload, a query on an empty sketch, and a
# sketch whose native handle did not survive `readRDS()`.

# Every exported constructor, paired with a builder for a populated instance.
sketch_builders <- list(
  kll_doubles = function() kll_doubles(as.double(1:100)),
  kll_floats = function() kll_floats(as.double(1:100)),
  req = function() req(as.double(1:100)),
  tdigest_double = function() tdigest_double(as.double(1:100)),
  hll = function() hll(as.character(1:100)),
  cpc = function() cpc(as.character(1:100)),
  theta = function() theta(as.character(1:100)),
  frequent_items = function() frequent_items(),
  count_min = function() count_min(),
  array_of_doubles = function() array_of_doubles(as.character(1:100)),
  varopt = function() varopt(as.double(1:100)),
  ebpps = function() ebpps(as.double(1:100)),
  bloom_filter = function() bloom_filter(max_items = 100, fpp = 0.01)
)

test_that("a corrupt `bytes` payload raises a classed condition", {
  garbage <- as.raw(rep(255L, 64L))
  for (name in names(sketch_builders)) {
    expect_error(
      do.call(name, list(bytes = garbage)),
      class = "datasketches_invalid_bytes",
      info = name
    )
  }
})

test_that("a truncated payload raises a classed condition", {
  for (name in names(sketch_builders)) {
    bytes <- sketch_builders[[name]]()$serialize()
    expect_error(
      do.call(name, list(bytes = bytes[seq_len(5L)])),
      class = "datasketches_invalid_bytes",
      info = name
    )
  }
})

test_that("classed `bytes` errors chain the native message as the parent", {
  condition <- tryCatch(
    kll_doubles(bytes = as.raw(rep(255L, 64L))),
    condition = identity
  )
  expect_s3_class(condition, "datasketches_invalid_bytes")
  expect_s3_class(condition$parent, "condition")
  expect_match(conditionMessage(condition$parent), "corruption|buffer|M must be")
})

test_that("queries on an empty sketch raise a classed condition", {
  empties <- list(
    kll_doubles = kll_doubles(),
    kll_floats = kll_floats(),
    req = req(),
    tdigest_double = tdigest_double()
  )
  for (name in names(empties)) {
    s <- empties[[name]]
    expect_error(s$quantile(0.5), class = "datasketches_empty_sketch", info = name)
    expect_error(s$rank(1), class = "datasketches_empty_sketch", info = name)
    expect_error(s$cdf(1), class = "datasketches_empty_sketch", info = name)
    expect_error(s$pmf(1), class = "datasketches_empty_sketch", info = name)
    expect_error(s$min(), class = "datasketches_empty_sketch", info = name)
    expect_error(s$max(), class = "datasketches_empty_sketch", info = name)
  }
})

test_that("summary() and print() stay safe on an empty sketch", {
  # The empty-sketch guard must not reach these: they report `<empty>` instead.
  for (build in list(kll_doubles, kll_floats, req, tdigest_double)) {
    s <- build()
    expect_type(s$summary(), "list")
    expect_output(print(s))
  }
})

test_that("a sketch restored with readRDS() reports a classed, actionable error", {
  path <- tempfile(fileext = ".rds")
  on.exit(unlink(path), add = TRUE)
  for (name in names(sketch_builders)) {
    saveRDS(sketch_builders[[name]](), path)
    restored <- readRDS(path)

    expect_error(print(restored), class = "datasketches_dead_pointer", info = name)
    expect_error(format(restored), class = "datasketches_dead_pointer", info = name)
    expect_error(summary(restored), class = "datasketches_dead_pointer", info = name)
    expect_error(
      as.character(restored),
      class = "datasketches_dead_pointer",
      info = name
    )
  }
})

test_that("the dead-handle error points at serialize() as the supported route", {
  path <- tempfile(fileext = ".rds")
  on.exit(unlink(path), add = TRUE)
  saveRDS(kll_doubles(as.double(1:100)), path)
  expect_error(print(readRDS(path)), regexp = "\\$serialize\\(\\)")
})

test_that("every classed condition also inherits datasketches_error", {
  classes <- c(
    "datasketches_invalid_bytes",
    "datasketches_empty_sketch",
    "datasketches_dead_pointer"
  )
  path <- tempfile(fileext = ".rds")
  on.exit(unlink(path), add = TRUE)
  saveRDS(kll_doubles(as.double(1:100)), path)
  conditions <- list(
    tryCatch(kll_doubles(bytes = as.raw(rep(255L, 64L))), condition = identity),
    tryCatch(kll_doubles()$quantile(0.5), condition = identity),
    tryCatch(print(readRDS(path)), condition = identity)
  )
  for (i in seq_along(conditions)) {
    expect_s3_class(conditions[[i]], classes[[i]])
    expect_s3_class(conditions[[i]], "datasketches_error")
  }
})

# lg_k hint recovery ----------------------------------------------------------

test_that("lg_k_hint_from_retained() recovers the width and clamps sanely", {
  # A compact sketch in estimation mode retains at least 2^lg_k and fewer than
  # 2^(lg_k + 1) entries, oscillating inside that octave as the table grows and
  # is rebuilt. Anywhere in the octave must recover the same lg_k.
  for (lg_k in c(13L, 14L, 16L, 18L, 20L)) {
    octave <- c(1, 1.01, 1.24, 1.5, 1.75, 1.99)
    for (position in octave) {
      expect_equal(
        lg_k_hint_from_retained(floor(position * 2^lg_k)),
        lg_k,
        info = paste(lg_k, position)
      )
    }
  }

  # Below the default width, fall back to the default rather than shrinking.
  expect_equal(lg_k_hint_from_retained(0), 12L)
  expect_equal(lg_k_hint_from_retained(1), 12L)
  expect_equal(lg_k_hint_from_retained(100), 12L)

  # Never exceed the maximum the builder accepts.
  expect_equal(lg_k_hint_from_retained(2^40), 26L)

  # Degenerate input falls back rather than propagating NA.
  expect_equal(lg_k_hint_from_retained(NA_real_), 12L)
  expect_equal(lg_k_hint_from_retained(numeric(0)), 12L)
})
