# VarOpt sampling sketch: the R6 implementation, its exported constructor,
# and the top-level `varopt_union()` set operation. The generator is
# internal; users go through `varopt()`. See `_dev/WORKING-ON.md` for the
# public API contract and implementation status.
#
# A VarOpt sketch samples up to `k` items from a stream of (item, weight)
# pairs, designed for minimum-variance estimation of subset sums over the
# full stream. Unlike Theta/HLL/CPC, items are retained verbatim (not
# hashed), so the item type (numeric or character) is fixed at creation.
# Native bridge functions live in `src/var_opt_sketch.cpp`.

# Reach a sibling instance's native pointer. R6 `private` is per-instance, so
# operations between two sketches (merge, set operations) read the other's
# state through its enclosing environment. Internal; never a public surface.
vo_ptr <- function(x) {
  x$.__enclos_env__$private$ptr
}

# Build a `varopt_sketch` R6 object that wraps an existing native pointer
# (the result of a set operation). Internal; never a public surface.
new_varopt_sketch <- function(ptr) {
  obj <- varopt_sketch_generator$new(k = vo_get_k_cpp(ptr))
  priv <- obj$.__enclos_env__$private
  priv$ptr <- ptr
  obj
}

# Internal R6 generator. `cloneable = FALSE` because the default shallow
# clone would copy the R6 wrapper while aliasing the same native sketch.
varopt_sketch_generator <- R6Class(
  "varopt_sketch",
  cloneable = FALSE,
  public = list(
    initialize = function(
      x = NULL,
      weight = NULL,
      k = NULL,
      type = NULL,
      bytes = NULL
    ) {
      if (!is.null(x) && !is.null(bytes)) {
        abort_invalid(
          "At most one of `x` and `bytes` may be supplied.",
          "datasketches_invalid_args"
        )
      }
      if (!is.null(bytes)) {
        if (!is.null(weight) || !is.null(k) || !is.null(type)) {
          abort_invalid(
            "`weight`, `k`, and `type` cannot be set when `bytes` is supplied; they are restored from the payload.",
            "datasketches_invalid_args"
          )
        }
        if (!is.raw(bytes)) {
          abort_invalid(
            "`bytes` must be a raw vector.",
            "datasketches_invalid_args"
          )
        }
        private$ptr <- vo_deserialize_cpp(bytes)
      } else {
        type <- if (is.null(type)) {
          if (is.character(x)) "character" else "double"
        } else {
          check_varopt_type(type)
        }
        k <- if (is.null(k)) 256L else check_varopt_k(k)
        private$ptr <- vo_create_cpp(k, type == "character")
        if (!is.null(x)) {
          self$update(x, weight)
        } else if (!is.null(weight)) {
          abort_invalid(
            "`weight` cannot be set without `x`.",
            "datasketches_invalid_args"
          )
        }
      }
      invisible(self)
    },

    # Accepts numeric or character input for `x`, depending on the item type
    # the sketch was created with; an `x` of the wrong type raises
    # `datasketches_invalid_input`. `weight` is a non-negative, finite number
    # or a vector of such values matching `length(x)`, defaulting to `1`.
    # `NA`/`NaN`/`NA_character_` in `x` are silently ignored (and the
    # corresponding `weight` dropped), matching the missing-value policy used
    # across families.
    update = function(x, weight = NULL) {
      x <- check_hashable_stream(x, "x")
      if (is.character(x) != self$is_character()) {
        abort_invalid(
          sprintf(
            "`x` must be %s, matching the item type this sketch was created with.",
            if (self$is_character()) "character" else "numeric"
          ),
          "datasketches_invalid_input"
        )
      }
      weight <- if (is.null(weight)) {
        rep(1, length(x))
      } else {
        check_varopt_weight(weight, length(x))
      }
      if (length(weight) == 1L) {
        weight <- rep(weight, length(x))
      }
      keep <- !is.na(x)
      x <- x[keep]
      weight <- weight[keep]
      if (length(x) > 0L) {
        if (is.character(x)) {
          vo_update_strings_cpp(private$ptr, x, weight)
        } else {
          vo_update_doubles_cpp(private$ptr, x, weight)
        }
      }
      invisible(self)
    },

    # Mutating merge. VarOpt has no direct merge(); internally this feeds both
    # sketches into a union sized for the larger configured `k`, and replaces
    # this sketch's state with the union result. Both sketches must hold the
    # same item type; self-merge is rejected for consistency with other
    # families.
    merge = function(other) {
      check_varopt(other, "other")
      if (identical(private$ptr, vo_ptr(other))) {
        abort_invalid(
          "A sketch cannot be merged into itself.",
          "datasketches_self_merge"
        )
      }
      if (!identical(self$is_character(), other$is_character())) {
        abort_invalid(
          "Cannot merge VarOpt sketches with different item types.",
          "datasketches_incompatible_sketch"
        )
      }
      max_k <- max(self$k(), other$k())
      vo_merge_cpp(private$ptr, vo_ptr(other), max_k)
      invisible(self)
    },

    # Configured maximum sample size.
    k = function() {
      vo_get_k_cpp(private$ptr)
    },

    # Total number of items processed so far.
    n = function() {
      vo_get_n_cpp(private$ptr)
    },

    # Number of items currently retained in the sketch.
    num_samples = function() {
      vo_get_num_samples_cpp(private$ptr)
    },

    is_empty = function() {
      vo_is_empty_cpp(private$ptr)
    },

    # `TRUE` if this sketch holds character items, `FALSE` if it holds
    # numeric items. Fixed at construction (or restored from `bytes`).
    is_character = function() {
      vo_is_string_cpp(private$ptr)
    },

    # A data frame with one row per retained sample: `item` (numeric or
    # character, matching `is_character()`) and `weight` (its estimated
    # weight in the full stream).
    samples = function() {
      rows <- if (self$is_character()) {
        vo_samples_strings_cpp(private$ptr)
      } else {
        vo_samples_doubles_cpp(private$ptr)
      }
      data.frame(
        item = rows$item,
        weight = rows$weight,
        stringsAsFactors = FALSE
      )
    },

    # Estimated subset sum of item weights over the full stream, for items
    # matching `predicate`, a function taking one item (numeric or character)
    # and returning a single logical. Returns a named list with
    # `lower_bound`, `estimate`, `upper_bound`, and `total_weight` (the
    # estimated total weight of the full stream). When the sketch holds the
    # entire stream (no sampling has occurred), `total_weight` instead
    # equals `estimate` (the matched-subset weight), matching the upstream
    # `subset_summary` contract.
    estimate_subset_sum = function(predicate) {
      items <- self$samples()$item
      indicator <- vapply(items, predicate, logical(1), USE.NAMES = FALSE)
      vo_estimate_subset_sum_cpp(private$ptr, indicator)
    },

    # Stable structured metadata (a plain named list).
    summary = function(...) {
      list(
        type = private$type_id,
        item_type = if (self$is_character()) "character" else "double",
        k = self$k(),
        n = self$n(),
        num_samples = self$num_samples(),
        is_empty = self$is_empty()
      )
    },

    # Concise one-line representation (same text as `as.character()`).
    format = function(...) {
      item_type <- if (self$is_character()) "character" else "double"
      if (self$is_empty()) {
        sprintf("<varopt_sketch[k=%d, %s, empty]>", self$k(), item_type)
      } else {
        sprintf(
          "<varopt_sketch[k=%d, %s, n=%s, num_samples=%d]>",
          self$k(),
          item_type,
          format(self$n(), scientific = FALSE, trim = TRUE),
          self$num_samples()
        )
      }
    },

    print = function(...) {
      cat("<varopt_sketch>\n")
      cat(sprintf("  k           : %d\n", self$k()))
      cat(sprintf(
        "  item_type   : %s\n",
        if (self$is_character()) "character" else "double"
      ))
      cat(sprintf("  n           : %s\n", format(self$n(), scientific = FALSE)))
      cat(sprintf("  num_samples : %d\n", self$num_samples()))
      cat(sprintf("  empty       : %s\n", self$is_empty()))
      invisible(self)
    },

    # Verbose upstream debug string.
    inspect = function(items = FALSE) {
      items <- check_flag(items, "items")
      cat(vo_to_string_cpp(private$ptr, items))
      invisible(self)
    },

    serialize = function() {
      vo_serialize_cpp(private$ptr)
    },

    # Stable type id for later typed persistence (write_sketch, deferred to 0.1.1).
    sketch_type = function() {
      private$type_id
    }
  ),
  private = list(
    ptr = NULL,
    type_id = "varopt"
  )
)

#' VarOpt sketch for variance-optimal sampling and subset-sum estimation
#'
#' Creates a
#' [VarOpt](https://datasketches.apache.org/docs/Sampling/VarOptSamplingSketches.html)
#' sketch, which samples up to `k` items from a stream of weighted (item,
#' weight) pairs. It is designed for minimum-variance estimation of subset
#' sums: `$estimate_subset_sum()` estimates the total weight of all stream
#' items matching a predicate, using only the retained sample.
#'
#' Unlike the hash-based cardinality and frequency sketches, VarOpt retains
#' items verbatim rather than hashing them, so the item type (numeric or
#' character) is fixed when the sketch is created and cannot change.
#'
#' At most one of `x` or `bytes` may be supplied:
#'
#' * Pass `x` to build a sketch and immediately update it with a numeric or
#'   character vector of items (optionally with `weight`). The item type is
#'   inferred from `x` unless `type` is supplied.
#' * Pass `bytes` to reconstruct a sketch from a native serialized payload (as
#'   produced by `sketch$serialize()`). `weight`, `k`, and `type` must not be
#'   supplied alongside `bytes`; they are restored from the payload.
#' * Pass neither for an empty (mutable) sketch with the given `k` and `type`.
#'
#' `update()` silently ignores `NA`/`NaN`/`NA_character_` in `x` (and the
#' corresponding `weight`), matching the missing-value policy used across
#' families; there is no `na_rm` argument.
#'
#' Two sketches can only be merged with `$merge()`, or combined with
#' `varopt_union()`, if they hold the same item type (a mismatch raises
#' `datasketches_incompatible_sketch`). Both operations resize the result for
#' the larger of the two inputs' configured `k`.
#'
#' @param x Optional numeric or character vector of items to update the new
#'   sketch with.
#' @param weight Optional weight(s) for each element of `x`: a single
#'   non-negative, finite number, or a vector of such values matching
#'   `length(x)`. Defaults to `1`. Cannot be set without `x`.
#' @param k Maximum sample size, a single whole number in `[1, 2^31 - 2]`.
#'   Defaults to `256`. Must not be set when `bytes` is supplied.
#' @param type Item type for a fresh sketch, either `"double"` or
#'   `"character"`. Defaults to the type of `x` (or `"double"` if `x` is not
#'   supplied). Must not be set when `bytes` is supplied.
#' @param bytes Optional [raw] vector holding a native serialized sketch to
#'   reconstruct.
#'
#' @return A `varopt_sketch` object. Key methods:
#'   \describe{
#'     \item{`$update(x, weight = NULL)`}{Add weighted items (mutates, returns
#'       the sketch).}
#'     \item{`$merge(other)`}{Absorb another sketch with the same item type
#'       (mutates, returns the sketch).}
#'     \item{`$samples()`}{A data frame of retained items and their estimated
#'       weights.}
#'     \item{`$estimate_subset_sum(predicate)`}{Estimated total weight of
#'       stream items matching `predicate`, with `lower_bound` and
#'       `upper_bound`.}
#'     \item{`$k()`, `$n()`, `$num_samples()`, `$is_empty()`,
#'       `$is_character()`}{Metadata accessors.}
#'     \item{`$summary()`, `$inspect()`, `$serialize()`}{Structured metadata,
#'       verbose debug output, and the native byte payload.}
#'   }
#'
#' @examples
#' items <- 1:1000
#' weights <- runif(1000)
#' sketch <- varopt(items, weights, k = 50)
#' sketch$samples()
#' sketch$estimate_subset_sum(\(x) x <= 500)
#'
#' # Round-trip through the native byte format.
#' restored <- varopt(bytes = sketch$serialize())
#' identical(restored$samples(), sketch$samples())
#'
#' @export
varopt <- function(
  x = NULL,
  weight = NULL,
  k = NULL,
  type = NULL,
  bytes = NULL
) {
  varopt_sketch_generator$new(
    x = x,
    weight = weight,
    k = k,
    type = type,
    bytes = bytes
  )
}

#' Combine two VarOpt sketches
#'
#' Combines two [varopt()] sketches into a new `varopt_sketch` result,
#' without mutating either input. `a` and `b` must hold the same item type (a
#' mismatch raises `datasketches_incompatible_sketch`). The result is sized
#' for the larger of `a` and `b`'s configured `k`.
#'
#' @param a,b `varopt_sketch` objects holding the same item type.
#'
#' @return A `varopt_sketch` object.
#'
#' @examples
#' a <- varopt(1:1000, runif(1000), k = 50)
#' b <- varopt(501:1500, runif(1000), k = 50)
#' u <- varopt_union(a, b)
#' u$k()
#' u$n()
#'
#' @export
varopt_union <- function(a, b) {
  check_varopt(a, "a")
  check_varopt(b, "b")
  if (!identical(a$is_character(), b$is_character())) {
    abort_invalid(
      "`a` and `b` must be VarOpt sketches with the same item type.",
      "datasketches_incompatible_sketch"
    )
  }
  max_k <- max(a$k(), b$k())
  ptr <- vo_union_cpp(vo_ptr(a), vo_ptr(b), max_k)
  new_varopt_sketch(ptr)
}
