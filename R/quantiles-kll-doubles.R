# KLL doubles quantile sketch: the R6 implementation and its exported
# constructor. The generator is internal; users go through `kll_doubles()`.
# See `_dev/WORKING-ON.md` for the public API contract and implementation status.
# Native bridge functions live in `src/kll_doubles.cpp`.

# Reach a sibling instance's native pointer. R6 `private` is per-instance, so
# operations between two sketches (merge) read the other's pointer through its
# enclosing environment. Internal; the raw pointer is never a public surface.
kll_doubles_ptr <- function(x) {
  x$.__enclos_env__$private$ptr
}

# Internal R6 generator. `cloneable = FALSE` because the default shallow clone
# would copy the R6 wrapper while aliasing the same native sketch.
kll_doubles_sketch_generator <- R6Class(
  "kll_doubles_sketch",
  cloneable = FALSE,
  public = list(
    initialize = function(x = NULL, k = NULL, bytes = NULL) {
      if (!is.null(x) && !is.null(bytes)) {
        abort_invalid(
          "At most one of `x` and `bytes` may be supplied.",
          "datasketches_invalid_args"
        )
      }
      if (!is.null(bytes)) {
        if (!is.null(k)) {
          abort_invalid(
            "`k` cannot be set when `bytes` is supplied; the width is restored from the payload.",
            "datasketches_invalid_args"
          )
        }
        if (!is.raw(bytes)) {
          abort_invalid(
            "`bytes` must be a raw vector.",
            "datasketches_invalid_args"
          )
        }
        private$ptr <- kll_doubles_deserialize_cpp(bytes)
      } else {
        k <- if (is.null(k)) 200L else check_k(k)
        private$ptr <- kll_doubles_create_cpp(k)
        if (!is.null(x)) {
          self$update(x)
        }
      }
      invisible(self)
    },

    update = function(x) {
      x <- check_numeric_stream(x, "x")
      kll_doubles_update_cpp(private$ptr, x)
      invisible(self)
    },

    # Mutating merge. Self-merge is undefined behaviour in the vendored C++
    # (no aliasing guard), so reject an identical pointer before the native call.
    merge = function(other) {
      check_kll_doubles(other, "other")
      if (identical(private$ptr, kll_doubles_ptr(other))) {
        abort_invalid(
          "A sketch cannot be merged into itself.",
          "datasketches_self_merge"
        )
      }
      kll_doubles_merge_cpp(private$ptr, kll_doubles_ptr(other))
      invisible(self)
    },

    quantile = function(probs, inclusive = TRUE) {
      probs <- check_probs(probs)
      inclusive <- check_flag(inclusive, "inclusive")
      kll_doubles_get_quantiles_cpp(private$ptr, probs, inclusive)
    },

    # `rank` treats input as data values: missing inputs map to NA_real_ in the
    # shape-preserving output rather than querying the sketch.
    rank = function(x, inclusive = TRUE) {
      x <- check_numeric_stream(x, "x")
      inclusive <- check_flag(inclusive, "inclusive")
      out <- rep(NA_real_, length(x))
      ok <- !is.na(x)
      if (any(ok)) {
        out[ok] <- kll_doubles_get_ranks_cpp(private$ptr, x[ok], inclusive)
      }
      out
    },

    # `cdf`/`pmf` are NOT length-preserving: n split points produce n + 1 values.
    cdf = function(split_points, inclusive = TRUE) {
      split_points <- check_split_points(split_points)
      inclusive <- check_flag(inclusive, "inclusive")
      kll_doubles_get_cdf_cpp(private$ptr, split_points, inclusive)
    },

    pmf = function(split_points, inclusive = TRUE) {
      split_points <- check_split_points(split_points)
      inclusive <- check_flag(inclusive, "inclusive")
      kll_doubles_get_pmf_cpp(private$ptr, split_points, inclusive)
    },

    n = function() {
      kll_doubles_get_n_cpp(private$ptr)
    },

    k = function() {
      kll_doubles_get_k_cpp(private$ptr)
    },

    num_retained = function() {
      kll_doubles_get_num_retained_cpp(private$ptr)
    },

    is_empty = function() {
      kll_doubles_is_empty_cpp(private$ptr)
    },

    is_estimation_mode = function() {
      kll_doubles_is_estimation_mode_cpp(private$ptr)
    },

    min = function() {
      kll_doubles_get_min_item_cpp(private$ptr)
    },

    max = function() {
      kll_doubles_get_max_item_cpp(private$ptr)
    },

    # Routes through the instance bridge so the error reflects the sketch's
    # effective k (min_k_ after a mixed-k merge), not the configured k.
    rank_error = function(pmf = FALSE) {
      pmf <- check_flag(pmf, "pmf")
      kll_doubles_rank_error_cpp(private$ptr, pmf)
    },

    # Stable structured metadata (a plain named list). min/max are NA on an empty
    # sketch rather than raising, so `summary()` is always safe to call.
    summary = function(...) {
      empty <- self$is_empty()
      list(
        type = private$type_id,
        n = self$n(),
        k = self$k(),
        num_retained = self$num_retained(),
        is_empty = empty,
        is_estimation_mode = self$is_estimation_mode(),
        min = if (empty) NA_real_ else self$min(),
        max = if (empty) NA_real_ else self$max(),
        rank_error = self$rank_error()
      )
    },

    # Concise one-line representation (same text as `as.character()`).
    format = function(...) {
      mode <- if (self$is_estimation_mode()) ", estimation" else ""
      sprintf(
        "<kll_doubles_sketch[n=%s, k=%d%s]>",
        format(self$n(), scientific = FALSE, trim = TRUE),
        self$k(),
        mode
      )
    },

    print = function(...) {
      empty <- self$is_empty()
      cat("<kll_doubles_sketch>\n")
      cat(sprintf(
        "  n          : %s\n",
        format(self$n(), scientific = FALSE, trim = TRUE)
      ))
      cat(sprintf("  k          : %d\n", self$k()))
      cat(sprintf(
        "  retained   : %s\n",
        format(self$num_retained(), scientific = FALSE, trim = TRUE)
      ))
      cat(sprintf("  estimation : %s\n", self$is_estimation_mode()))
      if (empty) {
        cat("  min / max  : <empty>\n")
      } else {
        cat(sprintf("  min / max  : %s / %s\n", self$min(), self$max()))
      }
      cat(sprintf("  rank error : %s\n", signif(self$rank_error(), 3)))
      invisible(self)
    },

    # Verbose upstream debug string (KLL levels and, optionally, retained items).
    inspect = function(levels = TRUE, items = FALSE) {
      levels <- check_flag(levels, "levels")
      items <- check_flag(items, "items")
      cat(kll_doubles_to_string_cpp(private$ptr, levels, items))
      invisible(self)
    },

    serialize = function() {
      kll_doubles_serialize_cpp(private$ptr)
    },

    # Stable type id for later typed persistence (write_sketch, deferred to 0.1.1).
    sketch_type = function() {
      private$type_id
    }
  ),
  private = list(
    ptr = NULL,
    type_id = "kll_doubles"
  )
)

#' KLL sketch for approximate quantiles of a numeric stream
#'
#' Creates a [KLL](https://datasketches.apache.org/docs/KLL/KLLSketch.html)
#' quantile sketch over `double` values. A KLL sketch is a compact, mergeable
#' summary that answers approximate quantile, rank, CDF, and PMF queries over a
#' stream far larger than memory, with a configurable accuracy/size trade-off
#' controlled by `k`.
#'
#' At most one of `x` or `bytes` may be supplied:
#'
#' * Pass `x` to build a sketch and immediately update it with a numeric vector.
#' * Pass `bytes` to reconstruct a sketch from a native serialized payload (as
#'   produced by `sketch$serialize()`). The width is restored from the payload,
#'   so `k` must not be supplied alongside `bytes`.
#' * Pass neither for an empty sketch of width `k`.
#'
#' `update()` silently ignores `NA`/`NaN`, matching the upstream/Python behaviour;
#' there is no `na_rm` argument.
#'
#' @param x Optional numeric vector to update the new sketch with.
#' @param k Sketch width controlling the accuracy/size trade-off, a whole number
#'   in `[8, 65535]`. Larger `k` is more accurate and larger. Defaults to `200`
#'   (resolved when a fresh sketch is built). Must not be set when `bytes` is
#'   supplied.
#' @param bytes Optional [raw] vector holding a native serialized sketch to
#'   reconstruct.
#'
#' @return A `kll_doubles_sketch` object. Key methods:
#'   \describe{
#'     \item{`$update(x)`}{Add numeric values (mutates, returns the sketch).}
#'     \item{`$merge(other)`}{Absorb another sketch (mutates, returns the sketch).}
#'     \item{`$quantile(probs, inclusive = TRUE)`}{Approximate quantiles for
#'       probabilities in `[0, 1]`.}
#'     \item{`$rank(x, inclusive = TRUE)`}{Approximate ranks of `x`; missing
#'       inputs return `NA`.}
#'     \item{`$cdf(split_points)` / `$pmf(split_points)`}{Cumulative / mass
#'       estimates; return `length(split_points) + 1` values.}
#'     \item{`$n()`, `$k()`, `$num_retained()`, `$is_empty()`,
#'       `$is_estimation_mode()`, `$min()`, `$max()`, `$rank_error(pmf = FALSE)`}{
#'       Metadata and accuracy accessors.}
#'     \item{`$summary()`, `$inspect()`, `$serialize()`}{Structured metadata,
#'       verbose debug output, and the native byte payload.}
#'   }
#'
#' @examples
#' sketch <- kll_doubles(rnorm(10000))
#' sketch$quantile(c(0.25, 0.5, 0.75))
#' sketch$rank(c(-1, 0, 1))
#'
#' # Round-trip through the native byte format.
#' restored <- kll_doubles(bytes = sketch$serialize())
#' identical(restored$quantile(0.5), sketch$quantile(0.5))
#'
#' @export
kll_doubles <- function(x = NULL, k = NULL, bytes = NULL) {
  kll_doubles_sketch_generator$new(x = x, k = k, bytes = bytes)
}
