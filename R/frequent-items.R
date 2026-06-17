# Frequent Items sketch: the R6 implementation and its exported constructor.
# The generator is internal; users go through `frequent_items()`. See
# `_dev/WORKING-ON.md` for the public API contract and implementation status.
#
# Unlike the cardinality families, Frequent Items tracks character items with
# associated weights (frequency counts) and has a direct native `merge()`.
# Native bridge functions live in `src/frequent_items_sketch.cpp`.

# Reach a sibling instance's native pointer. R6 `private` is per-instance, so
# `merge()` reads the other's state through its enclosing environment.
# Internal; never a public surface.
fi_ptr <- function(x) {
  x$.__enclos_env__$private$ptr
}

# Internal R6 generator. `cloneable = FALSE` because the default shallow clone
# would copy the R6 wrapper while aliasing the same native sketch.
frequent_items_sketch_generator <- R6Class(
  "frequent_items_sketch",
  cloneable = FALSE,
  public = list(
    initialize = function(
      x = NULL,
      weight = NULL,
      lg_max_map_size = NULL,
      lg_start_map_size = NULL,
      bytes = NULL
    ) {
      if (!is.null(x) && !is.null(bytes)) {
        abort_invalid(
          "At most one of `x` and `bytes` may be supplied.",
          "datasketches_invalid_args"
        )
      }
      if (!is.null(bytes)) {
        if (!is.null(lg_max_map_size) || !is.null(lg_start_map_size)) {
          abort_invalid(
            "`lg_max_map_size` and `lg_start_map_size` cannot be set when `bytes` is supplied; they are restored from the payload.",
            "datasketches_invalid_args"
          )
        }
        if (!is.raw(bytes)) {
          abort_invalid(
            "`bytes` must be a raw vector.",
            "datasketches_invalid_args"
          )
        }
        private$ptr <- fi_deserialize_cpp(bytes)
      } else {
        lg_max_map_size <- if (is.null(lg_max_map_size)) {
          8L
        } else {
          check_lg_max_map_size(lg_max_map_size)
        }
        lg_start_map_size <- if (is.null(lg_start_map_size)) {
          3L
        } else {
          check_lg_start_map_size(lg_start_map_size, lg_max_map_size)
        }
        private$ptr <- fi_create_cpp(lg_max_map_size, lg_start_map_size)
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

    # Accepts a character vector of items. `weight` is a positive whole
    # number, either a single value (recycled) or a vector matching the
    # length of `x`; it defaults to `1` (each occurrence counts once).
    # `NA_character_` is silently ignored, matching the missing-value policy
    # used across families.
    update = function(x, weight = NULL) {
      if (!is.character(x)) {
        abort_invalid(
          "`x` must be a character vector.",
          "datasketches_invalid_input"
        )
      }
      weight <- if (is.null(weight)) 1 else check_weight(weight, length(x))
      if (length(weight) > 1L && length(weight) != length(x)) {
        abort_invalid(
          "`weight` must be a single value or a vector matching the length of `x`.",
          "datasketches_invalid_weight"
        )
      }
      keep <- !is.na(x)
      if (length(weight) > 1L) {
        weight <- weight[keep]
      }
      x <- x[keep]
      if (length(x) > 0L) {
        fi_update_cpp(private$ptr, x, weight)
      }
      invisible(self)
    },

    # Mutating merge. Frequent Items has a direct native merge(); the other
    # sketch may have been built with a different `lg_max_map_size`.
    # Self-merge is rejected for consistency with other families.
    merge = function(other) {
      check_frequent_items(other, "other")
      if (identical(private$ptr, fi_ptr(other))) {
        abort_invalid(
          "A sketch cannot be merged into itself.",
          "datasketches_self_merge"
        )
      }
      fi_merge_cpp(private$ptr, fi_ptr(other))
      invisible(self)
    },

    # Estimated frequency (weight) of `item`, vectorized over a character
    # vector.
    estimate = function(item) {
      item <- check_item(item)
      fi_get_estimate_cpp(private$ptr, item)
    },

    # Guaranteed lower/upper bound on the frequency of `item`, vectorized
    # over a character vector.
    lower_bound = function(item) {
      item <- check_item(item)
      fi_get_lower_bound_cpp(private$ptr, item)
    },

    upper_bound = function(item) {
      item <- check_item(item)
      fi_get_upper_bound_cpp(private$ptr, item)
    },

    # Upper bound on the maximum error of `$estimate()` for any item.
    maximum_error = function() {
      fi_get_maximum_error_cpp(private$ptr)
    },

    # `3.5 / max_map_size`: the error bound used by the sketch.
    epsilon = function() {
      fi_get_epsilon_cpp(private$ptr)
    },

    # Sum of all weights (occurrences) seen so far.
    total_weight = function() {
      fi_get_total_weight_cpp(private$ptr)
    },

    num_active_items = function() {
      fi_get_num_active_items_cpp(private$ptr)
    },

    is_empty = function() {
      fi_is_empty_cpp(private$ptr)
    },

    # Items whose estimated frequency exceeds `threshold` (defaults to
    # `$maximum_error()`), as a data frame with columns `item`, `estimate`,
    # `lower_bound`, and `upper_bound`.
    #
    # If `error_type = "no_false_positives"` (the default), every returned
    # item is guaranteed to truly exceed the threshold, but some items that
    # truly exceed it may be omitted. If `error_type = "no_false_negatives"`,
    # every item that truly exceeds the threshold is guaranteed to be
    # returned, but some returned items may not truly exceed it.
    frequent_items = function(
      error_type = "no_false_positives",
      threshold = NULL
    ) {
      error_type <- check_fi_error_type(error_type)
      threshold <- if (is.null(threshold)) {
        NA_real_
      } else {
        check_weight(threshold, 1L)
      }
      rows <- fi_get_frequent_items_cpp(private$ptr, error_type, threshold)
      as.data.frame(rows, stringsAsFactors = FALSE)
    },

    # Stable structured metadata (a plain named list).
    summary = function(...) {
      list(
        type = private$type_id,
        is_empty = self$is_empty(),
        num_active_items = self$num_active_items(),
        total_weight = self$total_weight(),
        maximum_error = self$maximum_error(),
        epsilon = self$epsilon()
      )
    },

    # Concise one-line representation (same text as `as.character()`).
    format = function(...) {
      if (self$is_empty()) {
        "<frequent_items_sketch[empty]>"
      } else {
        sprintf(
          "<frequent_items_sketch[num_active_items=%d, total_weight=%s]>",
          self$num_active_items(),
          format(self$total_weight(), scientific = FALSE, trim = TRUE)
        )
      }
    },

    print = function(...) {
      empty <- self$is_empty()
      cat("<frequent_items_sketch>\n")
      cat(sprintf("  empty            : %s\n", empty))
      if (!empty) {
        cat(sprintf("  num_active_items : %d\n", self$num_active_items()))
        cat(sprintf(
          "  total_weight     : %s\n",
          format(self$total_weight(), scientific = FALSE, trim = TRUE)
        ))
        cat(sprintf(
          "  maximum_error    : %s\n",
          format(self$maximum_error(), scientific = FALSE, trim = TRUE)
        ))
      }
      invisible(self)
    },

    # Verbose upstream debug string.
    inspect = function(detail = FALSE) {
      detail <- check_flag(detail, "detail")
      cat(fi_to_string_cpp(private$ptr, detail))
      invisible(self)
    },

    serialize = function() {
      fi_serialize_cpp(private$ptr)
    },

    # Stable type id for later typed persistence (write_sketch, deferred to 0.1.1).
    sketch_type = function() {
      private$type_id
    }
  ),
  private = list(
    ptr = NULL,
    type_id = "frequent_items"
  )
)

# A character vector of items for `$estimate()`/`$lower_bound()`/`$upper_bound()`.
check_item <- function(item, call = rlang::caller_env()) {
  if (!is.character(item)) {
    abort_invalid(
      "`item` must be a character vector.",
      "datasketches_invalid_input",
      call = call
    )
  }
  item
}

#' Frequent Items sketch for approximate frequency estimation
#'
#' Creates a [Frequent Items](https://datasketches.apache.org/docs/Frequency/FrequencySketches.html)
#' sketch, a mergeable summary that estimates the frequencies of the most
#' frequent items in a character stream far larger than memory, with
#' guaranteed error bounds.
#'
#' At most one of `x` or `bytes` may be supplied:
#'
#' * Pass `x` to build a sketch and immediately update it with a character
#'   vector (optionally with `weight`).
#' * Pass `bytes` to reconstruct a sketch from a native serialized payload (as
#'   produced by `sketch$serialize()`). `lg_max_map_size` and
#'   `lg_start_map_size` are restored from the payload and must not be
#'   supplied alongside `bytes`.
#' * Pass neither for an empty sketch with the given `lg_max_map_size` and
#'   `lg_start_map_size`.
#'
#' `NA_character_` is silently ignored by `update()`, matching the
#' missing-value policy used across families; there is no `na_rm` argument.
#'
#' @param x Optional character vector to update the new sketch with.
#' @param weight Optional weight(s) for `x`: a single non-negative whole
#'   number (recycled), or a vector of such values matching the length of
#'   `x`. Defaults to `1` (each occurrence counts once). Cannot be set without
#'   `x`.
#' @param lg_max_map_size log2 of the maximum size of the internal hash map, a
#'   single whole number in `[3, 30]`. Larger values are more accurate and
#'   larger. Defaults to `8`. Must not be set when `bytes` is supplied.
#' @param lg_start_map_size log2 of the starting size of the internal hash
#'   map, a single whole number in `[3, lg_max_map_size]`. Defaults to `3`.
#'   Must not be set when `bytes` is supplied.
#' @param bytes Optional [raw] vector holding a native serialized sketch to
#'   reconstruct.
#'
#' @return A `frequent_items_sketch` object. Key methods:
#'   \describe{
#'     \item{`$update(x, weight = NULL)`}{Add character values with an
#'       optional weight (mutates, returns the sketch).}
#'     \item{`$merge(other)`}{Absorb another sketch (mutates, returns the
#'       sketch).}
#'     \item{`$estimate(item)`, `$lower_bound(item)`, `$upper_bound(item)`}{
#'       Estimated frequency and guaranteed bounds for one or more items.}
#'     \item{`$frequent_items(error_type = "no_false_positives", threshold = NULL)`}{
#'       A data frame of items whose estimated frequency exceeds `threshold`
#'       (defaults to `$maximum_error()`), with columns `item`, `estimate`,
#'       `lower_bound`, and `upper_bound`.}
#'     \item{`$maximum_error()`, `$epsilon()`, `$total_weight()`,
#'       `$num_active_items()`, `$is_empty()`}{Metadata accessors.}
#'     \item{`$summary()`, `$inspect()`, `$serialize()`}{Structured metadata,
#'       verbose debug output, and the native byte payload.}
#'   }
#'
#' @examples
#' words <- sample(letters[1:5], 1000, replace = TRUE, prob = c(.5, .25, .1, .1, .05))
#' sketch <- frequent_items(words)
#' sketch$frequent_items()
#' sketch$estimate("a")
#'
#' # Round-trip through the native byte format.
#' restored <- frequent_items(bytes = sketch$serialize())
#' identical(restored$total_weight(), sketch$total_weight())
#'
#' @export
frequent_items <- function(
  x = NULL,
  weight = NULL,
  lg_max_map_size = NULL,
  lg_start_map_size = NULL,
  bytes = NULL
) {
  frequent_items_sketch_generator$new(
    x = x,
    weight = weight,
    lg_max_map_size = lg_max_map_size,
    lg_start_map_size = lg_start_map_size,
    bytes = bytes
  )
}
