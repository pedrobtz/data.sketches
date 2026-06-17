# Theta sketch: the R6 implementation, its exported constructor, and the
# top-level set-operation functions (`theta_union()`, `theta_intersection()`,
# `theta_difference()`, `theta_jaccard()`). The generator is internal; users
# go through `theta()`. See `_dev/WORKING-ON.md` for the public API contract
# and implementation status.
#
# Unlike HLL/CPC, a Theta sketch comes in two flavors that share a common
# native base: an *update* sketch (mutable, built via `$update()`) and a
# *compact* sketch (immutable; the result of `$merge()`, a set operation, or
# `bytes =` reconstruction). `$is_compact()` distinguishes the two. `$merge()`
# and the set-operation functions below always produce compact sketches.
# Native bridge functions live in `src/theta_sketch.cpp`.

# Reach a sibling instance's native pointer / seed / lg_k hint. R6 `private`
# is per-instance, so operations between two sketches (merge, set operations)
# read the other's state through its enclosing environment. Internal; never a
# public surface.
theta_ptr <- function(x) {
  x$.__enclos_env__$private$ptr
}

theta_seed <- function(x) {
  x$.__enclos_env__$private$hash_seed
}

theta_lg_k_hint <- function(x) {
  x$.__enclos_env__$private$lg_k_hint
}

# Build a `theta_sketch` R6 object that wraps an existing native pointer
# (the result of a set operation). Internal; never a public surface.
new_theta_sketch <- function(ptr, seed, lg_k_hint) {
  obj <- theta_sketch_generator$new(seed = seed)
  priv <- obj$.__enclos_env__$private
  priv$ptr <- ptr
  priv$lg_k_hint <- lg_k_hint
  obj
}

# Resolve the shared seed for a two-sketch set operation. Both sketches must
# have been created with the same `seed`.
theta_check_matching_seeds <- function(a, b, call = rlang::caller_env()) {
  seed_a <- theta_seed(a)
  seed_b <- theta_seed(b)
  if (!identical(seed_a, seed_b)) {
    abort_invalid(
      "`a` and `b` must be Theta sketches created with the same `seed`.",
      "datasketches_seed_mismatch",
      call = call
    )
  }
  seed_a
}

# Internal R6 generator. `cloneable = FALSE` because the default shallow clone
# would copy the R6 wrapper while aliasing the same native sketch.
theta_sketch_generator <- R6Class(
  "theta_sketch",
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
            "`lg_k` cannot be set when `bytes` is supplied; a deserialized sketch is always compact.",
            "datasketches_invalid_args"
          )
        }
        if (!is.raw(bytes)) {
          abort_invalid(
            "`bytes` must be a raw vector.",
            "datasketches_invalid_args"
          )
        }
        private$ptr <- theta_deserialize_cpp(bytes, seed)
        private$lg_k_hint <- 12L
      } else {
        lg_k <- if (is.null(lg_k)) {
          12L
        } else {
          check_lg_k(lg_k, min = 5L, max = 26L)
        }
        private$ptr <- theta_create_cpp(lg_k, seed)
        private$lg_k_hint <- lg_k
        if (!is.null(x)) {
          self$update(x)
        }
      }
      private$hash_seed <- seed
      invisible(self)
    },

    # Accepts numeric or character input; each element is hashed and
    # contributes to the distinct-count estimate. `NA`/`NaN`/`NA_character_`
    # are silently ignored, matching the missing-value policy used across
    # families. Errors if the sketch is compact (e.g. after `$merge()` or
    # `bytes =` reconstruction); compact sketches are immutable.
    update = function(x) {
      if (self$is_compact()) {
        abort_invalid(
          "Cannot update a compact Theta sketch.",
          "datasketches_invalid_op"
        )
      }
      x <- check_hashable_stream(x, "x")
      x <- x[!is.na(x)]
      if (is.character(x)) {
        theta_update_strings_cpp(private$ptr, x)
      } else {
        theta_update_doubles_cpp(private$ptr, x)
      }
      invisible(self)
    },

    # Mutating merge. Theta has no direct merge(); internally this feeds both
    # sketches into a union sized for the larger configured `lg_k` and
    # replaces this sketch's state with the (compact) union result. Both
    # sketches must share the same `seed`; self-merge is rejected for
    # consistency with other families. After merge(), the receiver is
    # compact and can no longer be updated.
    merge = function(other) {
      check_theta(other, "other")
      if (identical(private$ptr, theta_ptr(other))) {
        abort_invalid(
          "A sketch cannot be merged into itself.",
          "datasketches_self_merge"
        )
      }
      if (!identical(private$hash_seed, theta_seed(other))) {
        abort_invalid(
          "Cannot merge Theta sketches created with different `seed` values.",
          "datasketches_seed_mismatch"
        )
      }
      lg_max_k <- max(private$lg_k_hint, theta_lg_k_hint(other))
      theta_merge_cpp(
        private$ptr,
        theta_ptr(other),
        lg_max_k,
        private$hash_seed
      )
      private$lg_k_hint <- lg_max_k
      invisible(self)
    },

    # Approximate count of distinct values seen so far.
    estimate = function() {
      theta_get_estimate_cpp(private$ptr)
    },

    # Approximate confidence interval around `estimate()`, at 1, 2, or 3
    # standard deviations.
    lower_bound = function(num_std_dev = 1) {
      num_std_dev <- check_num_std_dev(num_std_dev)
      theta_get_lower_bound_cpp(private$ptr, num_std_dev)
    },

    upper_bound = function(num_std_dev = 1) {
      num_std_dev <- check_num_std_dev(num_std_dev)
      theta_get_upper_bound_cpp(private$ptr, num_std_dev)
    },

    # log2 of the configured nominal number of entries. Not defined for a
    # compact sketch (`$is_compact()` is `TRUE`).
    lg_k = function() {
      if (self$is_compact()) {
        abort_invalid(
          "`lg_k()` is not defined for a compact Theta sketch.",
          "datasketches_invalid_op"
        )
      }
      theta_get_lg_k_cpp(private$ptr)
    },

    # Hash seed this sketch was created with. Two sketches can only be merged
    # or combined with a set operation if their seeds match.
    seed = function() {
      private$hash_seed
    },

    # Effective sampling probability, a value in `(0, 1]`. `1` means the
    # sketch is in exact mode (every retained entry has been seen).
    theta = function() {
      theta_get_theta_cpp(private$ptr)
    },

    num_retained = function() {
      theta_get_num_retained_cpp(private$ptr)
    },

    is_empty = function() {
      theta_is_empty_cpp(private$ptr)
    },

    is_estimation_mode = function() {
      theta_is_estimation_mode_cpp(private$ptr)
    },

    is_ordered = function() {
      theta_is_ordered_cpp(private$ptr)
    },

    # `TRUE` if this sketch is an immutable compact sketch (the result of
    # `$merge()`, a set operation, or `bytes =` reconstruction); `FALSE` if it
    # is a mutable update sketch that can still be `$update()`d.
    is_compact = function() {
      theta_is_compact_cpp(private$ptr)
    },

    # Stable structured metadata (a plain named list).
    summary = function(...) {
      list(
        type = private$type_id,
        is_compact = self$is_compact(),
        lg_k = if (self$is_compact()) NA_integer_ else self$lg_k(),
        seed = self$seed(),
        is_empty = self$is_empty(),
        is_estimation_mode = self$is_estimation_mode(),
        estimate = self$estimate(),
        lower_bound = self$lower_bound(),
        upper_bound = self$upper_bound(),
        theta = self$theta(),
        num_retained = self$num_retained()
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
        sprintf("<theta_sketch[%s, empty]>", kind)
      } else {
        sprintf(
          "<theta_sketch[%s, estimate=%s]>",
          kind,
          format(self$estimate(), scientific = FALSE, trim = TRUE, digits = 6)
        )
      }
    },

    print = function(...) {
      empty <- self$is_empty()
      cat("<theta_sketch>\n")
      if (self$is_compact()) {
        cat("  lg_k     : <not defined, compact>\n")
      } else {
        cat(sprintf("  lg_k     : %d\n", self$lg_k()))
      }
      cat(sprintf("  compact  : %s\n", self$is_compact()))
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
    inspect = function(detail = FALSE) {
      detail <- check_flag(detail, "detail")
      cat(theta_to_string_cpp(private$ptr, detail))
      invisible(self)
    },

    serialize = function() {
      theta_serialize_cpp(private$ptr)
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
    type_id = "theta"
  )
)

#' Theta sketch for approximate distinct counting and set operations
#'
#' Creates a [Theta](https://datasketches.apache.org/docs/Theta/ThetaSketches.html)
#' sketch, a mergeable summary that estimates the number of distinct values
#' seen in a stream far larger than memory. Unlike [hll()] and [cpc()], Theta
#' sketches natively support set operations: [theta_union()],
#' [theta_intersection()], [theta_difference()], and [theta_jaccard()] combine
#' two sketches into a new result without mutating either input.
#'
#' At most one of `x` or `bytes` may be supplied:
#'
#' * Pass `x` to build a sketch and immediately update it with a numeric or
#'   character vector.
#' * Pass `bytes` to reconstruct a sketch from a native serialized payload (as
#'   produced by `sketch$serialize()`). The result is always a *compact*
#'   sketch (see below); `lg_k` must not be supplied alongside `bytes`.
#'   Unlike `lg_k`, the hash `seed` is *not* stored in the payload and must be
#'   supplied if the original sketch did not use the default.
#' * Pass neither for an empty (mutable) sketch with the given `lg_k` and
#'   `seed`.
#'
#' `update()` silently ignores `NA`/`NaN`/`NA_character_`, matching the
#' missing-value policy used across families; there is no `na_rm` argument.
#'
#' A Theta sketch is either an *update* sketch (mutable, `$is_compact()` is
#' `FALSE`) or a *compact* sketch (immutable, `$is_compact()` is `TRUE`).
#' Fresh sketches built from `x`/`lg_k` are update sketches and can be grown
#' with `$update()`. Compact sketches arise from `bytes =` reconstruction,
#' `$merge()`, or any of the `theta_*()` set operations, and cannot be
#' updated further. `$lg_k()` is only defined for update sketches.
#'
#' Two sketches can only be merged with `$merge()`, or combined with a
#' `theta_*()` set operation, if they share the same `seed`; a mismatch
#' raises `datasketches_seed_mismatch`. `$merge()` mutates the receiver into
#' a compact sketch holding the union of both inputs (so it can no longer be
#' `$update()`d afterward).
#'
#' @param x Optional numeric or character vector to update the new sketch
#'   with. Each element is hashed and contributes to the distinct-count
#'   estimate.
#' @param lg_k log2 of the nominal number of entries, a single whole number in
#'   `[5, 26]`. Larger `lg_k` is more accurate and larger. Defaults to `12`
#'   (resolved when a fresh sketch is built). Must not be set when `bytes` is
#'   supplied.
#' @param seed Hash seed, a single non-negative whole number up to `2^53`.
#'   Defaults to `9001` (the upstream default), resolved whether or not `bytes`
#'   is supplied.
#' @param bytes Optional [raw] vector holding a native serialized sketch to
#'   reconstruct. The result is always a compact sketch.
#'
#' @return A `theta_sketch` object. Key methods:
#'   \describe{
#'     \item{`$update(x)`}{Add numeric or character values (mutates, returns
#'       the sketch). Errors if the sketch is compact.}
#'     \item{`$merge(other)`}{Absorb another sketch with the same `seed`,
#'       becoming compact (mutates, returns the sketch).}
#'     \item{`$estimate()`}{Approximate number of distinct values seen.}
#'     \item{`$lower_bound(num_std_dev = 1)` / `$upper_bound(num_std_dev = 1)`}{
#'       Approximate confidence bounds on `estimate()`, at 1, 2, or 3 standard
#'       deviations.}
#'     \item{`$lg_k()`, `$seed()`, `$theta()`, `$num_retained()`,
#'       `$is_empty()`, `$is_estimation_mode()`, `$is_ordered()`,
#'       `$is_compact()`}{Metadata accessors.}
#'     \item{`$summary()`, `$inspect()`, `$serialize()`}{Structured metadata,
#'       verbose debug output, and the native byte payload.}
#'   }
#'
#' @examples
#' sketch <- theta(sample(1000, 5000, replace = TRUE))
#' sketch$estimate()
#' sketch$lower_bound()
#' sketch$upper_bound()
#'
#' # Round-trip through the native byte format (always compact).
#' restored <- theta(bytes = sketch$serialize())
#' restored$is_compact()
#' identical(restored$estimate(), sketch$estimate())
#'
#' # Set operations.
#' a <- theta(1:1000)
#' b <- theta(501:1500)
#' theta_union(a, b)$estimate()
#' theta_intersection(a, b)$estimate()
#' theta_difference(a, b)$estimate()
#' theta_jaccard(a, b)
#'
#' @export
theta <- function(x = NULL, lg_k = NULL, seed = NULL, bytes = NULL) {
  theta_sketch_generator$new(x = x, lg_k = lg_k, seed = seed, bytes = bytes)
}

#' Theta sketch set operations
#'
#' Combine two [theta()] sketches into a new compact `theta_sketch` result,
#' without mutating either input. `a` and `b` must be Theta sketches created
#' with the same `seed` (a mismatch raises `datasketches_seed_mismatch`).
#'
#' * `theta_union(a, b)` estimates the size of the union `union(A, B)`.
#' * `theta_intersection(a, b)` estimates the size of the intersection
#'   `intersection(A, B)`.
#' * `theta_difference(a, b)` estimates the size of the set difference
#'   `A \\ B` (elements in `A` but not `B`).
#' * `theta_jaccard(a, b)` estimates the
#'   [Jaccard similarity index](https://en.wikipedia.org/wiki/Jaccard_index)
#'   `J(A, B) = |intersection(A, B)| / |union(A, B)|`, returning a named
#'   numeric vector
#'   `c(lower_bound, estimate, upper_bound)` for a ~95% confidence interval.
#'
#' @param a,b `theta_sketch` objects created with the same `seed`.
#' @param lg_k For `theta_union()`, log2 of the nominal number of entries for
#'   the union's internal sketch, a single whole number in `[5, 26]`. Defaults
#'   to the larger of `a` and `b`'s configured `lg_k` (or `12` for compact
#'   inputs).
#'
#' @return A compact `theta_sketch` object (`theta_union()`,
#'   `theta_intersection()`, `theta_difference()`), or a named numeric vector
#'   `c(lower_bound, estimate, upper_bound)` (`theta_jaccard()`).
#'
#' @examples
#' a <- theta(1:1000)
#' b <- theta(501:1500)
#' theta_union(a, b)$estimate()
#' theta_intersection(a, b)$estimate()
#' theta_difference(a, b)$estimate()
#' theta_jaccard(a, b)
#'
#' @name theta_set_operations
#' @export
theta_union <- function(a, b, lg_k = NULL) {
  check_theta(a, "a")
  check_theta(b, "b")
  seed <- theta_check_matching_seeds(a, b)
  lg_k <- if (is.null(lg_k)) {
    max(theta_lg_k_hint(a), theta_lg_k_hint(b))
  } else {
    check_lg_k(lg_k, min = 5L, max = 26L)
  }
  ptr <- theta_union_cpp(theta_ptr(a), theta_ptr(b), lg_k, seed)
  new_theta_sketch(ptr, seed, lg_k)
}

#' @rdname theta_set_operations
#' @export
theta_intersection <- function(a, b) {
  check_theta(a, "a")
  check_theta(b, "b")
  seed <- theta_check_matching_seeds(a, b)
  ptr <- theta_intersection_cpp(theta_ptr(a), theta_ptr(b), seed)
  new_theta_sketch(ptr, seed, max(theta_lg_k_hint(a), theta_lg_k_hint(b)))
}

#' @rdname theta_set_operations
#' @export
theta_difference <- function(a, b) {
  check_theta(a, "a")
  check_theta(b, "b")
  seed <- theta_check_matching_seeds(a, b)
  ptr <- theta_a_not_b_cpp(theta_ptr(a), theta_ptr(b), seed)
  new_theta_sketch(ptr, seed, max(theta_lg_k_hint(a), theta_lg_k_hint(b)))
}

#' @rdname theta_set_operations
#' @export
theta_jaccard <- function(a, b) {
  check_theta(a, "a")
  check_theta(b, "b")
  seed <- theta_check_matching_seeds(a, b)
  result <- theta_jaccard_cpp(theta_ptr(a), theta_ptr(b), seed)
  names(result) <- c("lower_bound", "estimate", "upper_bound")
  result
}
