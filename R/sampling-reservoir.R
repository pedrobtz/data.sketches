# EBPPS (Exact and Bounded Probabilistic Proportional-to-Size) sampling
# sketch: the R6 implementation and its exported constructor. The generator is
# internal; users go through `ebpps()`. See `_dev/WORKING-ON.md` for the
# public API contract and implementation status.
#
# EBPPS samples up to `k` items from a stream of (item, weight) pairs, with
# each item's inclusion probability proportional to its share of the total
# stream weight. It is a modern alternative to classic reservoir sampling
# (Hentschel, Haas & Tian, 2023) with a tighter bound on the sample size.
# Unlike Theta/HLL/CPC, items are retained verbatim (not hashed), so the item
# type (numeric or character) is fixed at creation. Unlike VarOpt, EBPPS
# supports a direct `merge()` with no separate union object. Native bridge
# functions live in `src/ebpps_sketch.cpp`.

# Reach a sibling instance's native pointer. R6 `private` is per-instance, so
# `merge()` reads the other sketch's state through its enclosing environment.
# Internal; never a public surface.
eb_ptr <- function(x) {
  x$.__enclos_env__$private$ptr
}

# Internal R6 generator. `cloneable = FALSE` because the default shallow
# clone would copy the R6 wrapper while aliasing the same native sketch.
ebpps_sketch_generator <- R6Class(
  "ebpps_sketch",
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
        private$ptr <- eb_deserialize_cpp(bytes)
      } else {
        type <- if (is.null(type)) {
          if (is.character(x)) "character" else "double"
        } else {
          check_ebpps_type(type)
        }
        k <- if (is.null(k)) 256L else check_ebpps_k(k)
        private$ptr <- eb_create_cpp(k, type == "character")
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
        check_ebpps_weight(weight, length(x))
      }
      if (length(weight) == 1L) {
        weight <- rep(weight, length(x))
      }
      keep <- !is.na(x)
      x <- x[keep]
      weight <- weight[keep]
      if (length(x) > 0L) {
        if (is.character(x)) {
          eb_update_strings_cpp(private$ptr, x, weight)
        } else {
          eb_update_doubles_cpp(private$ptr, x, weight)
        }
      }
      invisible(self)
    },

    # Mutating merge. Absorbs `other` into this sketch. Both sketches must
    # hold the same item type; self-merge is rejected for consistency with
    # other families. The native implementation resizes the result to
    # `min(k(), other$k())`.
    merge = function(other) {
      check_ebpps(other, "other")
      if (identical(private$ptr, eb_ptr(other))) {
        abort_invalid(
          "A sketch cannot be merged into itself.",
          "datasketches_self_merge"
        )
      }
      if (!identical(self$is_character(), other$is_character())) {
        abort_invalid(
          "Cannot merge EBPPS sketches with different item types.",
          "datasketches_incompatible_sketch"
        )
      }
      eb_merge_cpp(private$ptr, eb_ptr(other))
      invisible(self)
    },

    # Configured maximum sample size.
    k = function() {
      eb_get_k_cpp(private$ptr)
    },

    # Total number of items processed so far, regardless of weight.
    n = function() {
      eb_get_n_cpp(private$ptr)
    },

    # Cumulative weight of all items processed so far.
    cumulative_weight = function() {
      eb_get_cumulative_weight_cpp(private$ptr)
    },

    # Expected number of items returned by `$result()`: a non-negative
    # number no larger than `k()` (modulo floating-point error), whose
    # fractional part is the probability that the sample includes a
    # "partial" item.
    c = function() {
      eb_get_c_cpp(private$ptr)
    },

    is_empty = function() {
      eb_is_empty_cpp(private$ptr)
    },

    # `TRUE` if this sketch holds character items, `FALSE` if it holds
    # numeric items. Fixed at construction (or restored from `bytes`).
    is_character = function() {
      eb_is_string_cpp(private$ptr)
    },

    # The current sample: a numeric or character vector (matching
    # `is_character()`) of up to `k()` items, each retained proportional to
    # its share of the total stream weight.
    result = function() {
      if (self$is_character()) {
        eb_result_strings_cpp(private$ptr)
      } else {
        eb_result_doubles_cpp(private$ptr)
      }
    },

    # Stable structured metadata (a plain named list).
    summary = function(...) {
      list(
        type = private$type_id,
        item_type = if (self$is_character()) "character" else "double",
        k = self$k(),
        n = self$n(),
        cumulative_weight = self$cumulative_weight(),
        c = self$c(),
        is_empty = self$is_empty()
      )
    },

    # Concise one-line representation (same text as `as.character()`).
    format = function(...) {
      item_type <- if (self$is_character()) "character" else "double"
      if (self$is_empty()) {
        sprintf("<ebpps_sketch[k=%d, %s, empty]>", self$k(), item_type)
      } else {
        sprintf(
          "<ebpps_sketch[k=%d, %s, n=%s, c=%s]>",
          self$k(),
          item_type,
          format(self$n(), scientific = FALSE, trim = TRUE),
          format(self$c(), digits = 3, trim = TRUE)
        )
      }
    },

    print = function(...) {
      cat("<ebpps_sketch>\n")
      cat(sprintf("  k                 : %d\n", self$k()))
      cat(sprintf(
        "  item_type         : %s\n",
        if (self$is_character()) "character" else "double"
      ))
      cat(sprintf(
        "  n                 : %s\n",
        format(self$n(), scientific = FALSE)
      ))
      cat(sprintf(
        "  cumulative_weight : %s\n",
        format(self$cumulative_weight())
      ))
      cat(sprintf("  c                 : %s\n", format(self$c())))
      cat(sprintf("  empty             : %s\n", self$is_empty()))
      invisible(self)
    },

    # Verbose upstream debug string.
    inspect = function(items = FALSE) {
      items <- check_flag(items, "items")
      cat(eb_to_string_cpp(private$ptr, items))
      invisible(self)
    },

    serialize = function() {
      eb_serialize_cpp(private$ptr)
    },

    # Stable type id for later typed persistence (write_sketch, deferred to 0.1.1).
    sketch_type = function() {
      private$type_id
    }
  ),
  private = list(
    ptr = NULL,
    type_id = "ebpps"
  )
)

#' EBPPS sketch for proportional-to-size sampling
#'
#' Creates an
#' [EBPPS](https://datasketches.apache.org/docs/Sampling/EB-PPS_SamplingSketches.html)
#' (Exact and Bounded Probabilistic Proportional-to-Size) sketch, which
#' samples up to `k` items from a stream of weighted (item, weight) pairs. It
#' is a modern alternative to classic reservoir sampling: each item's
#' inclusion probability is proportional to its share of the total stream
#' weight, with a tight bound on the resulting sample size.
#'
#' Unlike the hash-based cardinality and frequency sketches, EBPPS retains
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
#' Two sketches can only be merged with `$merge()` if they hold the same item
#' type (a mismatch raises `datasketches_incompatible_sketch`). The merged
#' sketch is resized to the smaller of the two inputs' configured `k`,
#' matching the native implementation.
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
#' @return An `ebpps_sketch` object. Key methods:
#'   \describe{
#'     \item{`$update(x, weight = NULL)`}{Add weighted items (mutates, returns
#'       the sketch).}
#'     \item{`$merge(other)`}{Absorb another sketch with the same item type
#'       (mutates, returns the sketch).}
#'     \item{`$result()`}{The current sample as a numeric or character
#'       vector.}
#'     \item{`$k()`, `$n()`, `$cumulative_weight()`, `$c()`, `$is_empty()`,
#'       `$is_character()`}{Metadata accessors.}
#'     \item{`$summary()`, `$inspect()`, `$serialize()`}{Structured metadata,
#'       verbose debug output, and the native byte payload.}
#'   }
#'
#' @examples
#' items <- 1:1000
#' weights <- runif(1000)
#' sketch <- ebpps(items, weights, k = 50)
#' sketch$result()
#' sketch$c()
#'
#' # Round-trip through the native byte format.
#' restored <- ebpps(bytes = sketch$serialize())
#' restored$k()
#'
#' @export
ebpps <- function(
  x = NULL,
  weight = NULL,
  k = NULL,
  type = NULL,
  bytes = NULL
) {
  ebpps_sketch_generator$new(
    x = x,
    weight = weight,
    k = k,
    type = type,
    bytes = bytes
  )
}
