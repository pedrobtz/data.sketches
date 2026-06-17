# t-Digest double sketch: the R6 implementation and its exported constructor.
# The generator is internal; users go through `tdigest_double()`.
# Native bridge functions live in `src/tdigest_double.cpp`.

# Reach a sibling instance's native pointer. R6 `private` is per-instance, so
# operations between two sketches (merge) read the other's pointer through its
# enclosing environment. Internal; the raw pointer is never a public surface.
td_ptr <- function(x) {
  x$.__enclos_env__$private$ptr
}

# Internal R6 generator. `cloneable = FALSE` because the default shallow clone
# would copy the R6 wrapper while aliasing the same native sketch.
tdigest_double_sketch_generator <- R6Class(
  "tdigest_double_sketch",
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
        private$ptr <- td_deserialize_cpp(bytes)
      } else {
        k <- if (is.null(k)) 200L else check_tdigest_k(k)
        private$ptr <- td_create_cpp(k)
        if (!is.null(x)) {
          self$update(x)
        }
      }
      invisible(self)
    },

    update = function(x) {
      x <- check_numeric_stream(x, "x")
      td_update_cpp(private$ptr, x)
      invisible(self)
    },

    # Mutating merge. Self-merge is undefined behaviour in the vendored C++
    # (no aliasing guard), so reject an identical pointer before the native call.
    merge = function(other) {
      check_tdigest_double(other, "other")
      if (identical(private$ptr, td_ptr(other))) {
        abort_invalid(
          "A sketch cannot be merged into itself.",
          "datasketches_self_merge"
        )
      }
      td_merge_cpp(private$ptr, td_ptr(other))
      invisible(self)
    },

    # Unlike KLL/REQ, t-Digest has no `inclusive` argument for quantile/rank.
    quantile = function(probs) {
      probs <- check_probs(probs)
      td_get_quantiles_cpp(private$ptr, probs)
    },

    # `rank` treats input as data values: missing inputs map to NA_real_ in the
    # shape-preserving output rather than querying the sketch.
    rank = function(x) {
      x <- check_numeric_stream(x, "x")
      out <- rep(NA_real_, length(x))
      ok <- !is.na(x)
      if (any(ok)) {
        out[ok] <- td_get_ranks_cpp(private$ptr, x[ok])
      }
      out
    },

    # `cdf`/`pmf` are NOT length-preserving: n split points produce n + 1 values.
    cdf = function(split_points) {
      split_points <- check_split_points(split_points)
      td_get_cdf_cpp(private$ptr, split_points)
    },

    pmf = function(split_points) {
      split_points <- check_split_points(split_points)
      td_get_pmf_cpp(private$ptr, split_points)
    },

    n = function() {
      td_get_total_weight_cpp(private$ptr)
    },

    k = function() {
      td_get_k_cpp(private$ptr)
    },

    is_empty = function() {
      td_is_empty_cpp(private$ptr)
    },

    min = function() {
      td_get_min_value_cpp(private$ptr)
    },

    max = function() {
      td_get_max_value_cpp(private$ptr)
    },

    # Stable structured metadata (a plain named list). min/max are NA on an empty
    # sketch rather than raising, so `summary()` is always safe to call.
    summary = function(...) {
      empty <- self$is_empty()
      list(
        type = private$type_id,
        n = self$n(),
        k = self$k(),
        is_empty = empty,
        min = if (empty) NA_real_ else self$min(),
        max = if (empty) NA_real_ else self$max()
      )
    },

    # Concise one-line representation (same text as `as.character()`).
    format = function(...) {
      sprintf(
        "<tdigest_double_sketch[n=%s, k=%d]>",
        format(self$n(), scientific = FALSE, trim = TRUE),
        self$k()
      )
    },

    print = function(...) {
      empty <- self$is_empty()
      cat("<tdigest_double_sketch>\n")
      cat(sprintf(
        "  n          : %s\n",
        format(self$n(), scientific = FALSE, trim = TRUE)
      ))
      cat(sprintf("  k          : %d\n", self$k()))
      if (empty) {
        cat("  min / max  : <empty>\n")
      } else {
        cat(sprintf("  min / max  : %s / %s\n", self$min(), self$max()))
      }
      invisible(self)
    },

    # Verbose upstream debug string (t-Digest summary and, optionally, centroids).
    inspect = function(centroids = FALSE) {
      centroids <- check_flag(centroids, "centroids")
      cat(td_to_string_cpp(private$ptr, centroids))
      invisible(self)
    },

    serialize = function() {
      td_serialize_cpp(private$ptr)
    },

    # Stable type id for later typed persistence (write_sketch, deferred to 0.1.1).
    sketch_type = function() {
      private$type_id
    }
  ),
  private = list(
    ptr = NULL,
    type_id = "tdigest_double"
  )
)

#' t-Digest sketch for approximate quantiles of a numeric stream
#'
#' Creates a [t-Digest](https://github.com/tdunning/t-digest) quantile sketch
#' over `double` values. A t-Digest is a compact, mergeable summary that
#' answers approximate quantile, rank, CDF, and PMF queries over a stream far
#' larger than memory. Compared to [kll_doubles()] and [req()], a t-Digest
#' concentrates its accuracy near the tails of the distribution (extreme
#' quantiles such as p99 or p99.9), at some cost to accuracy near the median.
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
#' Unlike [kll_doubles()] and [req()], `$quantile()` and `$rank()` have no
#' `inclusive` argument, and there is no `$rank_error()` accuracy accessor.
#'
#' @param x Optional numeric vector to update the new sketch with.
#' @param k Compression parameter controlling the accuracy/size trade-off, a
#'   whole number in `[10, 65535]`. Larger `k` is more accurate and larger.
#'   Defaults to `200` (resolved when a fresh sketch is built). Must not be set
#'   when `bytes` is supplied.
#' @param bytes Optional [raw] vector holding a native serialized sketch to
#'   reconstruct.
#'
#' @return A `tdigest_double_sketch` object. Key methods:
#'   \describe{
#'     \item{`$update(x)`}{Add numeric values (mutates, returns the sketch).}
#'     \item{`$merge(other)`}{Absorb another sketch (mutates, returns the sketch).}
#'     \item{`$quantile(probs)`}{Approximate quantiles for probabilities in
#'       `[0, 1]`.}
#'     \item{`$rank(x)`}{Approximate ranks of `x`; missing inputs return `NA`.}
#'     \item{`$cdf(split_points)` / `$pmf(split_points)`}{Cumulative / mass
#'       estimates; return `length(split_points) + 1` values.}
#'     \item{`$n()`, `$k()`, `$is_empty()`, `$min()`, `$max()`}{Metadata
#'       accessors.}
#'     \item{`$summary()`, `$inspect()`, `$serialize()`}{Structured metadata,
#'       verbose debug output, and the native byte payload.}
#'   }
#'
#' @examples
#' sketch <- tdigest_double(rnorm(10000))
#' sketch$quantile(c(0.5, 0.99, 0.999))
#' sketch$rank(c(-1, 0, 1))
#'
#' # Round-trip through the native byte format.
#' restored <- tdigest_double(bytes = sketch$serialize())
#' identical(restored$quantile(0.5), sketch$quantile(0.5))
#'
#' @export
tdigest_double <- function(x = NULL, k = NULL, bytes = NULL) {
  tdigest_double_sketch_generator$new(x = x, k = k, bytes = bytes)
}
