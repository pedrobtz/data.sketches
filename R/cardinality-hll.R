# HLL (HyperLogLog) sketch: the R6 implementation and its exported
# constructor. The generator is internal; users go through `hll()`. See
# `_dev/WORKING-ON.md` for the public API contract and implementation status.
# Unlike the quantile sketches, HLL has no direct `merge()`; two sketches are
# combined via an internal union (see `hll_merge_cpp` in
# `src/hll_sketch.cpp`). HLL also accepts both numeric and character streams,
# hashing each element to estimate the number of distinct values.
# Native bridge functions live in `src/hll_sketch.cpp`.

# Reach a sibling instance's native pointer. R6 `private` is per-instance, so
# operations between two sketches (merge) read the other's pointer through its
# enclosing environment. Internal; the raw pointer is never a public surface.
hll_ptr <- function(x) {
  x$.__enclos_env__$private$ptr
}

# Internal R6 generator. `cloneable = FALSE` because the default shallow clone
# would copy the R6 wrapper while aliasing the same native sketch.
hll_sketch_generator <- R6Class(
  "hll_sketch",
  cloneable = FALSE,
  public = list(
    initialize = function(x = NULL, lg_k = NULL, type = NULL, bytes = NULL) {
      if (!is.null(x) && !is.null(bytes)) {
        abort_invalid(
          "At most one of `x` and `bytes` may be supplied.",
          "datasketches_invalid_args"
        )
      }
      if (!is.null(bytes)) {
        if (!is.null(lg_k)) {
          abort_invalid(
            "`lg_k` cannot be set when `bytes` is supplied; the configuration is restored from the payload.",
            "datasketches_invalid_args"
          )
        }
        if (!is.null(type)) {
          abort_invalid(
            "`type` cannot be set when `bytes` is supplied; it is restored from the payload.",
            "datasketches_invalid_args"
          )
        }
        if (!is.raw(bytes)) {
          abort_invalid(
            "`bytes` must be a raw vector.",
            "datasketches_invalid_args"
          )
        }
        if (length(bytes) < 8L) {
          abort_invalid(
            "`bytes` must be at least 8 bytes to be a valid HLL sketch payload.",
            "datasketches_invalid_args"
          )
        }
        private$ptr <- hll_deserialize_cpp(bytes)
      } else {
        lg_k <- if (is.null(lg_k)) 12L else check_lg_k(lg_k)
        type_int <- if (is.null(type)) 0L else check_hll_type(type)
        private$ptr <- hll_create_cpp(lg_k, type_int)
        if (!is.null(x)) {
          self$update(x)
        }
      }
      invisible(self)
    },

    # Accepts numeric or character input; each element is hashed to estimate
    # distinct-value cardinality. `NA`/`NaN`/`NA_character_` are silently
    # ignored, matching the missing-value policy used across families.
    update = function(x) {
      x <- check_hashable_stream(x, "x")
      x <- x[!is.na(x)]
      if (is.character(x)) {
        hll_update_strings_cpp(private$ptr, x)
      } else {
        hll_update_doubles_cpp(private$ptr, x)
      }
      invisible(self)
    },

    # Mutating merge. HLL has no native merge(); internally this feeds both
    # sketches into a union sized for the larger `lg_k` and replaces this
    # sketch's state with the union result. Self-merge is rejected for
    # consistency with other families, even though it would be idempotent here.
    merge = function(other) {
      check_hll(other, "other")
      if (identical(private$ptr, hll_ptr(other))) {
        abort_invalid(
          "A sketch cannot be merged into itself.",
          "datasketches_self_merge"
        )
      }
      hll_merge_cpp(private$ptr, hll_ptr(other))
      invisible(self)
    },

    # Approximate count of distinct values seen so far.
    estimate = function() {
      hll_get_estimate_cpp(private$ptr)
    },

    # Approximate confidence interval around `estimate()`, at 1, 2, or 3
    # standard deviations.
    lower_bound = function(num_std_dev = 1) {
      num_std_dev <- check_num_std_dev(num_std_dev)
      hll_get_lower_bound_cpp(private$ptr, num_std_dev)
    },

    upper_bound = function(num_std_dev = 1) {
      num_std_dev <- check_num_std_dev(num_std_dev)
      hll_get_upper_bound_cpp(private$ptr, num_std_dev)
    },

    # log2 of the number of buckets configured for this sketch.
    lg_k = function() {
      hll_get_lg_config_k_cpp(private$ptr)
    },

    # `"HLL_4"`, `"HLL_6"`, or `"HLL_8"`, the per-bucket encoding width.
    hll_type = function() {
      c("HLL_4", "HLL_6", "HLL_8")[hll_get_target_type_cpp(private$ptr) + 1L]
    },

    is_empty = function() {
      hll_is_empty_cpp(private$ptr)
    },

    # Whether the sketch is in its compact (read-only, serialize-ready) form.
    is_compact = function() {
      hll_is_compact_cpp(private$ptr)
    },

    # Stable structured metadata (a plain named list).
    summary = function(...) {
      list(
        type = private$type_id,
        lg_k = self$lg_k(),
        hll_type = self$hll_type(),
        is_empty = self$is_empty(),
        is_compact = self$is_compact(),
        estimate = self$estimate(),
        lower_bound = self$lower_bound(),
        upper_bound = self$upper_bound()
      )
    },

    # Concise one-line representation (same text as `as.character()`).
    format = function(...) {
      if (self$is_empty()) {
        sprintf(
          "<hll_sketch[lg_k=%d, type=%s, empty]>",
          self$lg_k(),
          self$hll_type()
        )
      } else {
        sprintf(
          "<hll_sketch[lg_k=%d, type=%s, estimate=%s]>",
          self$lg_k(),
          self$hll_type(),
          format(self$estimate(), scientific = FALSE, trim = TRUE, digits = 6)
        )
      }
    },

    print = function(...) {
      empty <- self$is_empty()
      cat("<hll_sketch>\n")
      cat(sprintf("  lg_k     : %d\n", self$lg_k()))
      cat(sprintf("  type     : %s\n", self$hll_type()))
      cat(sprintf("  empty    : %s\n", empty))
      if (empty) {
        cat("  estimate : <empty>\n")
      } else {
        cat(sprintf("  estimate : %s\n", self$estimate()))
        cat(sprintf(
          "  bounds   : [%s, %s] (1 std dev)\n",
          self$lower_bound(),
          self$upper_bound()
        ))
      }
      invisible(self)
    },

    # Verbose upstream debug string.
    inspect = function(detail = FALSE) {
      detail <- check_flag(detail, "detail")
      cat(hll_to_string_cpp(private$ptr, TRUE, detail, detail, FALSE))
      invisible(self)
    },

    serialize = function() {
      hll_serialize_cpp(private$ptr)
    },

    # Stable type id for later typed persistence (write_sketch, deferred to 0.1.1).
    sketch_type = function() {
      private$type_id
    }
  ),
  private = list(
    ptr = NULL,
    type_id = "hll"
  )
)

#' HLL sketch for approximate distinct counting
#'
#' Creates an [HLL](https://datasketches.apache.org/docs/HLL/HllSketches.html)
#' (HyperLogLog) sketch, a compact, mergeable summary that estimates the
#' number of distinct values seen in a stream far larger than memory.
#'
#' At most one of `x` or `bytes` may be supplied:
#'
#' * Pass `x` to build a sketch and immediately update it with a numeric or
#'   character vector.
#' * Pass `bytes` to reconstruct a sketch from a native serialized payload (as
#'   produced by `sketch$serialize()`). Configuration is restored from the
#'   payload, so `lg_k` and `type` must not be supplied alongside `bytes`.
#' * Pass neither for an empty sketch with the given `lg_k` and `type`.
#'
#' `update()` silently ignores `NA`/`NaN`/`NA_character_`, matching the
#' missing-value policy used across families; there is no `na_rm` argument.
#'
#' @param x Optional numeric or character vector to update the new sketch
#'   with. Each element is hashed and contributes to the distinct-count
#'   estimate.
#' @param lg_k log2 of the number of buckets, a single whole number in
#'   `[4, 21]`. Larger `lg_k` is more accurate and larger. Defaults to `12`
#'   (resolved when a fresh sketch is built). Must not be set when `bytes` is
#'   supplied.
#' @param type One of `"HLL_4"`, `"HLL_6"`, or `"HLL_8"`, controlling the
#'   per-bucket encoding width (a size/speed trade-off that does not affect
#'   accuracy). Defaults to `"HLL_4"` (resolved when a fresh sketch is built).
#'   Must not be set when `bytes` is supplied.
#' @param bytes Optional [raw] vector holding a native serialized sketch to
#'   reconstruct.
#'
#' @return An `hll_sketch` object. Key methods:
#'   \describe{
#'     \item{`$update(x)`}{Add numeric or character values (mutates, returns
#'       the sketch).}
#'     \item{`$merge(other)`}{Absorb another sketch (mutates, returns the
#'       sketch).}
#'     \item{`$estimate()`}{Approximate number of distinct values seen.}
#'     \item{`$lower_bound(num_std_dev = 1)` / `$upper_bound(num_std_dev = 1)`}{
#'       Approximate confidence bounds on `estimate()`, at 1, 2, or 3 standard
#'       deviations.}
#'     \item{`$lg_k()`, `$hll_type()`, `$is_empty()`, `$is_compact()`}{
#'       Metadata accessors.}
#'     \item{`$summary()`, `$inspect()`, `$serialize()`}{Structured metadata,
#'       verbose debug output, and the native byte payload.}
#'   }
#'
#' @examples
#' sketch <- hll(sample(1000, 5000, replace = TRUE))
#' sketch$estimate()
#' sketch$lower_bound()
#' sketch$upper_bound()
#'
#' # Round-trip through the native byte format.
#' restored <- hll(bytes = sketch$serialize())
#' identical(restored$estimate(), sketch$estimate())
#'
#' @export
hll <- function(x = NULL, lg_k = NULL, type = NULL, bytes = NULL) {
  hll_sketch_generator$new(x = x, lg_k = lg_k, type = type, bytes = bytes)
}
