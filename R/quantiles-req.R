# REQ (Relative Error Quantiles) sketch: the R6 implementation and its
# exported constructor. The generator is internal; users go through `req()`.
# See `_dev/WORKING-ON.md` for the public API contract and implementation
# status. This mirrors `R/quantiles-kll-doubles.R`, but REQ's error model is
# rank-dependent rather than a single uniform epsilon: `rank_lower_bound()`
# and `rank_upper_bound()` replace `rank_error()`, and the `hra` flag
# (high-rank accuracy) is part of the sketch configuration.
# Native bridge functions live in `src/req_sketch.cpp`.

# Reach a sibling instance's native pointer. R6 `private` is per-instance, so
# operations between two sketches (merge) read the other's pointer through its
# enclosing environment. Internal; the raw pointer is never a public surface.
req_ptr <- function(x) {
  x$.__enclos_env__$private$ptr
}

# Internal R6 generator. `cloneable = FALSE` because the default shallow clone
# would copy the R6 wrapper while aliasing the same native sketch.
req_sketch_generator <- R6Class(
  "req_sketch",
  cloneable = FALSE,
  public = list(
    initialize = function(x = NULL, k = NULL, hra = NULL, bytes = NULL) {
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
        if (!is.null(hra)) {
          abort_invalid(
            "`hra` cannot be set when `bytes` is supplied; it is restored from the payload.",
            "datasketches_invalid_args"
          )
        }
        if (!is.raw(bytes)) {
          abort_invalid(
            "`bytes` must be a raw vector.",
            "datasketches_invalid_args"
          )
        }
        private$ptr <- req_deserialize_cpp(bytes)
      } else {
        k <- if (is.null(k)) 12L else check_req_k(k)
        hra <- if (is.null(hra)) TRUE else check_flag(hra, "hra")
        private$ptr <- req_create_cpp(k, hra)
        if (!is.null(x)) {
          self$update(x)
        }
      }
      invisible(self)
    },

    update = function(x) {
      x <- check_numeric_stream(x, "x")
      req_update_cpp(private$ptr, x)
      invisible(self)
    },

    # Mutating merge. Self-merge is undefined behaviour in the vendored C++
    # (no aliasing guard), so reject an identical pointer before the native call.
    merge = function(other) {
      check_req(other, "other")
      if (identical(private$ptr, req_ptr(other))) {
        abort_invalid(
          "A sketch cannot be merged into itself.",
          "datasketches_self_merge"
        )
      }
      req_merge_cpp(private$ptr, req_ptr(other))
      invisible(self)
    },

    quantile = function(probs, inclusive = TRUE) {
      probs <- check_probs(probs)
      inclusive <- check_flag(inclusive, "inclusive")
      req_get_quantiles_cpp(private$ptr, probs, inclusive)
    },

    # `rank` treats input as data values: missing inputs map to NA_real_ in the
    # shape-preserving output rather than querying the sketch.
    rank = function(x, inclusive = TRUE) {
      x <- check_numeric_stream(x, "x")
      inclusive <- check_flag(inclusive, "inclusive")
      out <- rep(NA_real_, length(x))
      ok <- !is.na(x)
      if (any(ok)) {
        out[ok] <- req_get_ranks_cpp(private$ptr, x[ok], inclusive)
      }
      out
    },

    # `cdf`/`pmf` are NOT length-preserving: n split points produce n + 1 values.
    cdf = function(split_points, inclusive = TRUE) {
      split_points <- check_split_points(split_points)
      inclusive <- check_flag(inclusive, "inclusive")
      req_get_cdf_cpp(private$ptr, split_points, inclusive)
    },

    pmf = function(split_points, inclusive = TRUE) {
      split_points <- check_split_points(split_points)
      inclusive <- check_flag(inclusive, "inclusive")
      req_get_pmf_cpp(private$ptr, split_points, inclusive)
    },

    n = function() {
      req_get_n_cpp(private$ptr)
    },

    k = function() {
      req_get_k_cpp(private$ptr)
    },

    num_retained = function() {
      req_get_num_retained_cpp(private$ptr)
    },

    is_empty = function() {
      req_is_empty_cpp(private$ptr)
    },

    is_estimation_mode = function() {
      req_is_estimation_mode_cpp(private$ptr)
    },

    min = function() {
      req_get_min_item_cpp(private$ptr)
    },

    max = function() {
      req_get_max_item_cpp(private$ptr)
    },

    # Whether the sketch prioritizes accuracy for high ranks (near 1.0) over
    # low ranks (near 0.0). Fixed at construction time.
    is_hra = function() {
      req_is_hra_cpp(private$ptr)
    },

    # Vectorized approximate lower/upper bounds on the rank(s), at the
    # requested standard-deviation confidence (1, 2, or 3).
    rank_lower_bound = function(probs, num_std_dev = 1) {
      probs <- check_probs(probs, "probs")
      num_std_dev <- check_num_std_dev(num_std_dev)
      req_rank_lower_bound_cpp(private$ptr, probs, num_std_dev)
    },

    rank_upper_bound = function(probs, num_std_dev = 1) {
      probs <- check_probs(probs, "probs")
      num_std_dev <- check_num_std_dev(num_std_dev)
      req_rank_upper_bound_cpp(private$ptr, probs, num_std_dev)
    },

    # Stable structured metadata (a plain named list). min/max are NA on an
    # empty sketch rather than raising, so `summary()` is always safe to call.
    # Unlike KLL, REQ's error is rank-dependent, so `hra` is reported instead
    # of a single `rank_error` value.
    summary = function(...) {
      empty <- self$is_empty()
      list(
        type = private$type_id,
        n = self$n(),
        k = self$k(),
        hra = self$is_hra(),
        num_retained = self$num_retained(),
        is_empty = empty,
        is_estimation_mode = self$is_estimation_mode(),
        min = if (empty) NA_real_ else self$min(),
        max = if (empty) NA_real_ else self$max()
      )
    },

    # Concise one-line representation (same text as `as.character()`).
    format = function(...) {
      mode <- if (self$is_estimation_mode()) ", estimation" else ""
      hra <- if (self$is_hra()) "hra" else "lra"
      sprintf(
        "<req_sketch[n=%s, k=%d, %s%s]>",
        format(self$n(), scientific = FALSE, trim = TRUE),
        self$k(),
        hra,
        mode
      )
    },

    print = function(...) {
      empty <- self$is_empty()
      cat("<req_sketch>\n")
      cat(sprintf(
        "  n          : %s\n",
        format(self$n(), scientific = FALSE, trim = TRUE)
      ))
      cat(sprintf("  k          : %d\n", self$k()))
      cat(sprintf("  hra        : %s\n", self$is_hra()))
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
      invisible(self)
    },

    # Verbose upstream debug string (REQ levels and, optionally, retained items).
    inspect = function(levels = TRUE, items = FALSE) {
      levels <- check_flag(levels, "levels")
      items <- check_flag(items, "items")
      cat(req_to_string_cpp(private$ptr, levels, items))
      invisible(self)
    },

    serialize = function() {
      req_serialize_cpp(private$ptr)
    },

    # Stable type id for later typed persistence (write_sketch, deferred to 0.1.1).
    sketch_type = function() {
      private$type_id
    }
  ),
  private = list(
    ptr = NULL,
    type_id = "req"
  )
)

#' REQ sketch for relative-error approximate quantiles of a numeric stream
#'
#' Creates a [REQ](https://datasketches.apache.org/docs/REQ/ReqSketch.html)
#' (Relative Error Quantiles) sketch over `double` values. Like [kll_doubles()],
#' a REQ sketch is a compact, mergeable summary that answers approximate
#' quantile, rank, CDF, and PMF queries over a stream far larger than memory.
#' Unlike KLL, REQ's accuracy is *relative* and rank-dependent: error is small
#' near the prioritized end of the rank range (controlled by `hra`) and grows
#' towards the other end.
#'
#' At most one of `x` or `bytes` may be supplied:
#'
#' * Pass `x` to build a sketch and immediately update it with a numeric vector.
#' * Pass `bytes` to reconstruct a sketch from a native serialized payload (as
#'   produced by `sketch$serialize()`). Width and `hra` are restored from the
#'   payload, so `k` and `hra` must not be supplied alongside `bytes`.
#' * Pass neither for an empty sketch of width `k`.
#'
#' `update()` silently ignores `NA`/`NaN`, matching the upstream/Python behaviour;
#' there is no `na_rm` argument.
#'
#' @param x Optional numeric vector to update the new sketch with.
#' @param k Sketch width controlling the accuracy/size trade-off, a single
#'   even whole number in `[4, 1024]`. Larger `k` is more accurate and larger;
#'   `k = 12` corresponds to roughly 1% relative error at 95% confidence.
#'   Defaults to `12` (resolved when a fresh sketch is built). Must not be set
#'   when `bytes` is supplied.
#' @param hra If `TRUE`, prioritize accuracy for high ranks (near 1.0); if
#'   `FALSE`, prioritize low ranks (near 0.0). Defaults to `TRUE` (resolved
#'   when a fresh sketch is built). Must not be set when `bytes` is supplied.
#' @param bytes Optional [raw] vector holding a native serialized sketch to
#'   reconstruct.
#'
#' @return A `req_sketch` object. Key methods:
#'   \describe{
#'     \item{`$update(x)`}{Add numeric values (mutates, returns the sketch).}
#'     \item{`$merge(other)`}{Absorb another sketch (mutates, returns the sketch).}
#'     \item{`$quantile(probs, inclusive = TRUE)`}{Approximate quantiles for
#'       probabilities in `[0, 1]`.}
#'     \item{`$rank(x, inclusive = TRUE)`}{Approximate ranks of `x`; missing
#'       inputs return `NA`.}
#'     \item{`$cdf(split_points)` / `$pmf(split_points)`}{Cumulative / mass
#'       estimates; return `length(split_points) + 1` values.}
#'     \item{`$rank_lower_bound(probs, num_std_dev = 1)` /
#'       `$rank_upper_bound(probs, num_std_dev = 1)`}{Approximate confidence
#'       bounds on the rank(s) `probs`, at 1, 2, or 3 standard deviations.}
#'     \item{`$n()`, `$k()`, `$num_retained()`, `$is_empty()`,
#'       `$is_estimation_mode()`, `$min()`, `$max()`, `$is_hra()`}{
#'       Metadata accessors.}
#'     \item{`$summary()`, `$inspect()`, `$serialize()`}{Structured metadata,
#'       verbose debug output, and the native byte payload.}
#'   }
#'
#' @examples
#' sketch <- req(rnorm(10000))
#' sketch$quantile(c(0.25, 0.5, 0.75))
#' sketch$rank(c(-1, 0, 1))
#' sketch$rank_upper_bound(0.99)
#'
#' # Round-trip through the native byte format.
#' restored <- req(bytes = sketch$serialize())
#' identical(restored$quantile(0.5), sketch$quantile(0.5))
#'
#' @export
req <- function(x = NULL, k = NULL, hra = NULL, bytes = NULL) {
  req_sketch_generator$new(x = x, k = k, hra = hra, bytes = bytes)
}
