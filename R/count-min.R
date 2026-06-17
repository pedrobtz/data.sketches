# Count-Min sketch: the R6 implementation and its exported constructor. The
# generator is internal; users go through `count_min()`. See
# `_dev/WORKING-ON.md` for the public API contract and implementation status.
#
# Unlike the cardinality families, Count-Min tracks (item, weight) pairs and
# answers point-frequency queries. It accepts numeric or character streams:
# numeric items are hashed via the raw bytes of their IEEE-754 double
# representation, consistently between `update()` and the estimate/bound
# queries. Like CPC, it is seeded, but the seed (together with `num_hashes`
# and `num_buckets`) is part of the merge-compatibility contract rather than a
# serialization mismatch concern. It has a direct native `merge()`.
# Native bridge functions live in `src/count_min_sketch.cpp`.

# Reach a sibling instance's native pointer and seed. R6 `private` is
# per-instance, so `merge()` reads the other's state through its enclosing
# environment. Internal; never a public surface.
cm_ptr <- function(x) {
  x$.__enclos_env__$private$ptr
}

cm_seed <- function(x) {
  x$.__enclos_env__$private$hash_seed
}

# Internal R6 generator. `cloneable = FALSE` because the default shallow clone
# would copy the R6 wrapper while aliasing the same native sketch.
count_min_sketch_generator <- R6Class(
  "count_min_sketch",
  cloneable = FALSE,
  public = list(
    initialize = function(
      x = NULL,
      weight = NULL,
      num_hashes = NULL,
      num_buckets = NULL,
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
        if (!is.null(num_hashes) || !is.null(num_buckets)) {
          abort_invalid(
            "`num_hashes` and `num_buckets` cannot be set when `bytes` is supplied; they are restored from the payload.",
            "datasketches_invalid_args"
          )
        }
        if (!is.raw(bytes)) {
          abort_invalid(
            "`bytes` must be a raw vector.",
            "datasketches_invalid_args"
          )
        }
        private$ptr <- cm_deserialize_cpp(bytes, seed)
      } else {
        num_hashes <- if (is.null(num_hashes)) {
          3L
        } else {
          check_num_hashes(num_hashes)
        }
        num_buckets <- if (is.null(num_buckets)) {
          55L
        } else {
          check_num_buckets(num_buckets, num_hashes)
        }
        private$ptr <- cm_create_cpp(num_hashes, num_buckets, seed)
        if (!is.null(x)) {
          self$update(x, weight)
        } else if (!is.null(weight)) {
          abort_invalid(
            "`weight` cannot be set without `x`.",
            "datasketches_invalid_args"
          )
        }
      }
      private$hash_seed <- seed
      invisible(self)
    },

    # Accepts numeric or character input. `weight` is a finite number (may be
    # negative or fractional), either a single value (recycled) or a vector
    # matching the length of `x`; it defaults to `1` (each occurrence counts
    # once). `NA`/`NaN`/`NA_character_` are silently ignored, matching the
    # missing-value policy used across families. Numeric items are hashed via
    # the raw bytes of their IEEE-754 double representation.
    update = function(x, weight = NULL) {
      x <- check_hashable_stream(x, "x")
      weight <- if (is.null(weight)) 1 else check_cm_weight(weight, length(x))
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
        if (is.character(x)) {
          cm_update_strings_cpp(private$ptr, x, weight)
        } else {
          cm_update_doubles_cpp(private$ptr, x, weight)
        }
      }
      invisible(self)
    },

    # Mutating merge. Count-Min has a direct native merge(), but it requires
    # both sketches to share the same `num_hashes`, `num_buckets`, and `seed`
    # (otherwise the per-bucket counts are not comparable). Self-merge is
    # rejected for consistency with other families.
    merge = function(other) {
      check_count_min(other, "other")
      if (identical(private$ptr, cm_ptr(other))) {
        abort_invalid(
          "A sketch cannot be merged into itself.",
          "datasketches_self_merge"
        )
      }
      if (
        !identical(self$num_hashes(), other$num_hashes()) ||
          !identical(self$num_buckets(), other$num_buckets()) ||
          !identical(private$hash_seed, cm_seed(other))
      ) {
        abort_invalid(
          "Cannot merge Count-Min sketches with different `num_hashes`, `num_buckets`, or `seed`.",
          "datasketches_incompatible_sketch"
        )
      }
      cm_merge_cpp(private$ptr, cm_ptr(other))
      invisible(self)
    },

    # Estimated frequency (weight) of `item`, vectorized over a numeric or
    # character vector. Numeric items are hashed via the raw bytes of their
    # IEEE-754 double representation, matching `update()`.
    estimate = function(item) {
      item <- check_query_item(item)
      if (is.character(item)) {
        cm_get_estimate_strings_cpp(private$ptr, item)
      } else {
        cm_get_estimate_doubles_cpp(private$ptr, item)
      }
    },

    # Guaranteed lower/upper bound on the frequency of `item`, vectorized over
    # a numeric or character vector.
    lower_bound = function(item) {
      item <- check_query_item(item)
      if (is.character(item)) {
        cm_get_lower_bound_strings_cpp(private$ptr, item)
      } else {
        cm_get_lower_bound_doubles_cpp(private$ptr, item)
      }
    },

    upper_bound = function(item) {
      item <- check_query_item(item)
      if (is.character(item)) {
        cm_get_upper_bound_strings_cpp(private$ptr, item)
      } else {
        cm_get_upper_bound_doubles_cpp(private$ptr, item)
      }
    },

    # Sum of all weights (occurrences) seen so far.
    total_weight = function() {
      cm_get_total_weight_cpp(private$ptr)
    },

    # `exp(1) / num_buckets`: the relative error bound used by the sketch.
    relative_error = function() {
      cm_get_relative_error_cpp(private$ptr)
    },

    num_hashes = function() {
      as.integer(cm_get_num_hashes_cpp(private$ptr))
    },

    num_buckets = function() {
      as.integer(cm_get_num_buckets_cpp(private$ptr))
    },

    # Hash seed this sketch was created with. Two sketches can only be merged
    # if their `num_hashes`, `num_buckets`, and `seed` all match.
    seed = function() {
      private$hash_seed
    },

    is_empty = function() {
      cm_is_empty_cpp(private$ptr)
    },

    # Stable structured metadata (a plain named list).
    summary = function(...) {
      list(
        type = private$type_id,
        is_empty = self$is_empty(),
        num_hashes = self$num_hashes(),
        num_buckets = self$num_buckets(),
        seed = self$seed(),
        relative_error = self$relative_error(),
        total_weight = self$total_weight()
      )
    },

    # Concise one-line representation (same text as `as.character()`).
    format = function(...) {
      if (self$is_empty()) {
        sprintf(
          "<count_min_sketch[num_hashes=%d, num_buckets=%d, empty]>",
          self$num_hashes(),
          self$num_buckets()
        )
      } else {
        sprintf(
          "<count_min_sketch[num_hashes=%d, num_buckets=%d, total_weight=%s]>",
          self$num_hashes(),
          self$num_buckets(),
          format(self$total_weight(), scientific = FALSE, trim = TRUE)
        )
      }
    },

    print = function(...) {
      empty <- self$is_empty()
      cat("<count_min_sketch>\n")
      cat(sprintf("  num_hashes     : %d\n", self$num_hashes()))
      cat(sprintf("  num_buckets    : %d\n", self$num_buckets()))
      cat(sprintf(
        "  relative_error : %s\n",
        format(self$relative_error(), scientific = FALSE, trim = TRUE)
      ))
      cat(sprintf("  empty          : %s\n", empty))
      if (!empty) {
        cat(sprintf(
          "  total_weight   : %s\n",
          format(self$total_weight(), scientific = FALSE, trim = TRUE)
        ))
      }
      invisible(self)
    },

    # Verbose upstream debug string.
    inspect = function() {
      cat(cm_to_string_cpp(private$ptr))
      invisible(self)
    },

    serialize = function() {
      cm_serialize_cpp(private$ptr)
    },

    # Stable type id for later typed persistence (write_sketch, deferred to 0.1.1).
    sketch_type = function() {
      private$type_id
    }
  ),
  private = list(
    ptr = NULL,
    hash_seed = NULL,
    type_id = "count_min"
  )
)

#' Count-Min sketch for approximate point-frequency estimation
#'
#' Creates a [Count-Min](https://apache.github.io/datasketches-cpp/5.2.0/classdatasketches_1_1count__min__sketch.html)
#' sketch, a mergeable summary that estimates the frequency (sum of weights)
#' of individual items in a numeric or character stream far larger than
#' memory, with one-sided error: `$estimate()` never under-estimates the true
#' frequency.
#'
#' At most one of `x` or `bytes` may be supplied:
#'
#' * Pass `x` to build a sketch and immediately update it with a numeric or
#'   character vector (optionally with `weight`).
#' * Pass `bytes` to reconstruct a sketch from a native serialized payload (as
#'   produced by `sketch$serialize()`). `num_hashes` and `num_buckets` are
#'   restored from the payload and must not be supplied alongside `bytes`.
#' * Pass neither for an empty sketch with the given `num_hashes` and
#'   `num_buckets`.
#'
#' Numeric items are hashed via the raw bytes of their IEEE-754 double
#' representation; this is internally consistent between `update()` and the
#' `estimate()`/`lower_bound()`/`upper_bound()` queries, but is not guaranteed
#' to match hashes produced by other DataSketches language implementations for
#' the same numeric value.
#'
#' `NA`/`NaN`/`NA_character_` are silently ignored by `update()`, matching the
#' missing-value policy used across families; there is no `na_rm` argument.
#'
#' Two sketches can only be `$merge()`d if they share the same `num_hashes`,
#' `num_buckets`, and `seed`; a mismatch raises
#' `datasketches_incompatible_sketch`.
#'
#' @param x Optional numeric or character vector to update the new sketch
#'   with.
#' @param weight Optional weight(s) for `x`: a single finite number (recycled,
#'   may be negative or fractional), or a vector of such values matching the
#'   length of `x`. Defaults to `1` (each occurrence counts once). Cannot be
#'   set without `x`.
#' @param num_hashes Number of hash functions, a single whole number in
#'   `[1, 255]`. Larger values increase confidence but also memory use.
#'   Defaults to `3`. Must not be set when `bytes` is supplied. See
#'   [count_min_suggest_num_hashes()].
#' @param num_buckets Number of buckets per hash function, a single whole
#'   number of at least `3` (and such that `num_buckets * num_hashes < 2^30`).
#'   Larger values are more accurate and larger. Defaults to `55`. Must not be
#'   set when `bytes` is supplied. See [count_min_suggest_num_buckets()].
#' @param seed Hash seed, a single non-negative whole number up to `2^53`.
#'   Defaults to `9001`. Two sketches can only be merged if their `seed` (and
#'   `num_hashes` and `num_buckets`) match.
#' @param bytes Optional [raw] vector holding a native serialized sketch to
#'   reconstruct.
#'
#' @return A `count_min_sketch` object. Key methods:
#'   \describe{
#'     \item{`$update(x, weight = NULL)`}{Add numeric or character values with
#'       an optional weight (mutates, returns the sketch).}
#'     \item{`$merge(other)`}{Absorb another sketch with matching
#'       `num_hashes`, `num_buckets`, and `seed` (mutates, returns the
#'       sketch).}
#'     \item{`$estimate(item)`, `$lower_bound(item)`, `$upper_bound(item)`}{
#'       Estimated frequency and guaranteed bounds for one or more items.}
#'     \item{`$total_weight()`, `$relative_error()`, `$num_hashes()`,
#'       `$num_buckets()`, `$seed()`, `$is_empty()`}{Metadata accessors.}
#'     \item{`$summary()`, `$inspect()`, `$serialize()`}{Structured metadata,
#'       verbose debug output, and the native byte payload.}
#'   }
#'
#' @examples
#' words <- sample(letters[1:5], 1000, replace = TRUE, prob = c(.5, .25, .1, .1, .05))
#' sketch <- count_min(words)
#' sketch$estimate("a")
#' sketch$relative_error()
#'
#' # Round-trip through the native byte format.
#' restored <- count_min(bytes = sketch$serialize())
#' identical(restored$total_weight(), sketch$total_weight())
#'
#' @export
count_min <- function(
  x = NULL,
  weight = NULL,
  num_hashes = NULL,
  num_buckets = NULL,
  seed = NULL,
  bytes = NULL
) {
  count_min_sketch_generator$new(
    x = x,
    weight = weight,
    num_hashes = num_hashes,
    num_buckets = num_buckets,
    seed = seed,
    bytes = bytes
  )
}

#' Suggest Count-Min sketch parameters
#'
#' Helpers to translate a desired accuracy into the `num_buckets` and
#' `num_hashes` arguments of [count_min()].
#'
#' @param relative_error Desired relative error, a single positive number.
#'   `count_min_suggest_num_buckets()` returns the smallest `num_buckets` such
#'   that the sketch's `$relative_error()` does not exceed this value.
#' @param confidence Desired confidence, a single number in `(0, 1]`.
#'   `count_min_suggest_num_hashes()` returns the smallest `num_hashes` such
#'   that, with this probability, `$estimate()` is within `$relative_error()`
#'   of the true frequency.
#'
#' @return A single integer.
#'
#' @examples
#' num_buckets <- count_min_suggest_num_buckets(0.05)
#' num_hashes <- count_min_suggest_num_hashes(0.95)
#' sketch <- count_min(num_hashes = num_hashes, num_buckets = num_buckets)
#'
#' @name count_min_suggest
#' @export
count_min_suggest_num_buckets <- function(relative_error) {
  relative_error <- check_relative_error(relative_error)
  as.integer(cm_suggest_num_buckets_cpp(relative_error))
}

#' @rdname count_min_suggest
#' @export
count_min_suggest_num_hashes <- function(confidence) {
  confidence <- check_confidence(confidence)
  as.integer(cm_suggest_num_hashes_cpp(confidence))
}
