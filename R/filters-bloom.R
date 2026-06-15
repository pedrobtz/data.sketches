# Bloom filter: the R6 implementation and its exported constructor. The
# generator is internal; users go through `bloom_filter()`. See
# `_dev/WORKING-ON.md` for the public API contract and implementation status.
#
# Unlike the other families, a Bloom filter is not sub-linear in size: it is
# sized up front (either by accuracy, from a target number of distinct items
# and false-positive probability, or by an explicit number of bits and hash
# functions) and does not resize itself. It tracks set membership only (no
# weights, no estimate/bounds). Numeric items are hashed via the raw bytes of
# their IEEE-754 double representation, the same scheme used by Count-Min, so
# `update()` and `query()` stay consistent. `$merge()` (logical OR) and
# `$intersect()` (logical AND) are in-place and require the two filters to be
# "compatible" (same `seed`, `num_hashes`, and `capacity`). Native bridge
# functions live in `src/bloom_filter.cpp`.

# Reach a sibling instance's native pointer. R6 `private` is per-instance, so
# `merge()`/`intersect()` read the other filter's state through its enclosing
# environment. Internal; never a public surface.
bf_ptr <- function(x) {
  x$.__enclos_env__$private$ptr
}

# Internal R6 generator. `cloneable = FALSE` because the default shallow
# clone would copy the R6 wrapper while aliasing the same native filter.
bloom_filter_generator <- R6Class(
  "bloom_filter",
  cloneable = FALSE,
  public = list(
    initialize = function(
      x = NULL,
      max_items = NULL,
      fpp = NULL,
      num_bits = NULL,
      num_hashes = NULL,
      seed = NULL,
      bytes = NULL
    ) {
      if (!is.null(x) && !is.null(bytes)) {
        abort_invalid(
          "At most one of `x` and `bytes` may be supplied.",
          "datasketches_invalid_args"
        )
      }
      if (!is.null(bytes)) {
        if (
          !is.null(max_items) ||
            !is.null(fpp) ||
            !is.null(num_bits) ||
            !is.null(num_hashes) ||
            !is.null(seed)
        ) {
          abort_invalid(
            "`max_items`, `fpp`, `num_bits`, `num_hashes`, and `seed` cannot be set when `bytes` is supplied; they are restored from the payload.",
            "datasketches_invalid_args"
          )
        }
        if (!is.raw(bytes)) {
          abort_invalid(
            "`bytes` must be a raw vector.",
            "datasketches_invalid_args"
          )
        }
        private$ptr <- bf_deserialize_cpp(bytes)
      } else {
        has_accuracy <- !is.null(max_items) || !is.null(fpp)
        has_size <- !is.null(num_bits) || !is.null(num_hashes)
        if (has_accuracy && has_size) {
          abort_invalid(
            "`max_items`/`fpp` and `num_bits`/`num_hashes` cannot be combined; choose one sizing strategy.",
            "datasketches_invalid_args"
          )
        }

        seed <- if (is.null(seed)) 9001 else check_seed(seed)

        if (has_size) {
          if (is.null(num_bits) || is.null(num_hashes)) {
            abort_invalid(
              "`num_bits` and `num_hashes` must both be supplied.",
              "datasketches_invalid_args"
            )
          }
          num_bits <- check_bloom_num_bits(num_bits)
          num_hashes <- check_bloom_num_hashes(num_hashes)
          private$ptr <- bf_create_by_size_cpp(num_bits, num_hashes, seed)
        } else {
          if (is.null(max_items) && !is.null(fpp)) {
            abort_invalid(
              "`max_items` and `fpp` must both be supplied.",
              "datasketches_invalid_args"
            )
          }
          if (!is.null(max_items) && is.null(fpp)) {
            abort_invalid(
              "`max_items` and `fpp` must both be supplied.",
              "datasketches_invalid_args"
            )
          }
          max_items <- if (is.null(max_items)) {
            10000
          } else {
            check_bloom_max_items(max_items)
          }
          fpp <- if (is.null(fpp)) 0.01 else check_bloom_fpp(fpp)
          private$ptr <- bf_create_by_accuracy_cpp(max_items, fpp, seed)
        }

        if (!is.null(x)) {
          self$update(x)
        }
      }
      invisible(self)
    },

    # Accepts numeric or character input for `x`. `NA`/`NaN`/`NA_character_`
    # are silently ignored, matching the missing-value policy used across
    # families. Numeric items are hashed via the raw bytes of their IEEE-754
    # double representation.
    update = function(x) {
      x <- check_hashable_stream(x, "x")
      x <- x[!is.na(x)]
      if (length(x) > 0L) {
        if (is.character(x)) {
          bf_update_strings_cpp(private$ptr, x)
        } else {
          bf_update_doubles_cpp(private$ptr, x)
        }
      }
      invisible(self)
    },

    # Queries whether each element of `x` might have been seen, returning a
    # logical vector the same length as `x`. There are no false negatives;
    # `TRUE` results may be false positives at the configured `$fpp()`.
    # `NA`/`NaN`/`NA_character_` in `x` return `NA`.
    query = function(x) {
      x <- check_hashable_stream(x, "x")
      keep <- !is.na(x)
      out <- logical(length(x))
      out[!keep] <- NA
      if (any(keep)) {
        out[keep] <- if (is.character(x)) {
          bf_query_strings_cpp(private$ptr, x[keep])
        } else {
          bf_query_doubles_cpp(private$ptr, x[keep])
        }
      }
      out
    },

    # Like `$query()` followed by `$update()`, but for each element, the
    # query result reflects the filter's state *before* that element (and any
    # earlier elements of `x`) are added. `NA`/`NaN`/`NA_character_` in `x`
    # are skipped (returning `NA`, and not added to the filter).
    query_and_update = function(x) {
      x <- check_hashable_stream(x, "x")
      keep <- !is.na(x)
      out <- logical(length(x))
      out[!keep] <- NA
      if (any(keep)) {
        out[keep] <- if (is.character(x)) {
          bf_query_and_update_strings_cpp(private$ptr, x[keep])
        } else {
          bf_query_and_update_doubles_cpp(private$ptr, x[keep])
        }
      }
      out
    },

    # Mutating in-place logical OR: this filter becomes the union of itself
    # and `other`. Both filters must be "compatible" (same `seed`,
    # `num_hashes`, and `capacity`); self-merge is rejected for consistency
    # with other families.
    merge = function(other) {
      check_bloom_filter(other, "other")
      if (identical(private$ptr, bf_ptr(other))) {
        abort_invalid(
          "A filter cannot be merged into itself.",
          "datasketches_self_merge"
        )
      }
      if (!bf_is_compatible_cpp(private$ptr, bf_ptr(other))) {
        abort_invalid(
          "Cannot combine Bloom filters with different `seed`, `num_hashes`, or `capacity`.",
          "datasketches_incompatible_sketch"
        )
      }
      bf_union_cpp(private$ptr, bf_ptr(other))
      invisible(self)
    },

    # Mutating in-place logical AND: this filter becomes the intersection of
    # itself and `other`. Same compatibility requirements as `$merge()`.
    intersect = function(other) {
      check_bloom_filter(other, "other")
      if (identical(private$ptr, bf_ptr(other))) {
        abort_invalid(
          "A filter cannot be intersected with itself.",
          "datasketches_self_merge"
        )
      }
      if (!bf_is_compatible_cpp(private$ptr, bf_ptr(other))) {
        abort_invalid(
          "Cannot combine Bloom filters with different `seed`, `num_hashes`, or `capacity`.",
          "datasketches_incompatible_sketch"
        )
      }
      bf_intersect_cpp(private$ptr, bf_ptr(other))
      invisible(self)
    },

    # Mutating in-place logical NOT: flips every bit, approximately inverting
    # the notion of set membership.
    invert = function() {
      bf_invert_cpp(private$ptr)
      invisible(self)
    },

    # Resets the filter to its original (empty) state, keeping its sizing and
    # `seed`.
    reset = function() {
      bf_reset_cpp(private$ptr)
      invisible(self)
    },

    # Whether `other` may be combined with this filter via `$merge()` or
    # `$intersect()`, i.e. whether `seed`, `num_hashes`, and `capacity` match.
    is_compatible = function(other) {
      check_bloom_filter(other, "other")
      bf_is_compatible_cpp(private$ptr, bf_ptr(other))
    },

    # Total number of bits in the filter.
    capacity = function() {
      bf_get_capacity_cpp(private$ptr)
    },

    # Number of hash functions applied per item.
    num_hashes = function() {
      bf_get_num_hashes_cpp(private$ptr)
    },

    # Base hash seed.
    seed = function() {
      bf_get_seed_cpp(private$ptr)
    },

    # Number of bits currently set to 1.
    bits_used = function() {
      bf_get_bits_used_cpp(private$ptr)
    },

    is_empty = function() {
      bf_is_empty_cpp(private$ptr)
    },

    # Stable structured metadata (a plain named list).
    summary = function(...) {
      list(
        type = private$type_id,
        capacity = self$capacity(),
        num_hashes = self$num_hashes(),
        seed = self$seed(),
        bits_used = self$bits_used(),
        is_empty = self$is_empty()
      )
    },

    # Concise one-line representation (same text as `as.character()`).
    format = function(...) {
      if (self$is_empty()) {
        sprintf(
          "<bloom_filter[capacity=%s, num_hashes=%d, empty]>",
          format(self$capacity(), scientific = FALSE, trim = TRUE),
          self$num_hashes()
        )
      } else {
        sprintf(
          "<bloom_filter[capacity=%s, num_hashes=%d, bits_used=%s]>",
          format(self$capacity(), scientific = FALSE, trim = TRUE),
          self$num_hashes(),
          format(self$bits_used(), scientific = FALSE, trim = TRUE)
        )
      }
    },

    print = function(...) {
      cat("<bloom_filter>\n")
      cat(sprintf(
        "  capacity   : %s\n",
        format(self$capacity(), scientific = FALSE)
      ))
      cat(sprintf("  num_hashes : %d\n", self$num_hashes()))
      cat(sprintf(
        "  seed       : %s\n",
        format(self$seed(), scientific = FALSE)
      ))
      cat(sprintf(
        "  bits_used  : %s\n",
        format(self$bits_used(), scientific = FALSE)
      ))
      cat(sprintf("  empty      : %s\n", self$is_empty()))
      invisible(self)
    },

    # Verbose upstream debug string.
    inspect = function(items = FALSE) {
      items <- check_flag(items, "items")
      cat(bf_to_string_cpp(private$ptr, items))
      invisible(self)
    },

    serialize = function() {
      bf_serialize_cpp(private$ptr)
    },

    # Stable type id for later typed persistence (write_sketch, deferred to 0.1.1).
    sketch_type = function() {
      private$type_id
    }
  ),
  private = list(
    ptr = NULL,
    type_id = "bloom_filter"
  )
)

#' Bloom filter for approximate set membership
#'
#' Creates a
#' [Bloom filter](https://github.com/apache/datasketches-cpp/tree/master/filters),
#' a probabilistic data structure for approximate set membership. Querying an
#' item that has been added always returns `TRUE` (no false negatives);
#' querying an item that has never been added may return `TRUE` with
#' probability up to the configured false-positive probability.
#'
#' Unlike the other sketch families, a Bloom filter is not sub-linear in size:
#' it is sized up front and does not resize itself. There are two sizing
#' strategies, which cannot be combined:
#'
#' * `max_items` and `fpp` size the filter for a target number of distinct
#'   items and a target false-positive probability.
#' * `num_bits` and `num_hashes` size the filter explicitly.
#'
#' If neither strategy is specified, the filter defaults to
#' `max_items = 10000` and `fpp = 0.01`.
#'
#' At most one of `x` or `bytes` may be supplied:
#'
#' * Pass `x` to build a filter and immediately update it with a numeric or
#'   character vector of items.
#' * Pass `bytes` to reconstruct a filter from a native serialized payload (as
#'   produced by `filter$serialize()`). `max_items`, `fpp`, `num_bits`,
#'   `num_hashes`, and `seed` must not be supplied alongside `bytes`; they are
#'   restored from the payload.
#' * Pass neither for an empty (mutable) filter with the given sizing.
#'
#' `update()`, `query()`, and `query_and_update()` silently ignore (or return
#' `NA` for) `NA`/`NaN`/`NA_character_` in `x`, matching the missing-value
#' policy used across families.
#'
#' Two filters can only be combined with `$merge()` (logical OR) or
#' `$intersect()` (logical AND) if they are "compatible": they share the same
#' `seed`, `num_hashes`, and `capacity` (a mismatch raises
#' `datasketches_incompatible_sketch`).
#'
#' @param x Optional numeric or character vector of items to update the new
#'   filter with.
#' @param max_items Target maximum number of distinct items, a single positive
#'   whole number up to `2^53`. Must be supplied together with `fpp`, and
#'   cannot be combined with `num_bits`/`num_hashes`. Must not be set when
#'   `bytes` is supplied.
#' @param fpp Target false-positive probability, a single number in `(0, 1]`.
#'   Must be supplied together with `max_items`. Must not be set when `bytes`
#'   is supplied.
#' @param num_bits Number of bits in the filter, a single positive whole number
#'   up to `2^53`. Must be supplied together with `num_hashes`, and cannot be
#'   combined with `max_items`/`fpp`. Must not be set when `bytes` is supplied.
#' @param num_hashes Number of hash functions applied per item, a single whole
#'   number in `[1, 65535]`. Must be supplied together with `num_bits`. Must
#'   not be set when `bytes` is supplied.
#' @param seed Hash seed, a single non-negative whole number up to `2^53`.
#'   Defaults to `9001`. Two filters can only be combined if their `seed` (and
#'   `num_hashes` and `capacity`) match. Must not be set when `bytes` is
#'   supplied.
#' @param bytes Optional [raw] vector holding a native serialized filter to
#'   reconstruct.
#'
#' @return A `bloom_filter` object. Key methods:
#'   \describe{
#'     \item{`$update(x)`}{Add items (mutates, returns the filter).}
#'     \item{`$query(x)`}{Logical vector: might each element have been seen?}
#'     \item{`$query_and_update(x)`}{`$query()` against the prior state,
#'       then `$update()` (mutates, returns the query result).}
#'     \item{`$merge(other)`}{In-place logical OR with a compatible filter
#'       (mutates, returns the filter).}
#'     \item{`$intersect(other)`}{In-place logical AND with a compatible
#'       filter (mutates, returns the filter).}
#'     \item{`$invert()`}{In-place logical NOT (mutates, returns the
#'       filter).}
#'     \item{`$reset()`}{Clear all bits, keeping sizing and `seed` (mutates,
#'       returns the filter).}
#'     \item{`$is_compatible(other)`}{Whether `other` may be combined with
#'       this filter.}
#'     \item{`$capacity()`, `$num_hashes()`, `$seed()`, `$bits_used()`,
#'       `$is_empty()`}{Metadata accessors.}
#'     \item{`$summary()`, `$inspect()`, `$serialize()`}{Structured metadata,
#'       verbose debug output, and the native byte payload.}
#'   }
#'
#' @examples
#' bf <- bloom_filter(letters, max_items = 1000, fpp = 0.01)
#' bf$query(c("a", "z", "!"))
#'
#' # Round-trip through the native byte format.
#' restored <- bloom_filter(bytes = bf$serialize())
#' restored$query("a")
#'
#' @export
bloom_filter <- function(
  x = NULL,
  max_items = NULL,
  fpp = NULL,
  num_bits = NULL,
  num_hashes = NULL,
  seed = NULL,
  bytes = NULL
) {
  bloom_filter_generator$new(
    x = x,
    max_items = max_items,
    fpp = fpp,
    num_bits = num_bits,
    num_hashes = num_hashes,
    seed = seed,
    bytes = bytes
  )
}

#' Suggest Bloom filter sizing parameters
#'
#' Helpers that translate a target accuracy into Bloom filter constructor
#' arguments for the `num_bits`/`num_hashes` sizing strategy. These compute
#' the same values that [bloom_filter()] uses internally for the
#' `max_items`/`fpp` sizing strategy, for callers who want to inspect or reuse
#' them (for example, to create multiple compatible filters with an explicit
#' `seed`).
#'
#' @param max_items Target maximum number of distinct items, a single positive
#'   whole number up to `2^53`.
#' @param fpp Target false-positive probability, a single number in `(0, 1]`.
#' @param num_bits Number of bits in the filter, a single positive whole number
#'   up to `2^53`.
#'
#' @return A single number: `bloom_filter_suggest_num_filter_bits()` returns
#'   the suggested `num_bits` (a double, which may exceed
#'   `.Machine$integer.max`); `bloom_filter_suggest_num_hashes()` returns the
#'   suggested `num_hashes` (an integer).
#'
#' @examples
#' num_bits <- bloom_filter_suggest_num_filter_bits(1000, 0.01)
#' num_hashes <- bloom_filter_suggest_num_hashes(1000, num_bits)
#' bf <- bloom_filter(num_bits = num_bits, num_hashes = num_hashes)
#'
#' @name bloom_filter_suggest
#' @export
bloom_filter_suggest_num_filter_bits <- function(max_items, fpp) {
  max_items <- check_bloom_max_items(max_items)
  fpp <- check_bloom_fpp(fpp)
  bf_suggest_num_filter_bits_cpp(max_items, fpp)
}

#' @rdname bloom_filter_suggest
#' @export
bloom_filter_suggest_num_hashes <- function(max_items, num_bits) {
  max_items <- check_bloom_max_items(max_items)
  num_bits <- check_bloom_num_bits(num_bits)
  as.integer(bf_suggest_num_hashes_cpp(max_items, num_bits))
}
