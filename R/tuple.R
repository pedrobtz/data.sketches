# Array of Doubles (Tuple) sketch: the R6 implementation, its exported
# constructor, and the top-level set-operation functions
# (`array_of_doubles_union()`, `array_of_doubles_intersection()`,
# `array_of_doubles_difference()`). The generator is internal; users go
# through `array_of_doubles()`. See `_dev/WORKING-ON.md` for the public API
# contract and implementation status.
#
# An Array of Doubles sketch extends a Theta sketch: each retained key is
# additionally associated with a fixed-length array of `num_values` doubles.
# Like Theta, it comes in two flavors that share a common native base: an
# *update* sketch (mutable, built via `$update()`) and a *compact* sketch
# (immutable; the result of `$merge()`, a set operation, or `bytes =`
# reconstruction). `$is_compact()` distinguishes the two. `$merge()` and the
# set-operation functions below always produce compact sketches. Native
# bridge functions live in `src/array_of_doubles_sketch.cpp`.

# Reach a sibling instance's native pointer / seed / lg_k hint. R6 `private`
# is per-instance, so operations between two sketches (merge, set operations)
# read the other's state through its enclosing environment. Internal; never a
# public surface.
aod_ptr <- function(x) {
  x$.__enclos_env__$private$ptr
}

aod_seed <- function(x) {
  x$.__enclos_env__$private$hash_seed
}

aod_lg_k_hint <- function(x) {
  x$.__enclos_env__$private$lg_k_hint
}

# Build an `array_of_doubles_sketch` R6 object that wraps an existing native
# pointer (the result of a set operation). Internal; never a public surface.
new_array_of_doubles_sketch <- function(ptr, seed, lg_k_hint) {
  obj <- array_of_doubles_sketch_generator$new(
    num_values = aod_get_num_values_cpp(ptr),
    seed = seed
  )
  priv <- obj$.__enclos_env__$private
  priv$ptr <- ptr
  priv$lg_k_hint <- lg_k_hint
  obj
}

# Resolve the shared seed for a two-sketch operation. Both sketches must have
# been created with the same `seed`.
aod_check_matching_seeds <- function(a, b, call = rlang::caller_env()) {
  seed_a <- aod_seed(a)
  seed_b <- aod_seed(b)
  if (!identical(seed_a, seed_b)) {
    abort_invalid(
      "`a` and `b` must be Array of Doubles sketches created with the same `seed`.",
      "datasketches_seed_mismatch",
      call = call
    )
  }
  seed_a
}

# Resolve the shared `num_values` for a two-sketch union/intersection. Both
# sketches must have the same `num_values`, since the combining policy
# operates element-wise on the value arrays.
aod_check_matching_num_values <- function(a, b, call = rlang::caller_env()) {
  num_values_a <- a$num_values()
  num_values_b <- b$num_values()
  if (!identical(num_values_a, num_values_b)) {
    abort_invalid(
      "`a` and `b` must be Array of Doubles sketches with the same `num_values`.",
      "datasketches_incompatible_sketch",
      call = call
    )
  }
  num_values_a
}

# Internal R6 generator. `cloneable = FALSE` because the default shallow clone
# would copy the R6 wrapper while aliasing the same native sketch.
array_of_doubles_sketch_generator <- R6Class(
  "array_of_doubles_sketch",
  cloneable = FALSE,
  public = list(
    initialize = function(
      x = NULL,
      values = NULL,
      lg_k = NULL,
      num_values = NULL,
      seed = NULL,
      bytes = NULL
    ) {
      if (!is.null(x) && !is.null(bytes)) {
        abort_invalid(
          "At most one of `x` and `bytes` may be supplied.",
          "datasketches_invalid_args"
        )
      }
      seed <- if (is.null(seed)) 9001 else check_seed(seed)
      if (!is.null(bytes)) {
        if (!is.null(lg_k) || !is.null(num_values)) {
          abort_invalid(
            "`lg_k` and `num_values` cannot be set when `bytes` is supplied; they are restored from the payload.",
            "datasketches_invalid_args"
          )
        }
        if (!is.raw(bytes)) {
          abort_invalid(
            "`bytes` must be a raw vector.",
            "datasketches_invalid_args"
          )
        }
        private$ptr <- aod_deserialize_cpp(bytes, seed)
        private$lg_k_hint <- 12L
      } else {
        lg_k <- if (is.null(lg_k)) {
          12L
        } else {
          check_lg_k(lg_k, min = 5L, max = 26L)
        }
        num_values <- if (is.null(num_values)) {
          1L
        } else {
          check_num_values(num_values)
        }
        private$ptr <- aod_create_cpp(lg_k, num_values, seed)
        private$lg_k_hint <- lg_k
        if (!is.null(x)) {
          self$update(x, values)
        } else if (!is.null(values)) {
          abort_invalid(
            "`values` cannot be set without `x`.",
            "datasketches_invalid_args"
          )
        }
      }
      private$hash_seed <- seed
      invisible(self)
    },

    # Accepts numeric or character input for `x`, each element hashed and
    # contributing to the distinct-count estimate. `values` is a numeric
    # vector (when `num_values() == 1`) or a numeric matrix with
    # `num_values()` columns, recycled to `length(x)` rows if a single
    # value/row is supplied; it defaults to `1`s. `NA`/`NaN`/`NA_character_`
    # in `x` are silently ignored (and the corresponding row of `values`
    # dropped), matching the missing-value policy used across families.
    # Errors if the sketch is compact (e.g. after `$merge()` or `bytes =`
    # reconstruction); compact sketches are immutable.
    update = function(x, values = NULL) {
      if (self$is_compact()) {
        abort_invalid(
          "Cannot update a compact Array of Doubles sketch.",
          "datasketches_invalid_op"
        )
      }
      x <- check_hashable_stream(x, "x")
      num_values <- self$num_values()
      values <- if (is.null(values)) {
        matrix(1, nrow = length(x), ncol = num_values)
      } else {
        check_aod_values(values, length(x), num_values)
      }
      keep <- !is.na(x)
      values <- values[keep, , drop = FALSE]
      x <- x[keep]
      if (length(x) > 0L) {
        if (is.character(x)) {
          aod_update_strings_cpp(private$ptr, x, values)
        } else {
          aod_update_doubles_cpp(private$ptr, x, values)
        }
      }
      invisible(self)
    },

    # Mutating merge. Array of Doubles has no direct merge(); internally this
    # feeds both sketches into a union sized for the larger configured
    # `lg_k`, combining value arrays of matching keys by element-wise sum,
    # and replaces this sketch's state with the (compact) union result. Both
    # sketches must share the same `seed` and `num_values`; self-merge is
    # rejected for consistency with other families. After merge(), the
    # receiver is compact and can no longer be updated.
    merge = function(other) {
      check_array_of_doubles(other, "other")
      if (identical(private$ptr, aod_ptr(other))) {
        abort_invalid(
          "A sketch cannot be merged into itself.",
          "datasketches_self_merge"
        )
      }
      if (!identical(private$hash_seed, aod_seed(other))) {
        abort_invalid(
          "Cannot merge Array of Doubles sketches created with different `seed` values.",
          "datasketches_seed_mismatch"
        )
      }
      if (!identical(self$num_values(), other$num_values())) {
        abort_invalid(
          "Cannot merge Array of Doubles sketches with different `num_values`.",
          "datasketches_incompatible_sketch"
        )
      }
      lg_max_k <- max(private$lg_k_hint, aod_lg_k_hint(other))
      aod_merge_cpp(
        private$ptr,
        aod_ptr(other),
        lg_max_k,
        private$hash_seed
      )
      private$lg_k_hint <- lg_max_k
      invisible(self)
    },

    # Approximate count of distinct keys seen so far.
    estimate = function() {
      aod_get_estimate_cpp(private$ptr)
    },

    # Approximate confidence interval around `estimate()`, at 1, 2, or 3
    # standard deviations.
    lower_bound = function(num_std_dev = 1) {
      num_std_dev <- check_num_std_dev(num_std_dev)
      aod_get_lower_bound_cpp(private$ptr, num_std_dev)
    },

    upper_bound = function(num_std_dev = 1) {
      num_std_dev <- check_num_std_dev(num_std_dev)
      aod_get_upper_bound_cpp(private$ptr, num_std_dev)
    },

    # Estimated sum of each value column over the full input stream: the sum
    # of retained values for that column, scaled by `1 / theta()`. Returns a
    # numeric vector of length `num_values()`.
    column_sums = function() {
      aod_column_sums_cpp(private$ptr)
    },

    # Number of double values associated with each retained key. Fixed at
    # construction (or restored from `bytes`).
    num_values = function() {
      aod_get_num_values_cpp(private$ptr)
    },

    # log2 of the configured nominal number of entries. Not defined for a
    # compact sketch (`$is_compact()` is `TRUE`).
    lg_k = function() {
      if (self$is_compact()) {
        abort_invalid(
          "`lg_k()` is not defined for a compact Array of Doubles sketch.",
          "datasketches_invalid_op"
        )
      }
      aod_get_lg_k_cpp(private$ptr)
    },

    # Hash seed this sketch was created with. Two sketches can only be merged
    # or combined with a set operation if their seeds match.
    seed = function() {
      private$hash_seed
    },

    # Effective sampling probability, a value in `(0, 1]`. `1` means the
    # sketch is in exact mode (every retained entry has been seen).
    theta = function() {
      aod_get_theta_cpp(private$ptr)
    },

    num_retained = function() {
      aod_get_num_retained_cpp(private$ptr)
    },

    is_empty = function() {
      aod_is_empty_cpp(private$ptr)
    },

    is_estimation_mode = function() {
      aod_is_estimation_mode_cpp(private$ptr)
    },

    is_ordered = function() {
      aod_is_ordered_cpp(private$ptr)
    },

    # `TRUE` if this sketch is an immutable compact sketch (the result of
    # `$merge()`, a set operation, or `bytes =` reconstruction); `FALSE` if it
    # is a mutable update sketch that can still be `$update()`d.
    is_compact = function() {
      aod_is_compact_cpp(private$ptr)
    },

    # Stable structured metadata (a plain named list).
    summary = function(...) {
      list(
        type = private$type_id,
        is_compact = self$is_compact(),
        lg_k = if (self$is_compact()) NA_integer_ else self$lg_k(),
        num_values = self$num_values(),
        seed = self$seed(),
        is_empty = self$is_empty(),
        is_estimation_mode = self$is_estimation_mode(),
        estimate = self$estimate(),
        lower_bound = self$lower_bound(),
        upper_bound = self$upper_bound(),
        theta = self$theta(),
        num_retained = self$num_retained(),
        column_sums = self$column_sums()
      )
    },

    # Concise one-line representation (same text as `as.character()`).
    format = function(...) {
      kind <- if (self$is_compact()) {
        "compact"
      } else {
        sprintf("lg_k=%d", self$lg_k())
      }
      if (self$is_empty()) {
        sprintf(
          "<array_of_doubles_sketch[%s, num_values=%d, empty]>",
          kind,
          self$num_values()
        )
      } else {
        sprintf(
          "<array_of_doubles_sketch[%s, num_values=%d, estimate=%s]>",
          kind,
          self$num_values(),
          format(self$estimate(), scientific = FALSE, trim = TRUE, digits = 6)
        )
      }
    },

    print = function(...) {
      empty <- self$is_empty()
      cat("<array_of_doubles_sketch>\n")
      if (self$is_compact()) {
        cat("  lg_k        : <not defined, compact>\n")
      } else {
        cat(sprintf("  lg_k        : %d\n", self$lg_k()))
      }
      cat(sprintf("  compact     : %s\n", self$is_compact()))
      cat(sprintf("  num_values  : %d\n", self$num_values()))
      cat(sprintf(
        "  seed        : %s\n",
        format(self$seed(), scientific = FALSE)
      ))
      cat(sprintf("  empty       : %s\n", empty))
      if (empty) {
        cat("  estimate    : <empty>\n")
      } else {
        cat(sprintf("  estimate    : %s\n", self$estimate()))
        cat(sprintf(
          "  bounds      : [%s, %s] (1 std dev)\n",
          self$lower_bound(),
          self$upper_bound()
        ))
        cat(sprintf(
          "  column_sums : %s\n",
          paste(
            format(self$column_sums(), scientific = FALSE, trim = TRUE),
            collapse = ", "
          )
        ))
      }
      invisible(self)
    },

    # Verbose upstream debug string.
    inspect = function(items = FALSE) {
      items <- check_flag(items, "items")
      cat(aod_to_string_cpp(private$ptr, items))
      invisible(self)
    },

    serialize = function() {
      aod_serialize_cpp(private$ptr)
    },

    # Stable type id for later typed persistence (write_sketch, deferred to 0.1.1).
    sketch_type = function() {
      private$type_id
    }
  ),
  private = list(
    ptr = NULL,
    hash_seed = NULL,
    lg_k_hint = NULL,
    type_id = "array_of_doubles"
  )
)

#' Array of Doubles (Tuple) sketch for estimating sums alongside distinct counts
#'
#' Creates an
#' [Array of Doubles](https://datasketches.apache.org/docs/Tuple/TupleOverview.html)
#' sketch, a Tuple sketch that extends a [theta()] sketch by associating a
#' fixed-length array of `num_values` doubles with each retained key. It
#' estimates not only the number of distinct keys (`$estimate()`, as for
#' [theta()]) but also the sum of each value column over the full input
#' stream (`$column_sums()`), e.g. to estimate the total of a numeric measure
#' across distinct users.
#'
#' At most one of `x` or `bytes` may be supplied:
#'
#' * Pass `x` to build a sketch and immediately update it with a numeric or
#'   character vector of keys (optionally with `values`).
#' * Pass `bytes` to reconstruct a sketch from a native serialized payload (as
#'   produced by `sketch$serialize()`). The result is always a *compact*
#'   sketch (see below); `lg_k` and `num_values` must not be supplied
#'   alongside `bytes`. Unlike `lg_k`, the hash `seed` is *not* stored in the
#'   payload and must be supplied if the original sketch did not use the
#'   default.
#' * Pass neither for an empty (mutable) sketch with the given `lg_k`,
#'   `num_values`, and `seed`.
#'
#' `update()` silently ignores `NA`/`NaN`/`NA_character_` in `x` (and the
#' corresponding row of `values`), matching the missing-value policy used
#' across families; there is no `na_rm` argument.
#'
#' An Array of Doubles sketch is either an *update* sketch (mutable,
#' `$is_compact()` is `FALSE`) or a *compact* sketch (immutable,
#' `$is_compact()` is `TRUE`). Fresh sketches built from `x`/`lg_k` are update
#' sketches and can be grown with `$update()`. Compact sketches arise from
#' `bytes =` reconstruction, `$merge()`, or any of the
#' `array_of_doubles_*()` set operations, and cannot be updated further.
#' `$lg_k()` is only defined for update sketches.
#'
#' Two sketches can only be merged with `$merge()`, or combined with
#' `array_of_doubles_union()` / `array_of_doubles_intersection()`, if they
#' share the same `seed` (a mismatch raises `datasketches_seed_mismatch`) and
#' the same `num_values` (a mismatch raises
#' `datasketches_incompatible_sketch`). Value arrays for matching keys are
#' combined by element-wise sum. `$merge()` mutates the receiver into a
#' compact sketch holding the union of both inputs (so it can no longer be
#' `$update()`d afterward).
#'
#' @param x Optional numeric or character vector of keys to update the new
#'   sketch with. Each element is hashed and contributes to the
#'   distinct-count estimate.
#' @param values Optional value(s) associated with each element of `x`: a
#'   numeric vector (when `num_values == 1`) or a numeric matrix with
#'   `num_values` columns, recycled to `length(x)` rows if a single
#'   value/row is supplied. Defaults to `1`s (so `$column_sums()` estimates
#'   the count of each key, like `$estimate()`). Cannot be set without `x`.
#' @param lg_k log2 of the nominal number of entries, a single whole number in
#'   `[5, 26]`. Larger `lg_k` is more accurate and larger. Defaults to `12`
#'   (resolved when a fresh sketch is built). Must not be set when `bytes` is
#'   supplied.
#' @param num_values Number of double values associated with each retained
#'   key, a single whole number in `[1, 255]`. Defaults to `1`. Must not be
#'   set when `bytes` is supplied.
#' @param seed Hash seed, a single non-negative whole number up to `2^53`.
#'   Defaults to `9001` (the upstream default), resolved whether or not `bytes`
#'   is supplied.
#' @param bytes Optional [raw] vector holding a native serialized sketch to
#'   reconstruct. The result is always a compact sketch.
#'
#' @return An `array_of_doubles_sketch` object. Key methods:
#'   \describe{
#'     \item{`$update(x, values = NULL)`}{Add keys with associated values
#'       (mutates, returns the sketch). Errors if the sketch is compact.}
#'     \item{`$merge(other)`}{Absorb another sketch with the same `seed` and
#'       `num_values`, becoming compact (mutates, returns the sketch).}
#'     \item{`$estimate()`}{Approximate number of distinct keys seen.}
#'     \item{`$lower_bound(num_std_dev = 1)` / `$upper_bound(num_std_dev = 1)`}{
#'       Approximate confidence bounds on `estimate()`, at 1, 2, or 3 standard
#'       deviations.}
#'     \item{`$column_sums()`}{Estimated sum of each value column over the
#'       full input stream.}
#'     \item{`$lg_k()`, `$num_values()`, `$seed()`, `$theta()`,
#'       `$num_retained()`, `$is_empty()`, `$is_estimation_mode()`,
#'       `$is_ordered()`, `$is_compact()`}{Metadata accessors.}
#'     \item{`$summary()`, `$inspect()`, `$serialize()`}{Structured metadata,
#'       verbose debug output, and the native byte payload.}
#'   }
#'
#' @examples
#' keys <- sample(1000, 5000, replace = TRUE)
#' values <- runif(length(keys))
#' sketch <- array_of_doubles(keys, values)
#' sketch$estimate()
#' sketch$column_sums()
#'
#' # Round-trip through the native byte format (always compact).
#' restored <- array_of_doubles(bytes = sketch$serialize())
#' restored$is_compact()
#' identical(restored$column_sums(), sketch$column_sums())
#'
#' @export
array_of_doubles <- function(
  x = NULL,
  values = NULL,
  lg_k = NULL,
  num_values = NULL,
  seed = NULL,
  bytes = NULL
) {
  array_of_doubles_sketch_generator$new(
    x = x,
    values = values,
    lg_k = lg_k,
    num_values = num_values,
    seed = seed,
    bytes = bytes
  )
}

#' Array of Doubles sketch set operations
#'
#' Combine two [array_of_doubles()] sketches into a new compact
#' `array_of_doubles_sketch` result, without mutating either input. `a` and
#' `b` must be Array of Doubles sketches created with the same `seed` (a
#' mismatch raises `datasketches_seed_mismatch`).
#'
#' * `array_of_doubles_union(a, b)` estimates the size of the union
#'   `union(A, B)`. `a` and `b` must also share the same `num_values` (a
#'   mismatch raises `datasketches_incompatible_sketch`); value arrays for
#'   matching keys are combined by element-wise sum.
#' * `array_of_doubles_intersection(a, b)` estimates the size of the
#'   intersection `intersection(A, B)`, with the same `num_values`
#'   requirement and combining rule as `array_of_doubles_union()`.
#' * `array_of_doubles_difference(a, b)` estimates the size of the set
#'   difference `A \\ B` (elements in `A` but not `B`), retaining `a`'s value
#'   arrays unchanged for the retained keys.
#'
#' @param a,b `array_of_doubles_sketch` objects created with the same `seed`.
#' @param lg_k For `array_of_doubles_union()`, log2 of the nominal number of
#'   entries for the union's internal sketch, a single whole number in
#'   `[5, 26]`. Defaults to the larger of `a` and `b`'s configured `lg_k` (or
#'   `12` for compact inputs).
#'
#' @return A compact `array_of_doubles_sketch` object.
#'
#' @examples
#' a <- array_of_doubles(1:1000, runif(1000))
#' b <- array_of_doubles(501:1500, runif(1000))
#' array_of_doubles_union(a, b)$column_sums()
#' array_of_doubles_intersection(a, b)$estimate()
#' array_of_doubles_difference(a, b)$estimate()
#'
#' @name array_of_doubles_set_operations
#' @export
array_of_doubles_union <- function(a, b, lg_k = NULL) {
  check_array_of_doubles(a, "a")
  check_array_of_doubles(b, "b")
  seed <- aod_check_matching_seeds(a, b)
  num_values <- aod_check_matching_num_values(a, b)
  lg_k <- if (is.null(lg_k)) {
    max(aod_lg_k_hint(a), aod_lg_k_hint(b))
  } else {
    check_lg_k(lg_k, min = 5L, max = 26L)
  }
  ptr <- aod_union_cpp(aod_ptr(a), aod_ptr(b), lg_k, seed, num_values)
  new_array_of_doubles_sketch(ptr, seed, lg_k)
}

#' @rdname array_of_doubles_set_operations
#' @export
array_of_doubles_intersection <- function(a, b) {
  check_array_of_doubles(a, "a")
  check_array_of_doubles(b, "b")
  seed <- aod_check_matching_seeds(a, b)
  num_values <- aod_check_matching_num_values(a, b)
  ptr <- aod_intersection_cpp(aod_ptr(a), aod_ptr(b), seed, num_values)
  new_array_of_doubles_sketch(
    ptr,
    seed,
    max(aod_lg_k_hint(a), aod_lg_k_hint(b))
  )
}

#' @rdname array_of_doubles_set_operations
#' @export
array_of_doubles_difference <- function(a, b) {
  check_array_of_doubles(a, "a")
  check_array_of_doubles(b, "b")
  seed <- aod_check_matching_seeds(a, b)
  num_values <- a$num_values()
  ptr <- aod_a_not_b_cpp(aod_ptr(a), aod_ptr(b), seed, num_values)
  new_array_of_doubles_sketch(
    ptr,
    seed,
    max(aod_lg_k_hint(a), aod_lg_k_hint(b))
  )
}
