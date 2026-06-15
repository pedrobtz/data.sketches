# CPC (Compressed Probabilistic Counting) sketch: the R6 implementation and
# its exported constructor. The generator is internal; users go through
# `cpc()`. See `_dev/WORKING-ON.md` for the public API contract and
# implementation status. Like HLL (`R/cardinality-hll.R`), CPC has no direct
# `merge()` and accepts both numeric and character streams. Unlike HLL, CPC is
# a *seeded* family: the hash seed is part of its serialization compatibility
# contract (not stored in the payload), so it is exposed as a constructor
# argument and tracked alongside the native pointer.
# Native bridge functions live in `src/cpc_sketch.cpp`.

# Reach a sibling instance's native pointer and seed. R6 `private` is
# per-instance, so operations between two sketches (merge) read the other's
# state through its enclosing environment. Internal; never a public surface.
cpc_ptr <- function(x) {
  x$.__enclos_env__$private$ptr
}

cpc_seed <- function(x) {
  x$.__enclos_env__$private$hash_seed
}

# Internal R6 generator. `cloneable = FALSE` because the default shallow clone
# would copy the R6 wrapper while aliasing the same native sketch.
cpc_sketch_generator <- R6Class(
  "cpc_sketch",
  cloneable = FALSE,
  public = list(
    initialize = function(x = NULL, lg_k = NULL, seed = NULL, bytes = NULL) {
      if (!is.null(x) && !is.null(bytes)) {
        abort_invalid(
          "At most one of `x` and `bytes` may be supplied.",
          "datasketches_invalid_args"
        )
      }
      seed <- if (is.null(seed)) 9001 else check_seed(seed)
      if (!is.null(bytes)) {
        if (!is.null(lg_k)) {
          abort_invalid(
            "`lg_k` cannot be set when `bytes` is supplied; it is restored from the payload.",
            "datasketches_invalid_args"
          )
        }
        if (!is.raw(bytes)) {
          abort_invalid(
            "`bytes` must be a raw vector.",
            "datasketches_invalid_args"
          )
        }
        private$ptr <- cpc_deserialize_cpp(bytes, seed)
      } else {
        lg_k <- if (is.null(lg_k)) {
          11L
        } else {
          check_lg_k(lg_k, min = 4L, max = 26L)
        }
        private$ptr <- cpc_create_cpp(lg_k, seed)
        if (!is.null(x)) {
          self$update(x)
        }
      }
      private$hash_seed <- seed
      invisible(self)
    },

    # Accepts numeric or character input; each element is hashed to estimate
    # distinct-value cardinality. `NA`/`NaN`/`NA_character_` are silently
    # ignored, matching the missing-value policy used across families.
    update = function(x) {
      x <- check_hashable_stream(x, "x")
      x <- x[!is.na(x)]
      if (is.character(x)) {
        cpc_update_strings_cpp(private$ptr, x)
      } else {
        cpc_update_doubles_cpp(private$ptr, x)
      }
      invisible(self)
    },

    # Mutating merge. CPC has no native merge(); internally this feeds both
    # sketches into a union sized for the larger `lg_k` and replaces this
    # sketch's state with the union result. Both sketches must share the same
    # `seed`; self-merge is rejected for consistency with other families.
    merge = function(other) {
      check_cpc(other, "other")
      if (identical(private$ptr, cpc_ptr(other))) {
        abort_invalid(
          "A sketch cannot be merged into itself.",
          "datasketches_self_merge"
        )
      }
      if (!identical(private$hash_seed, cpc_seed(other))) {
        abort_invalid(
          "Cannot merge CPC sketches created with different `seed` values.",
          "datasketches_seed_mismatch"
        )
      }
      cpc_merge_cpp(private$ptr, cpc_ptr(other), private$hash_seed)
      invisible(self)
    },

    # Approximate count of distinct values seen so far.
    estimate = function() {
      cpc_get_estimate_cpp(private$ptr)
    },

    # Approximate confidence interval around `estimate()`, at 1, 2, or 3
    # standard deviations.
    lower_bound = function(num_std_dev = 1) {
      num_std_dev <- check_num_std_dev(num_std_dev)
      cpc_get_lower_bound_cpp(private$ptr, num_std_dev)
    },

    upper_bound = function(num_std_dev = 1) {
      num_std_dev <- check_num_std_dev(num_std_dev)
      cpc_get_upper_bound_cpp(private$ptr, num_std_dev)
    },

    # log2 of the number of bins configured for this sketch.
    lg_k = function() {
      cpc_get_lg_k_cpp(private$ptr)
    },

    # Hash seed this sketch was created with. Two sketches can only be merged
    # if their seeds match.
    seed = function() {
      private$hash_seed
    },

    is_empty = function() {
      cpc_is_empty_cpp(private$ptr)
    },

    # Stable structured metadata (a plain named list).
    summary = function(...) {
      list(
        type = private$type_id,
        lg_k = self$lg_k(),
        seed = self$seed(),
        is_empty = self$is_empty(),
        estimate = self$estimate(),
        lower_bound = self$lower_bound(),
        upper_bound = self$upper_bound()
      )
    },

    # Concise one-line representation (same text as `as.character()`).
    format = function(...) {
      if (self$is_empty()) {
        sprintf("<cpc_sketch[lg_k=%d, empty]>", self$lg_k())
      } else {
        sprintf(
          "<cpc_sketch[lg_k=%d, estimate=%s]>",
          self$lg_k(),
          format(self$estimate(), scientific = FALSE, trim = TRUE, digits = 6)
        )
      }
    },

    print = function(...) {
      empty <- self$is_empty()
      cat("<cpc_sketch>\n")
      cat(sprintf("  lg_k     : %d\n", self$lg_k()))
      cat(sprintf("  seed     : %s\n", format(self$seed(), scientific = FALSE)))
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
    inspect = function() {
      cat(cpc_to_string_cpp(private$ptr))
      invisible(self)
    },

    serialize = function() {
      cpc_serialize_cpp(private$ptr)
    },

    # Stable type id for later typed persistence (write_sketch, deferred to 0.1.1).
    sketch_type = function() {
      private$type_id
    }
  ),
  private = list(
    ptr = NULL,
    hash_seed = NULL,
    type_id = "cpc"
  )
)

#' CPC sketch for approximate distinct counting
#'
#' Creates a [CPC](https://datasketches.apache.org/docs/CPC/CpcSketches.html)
#' (Compressed Probabilistic Counting) sketch, a very compact, mergeable
#' summary that estimates the number of distinct values seen in a stream far
#' larger than memory. CPC sketches are similar in purpose to [hll()] but
#' serialize to a smaller payload, at the cost of slightly higher CPU use.
#'
#' At most one of `x` or `bytes` may be supplied:
#'
#' * Pass `x` to build a sketch and immediately update it with a numeric or
#'   character vector.
#' * Pass `bytes` to reconstruct a sketch from a native serialized payload (as
#'   produced by `sketch$serialize()`). `lg_k` is restored from the payload
#'   and must not be supplied alongside `bytes`. Unlike `lg_k`, the hash
#'   `seed` is *not* stored in the payload and must be supplied if the
#'   original sketch did not use the default.
#' * Pass neither for an empty sketch with the given `lg_k` and `seed`.
#'
#' `update()` silently ignores `NA`/`NaN`/`NA_character_`, matching the
#' missing-value policy used across families; there is no `na_rm` argument.
#'
#' Two sketches can only be merged with `$merge()` if they share the same
#' `seed`; a mismatch raises `datasketches_seed_mismatch`.
#'
#' @param x Optional numeric or character vector to update the new sketch
#'   with. Each element is hashed and contributes to the distinct-count
#'   estimate.
#' @param lg_k log2 of the number of bins, a single whole number in
#'   `[4, 26]`. Larger `lg_k` is more accurate and larger. Defaults to `11`
#'   (resolved when a fresh sketch is built). Must not be set when `bytes` is
#'   supplied.
#' @param seed Hash seed, a single non-negative whole number up to `2^53`.
#'   Defaults to `9001` (the upstream default), resolved whether or not `bytes`
#'   is supplied.
#' @param bytes Optional [raw] vector holding a native serialized sketch to
#'   reconstruct.
#'
#' @return A `cpc_sketch` object. Key methods:
#'   \describe{
#'     \item{`$update(x)`}{Add numeric or character values (mutates, returns
#'       the sketch).}
#'     \item{`$merge(other)`}{Absorb another sketch with the same `seed`
#'       (mutates, returns the sketch).}
#'     \item{`$estimate()`}{Approximate number of distinct values seen.}
#'     \item{`$lower_bound(num_std_dev = 1)` / `$upper_bound(num_std_dev = 1)`}{
#'       Approximate confidence bounds on `estimate()`, at 1, 2, or 3 standard
#'       deviations.}
#'     \item{`$lg_k()`, `$seed()`, `$is_empty()`}{Metadata accessors.}
#'     \item{`$summary()`, `$inspect()`, `$serialize()`}{Structured metadata,
#'       verbose debug output, and the native byte payload.}
#'   }
#'
#' @examples
#' sketch <- cpc(sample(1000, 5000, replace = TRUE))
#' sketch$estimate()
#' sketch$lower_bound()
#' sketch$upper_bound()
#'
#' # Round-trip through the native byte format.
#' restored <- cpc(bytes = sketch$serialize())
#' identical(restored$estimate(), sketch$estimate())
#'
#' @export
cpc <- function(x = NULL, lg_k = NULL, seed = NULL, bytes = NULL) {
  cpc_sketch_generator$new(x = x, lg_k = lg_k, seed = seed, bytes = bytes)
}
