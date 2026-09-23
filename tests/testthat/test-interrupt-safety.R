# The native update/query loops probe for user interrupts so a multi-million
# element call stays abortable. That probe must unwind through C++ rather than
# longjmp past it: `R_CheckUserInterrupt()` skips every destructor in the
# frame, including the one that releases cpp11's preserve token on the input
# vector, so an interrupted update used to pin its whole input in R's precious
# list for the life of the session. `cpp11::check_user_interrupt()` routes the
# unwind through `R_UnwindProtect` so destructors run.
#
# `setTimeLimit()` raises at the same probe points as a user interrupt, which
# makes the path testable without sending a signal.

# Interrupt `expr` after `seconds` and report whether it actually fired.
interrupt_after <- function(expr, seconds) {
  fired <- TRUE
  tryCatch(
    {
      setTimeLimit(elapsed = seconds, transient = TRUE)
      on.exit(setTimeLimit(), add = TRUE)
      force(expr)
      fired <- FALSE
    },
    error = function(e) NULL
  )
  setTimeLimit()
  fired
}

test_that("an interrupted update releases its input vector", {
  skip_on_cran()

  # Large enough that the update spans many interrupt probes and that the
  # leaked vector is unmistakable against baseline noise.
  n <- 2e7
  x <- runif(n)
  sketch <- kll_doubles()

  invisible(gc(full = TRUE))
  fired <- interrupt_after(sketch$update(x), seconds = 0.25)
  skip_if_not(fired, "update() completed before the time limit fired")

  # Drop the only R-level reference; if the native loop leaked cpp11's
  # preserve token, the vector survives the collection anyway.
  rm(x)
  invisible(gc(full = TRUE))
  vcells <- gc(full = TRUE)["Vcells", "used"]

  # The vector occupies `n` Vcells. Allow generous headroom for whatever else
  # the session holds; a leak would leave essentially all of it behind.
  expect_lt(vcells, n / 2)
})

test_that("a sketch stays usable after an interrupted update", {
  skip_on_cran()

  x <- runif(2e7)
  sketch <- kll_doubles()
  fired <- interrupt_after(sketch$update(x), seconds = 0.25)
  skip_if_not(fired, "update() completed before the time limit fired")

  # The partially-updated sketch is still a valid, queryable object: the
  # unwind must not corrupt native state.
  expect_true(sketch$n() > 0)
  expect_lt(sketch$n(), length(x))
  expect_false(sketch$is_empty())
  expect_type(sketch$quantile(0.5), "double")

  # And it can still be updated and merged afterwards.
  sketch$update(c(1, 2, 3))
  other <- kll_doubles(as.double(1:100))
  expect_no_error(sketch$merge(other))
})

test_that("short updates are not interrupted spuriously", {
  # The probe fires on 64k boundaries but must not trip on the first element,
  # which would pump the R event loop on every single update() call.
  sketch <- kll_doubles()
  expect_no_error(sketch$update(as.double(1:10)))
  expect_equal(sketch$n(), 10)
})
