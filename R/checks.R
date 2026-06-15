# Internal Tier-1 validators for the public sketch surfaces. These run in R
# before any value crosses the cpp11 bridge, so bad user input is reported by R
# with a stable classed condition instead of flattening through the C++ glue.
# See `_dev/WORKING-ON.md` (Validation Contract).
# All conditions inherit `datasketches_error`; none of these are exported.

# Shared raiser: keeps every validator's condition shape identical.
abort_invalid <- function(message, class, call = rlang::caller_env()) {
  rlang::abort(message, class = c(class, "datasketches_error"), call = call)
}

.datasketches_max_safe_uint64 <- 2^53

check_uint64ish <- function(
  x,
  lengths,
  min,
  message,
  class,
  call = rlang::caller_env()
) {
  if (
    !is.numeric(x) ||
      length(x) == 0L ||
      !(length(x) %in% lengths)
  ) {
    abort_invalid(message, class, call = call)
  }

  x <- as.double(x)
  if (
    anyNA(x) ||
      any(!is.finite(x)) ||
      any(x != trunc(x)) ||
      any(x < min) ||
      any(x > .datasketches_max_safe_uint64)
  ) {
    abort_invalid(message, class, call = call)
  }

  x
}

# Sketch width `k`. Mirrors `checked_k()` in `src/kll_doubles.cpp` exactly so a
# bad `k` never reaches C++. Returns an integer suitable for the bridge.
check_k <- function(k, call = rlang::caller_env()) {
  if (
    !is.numeric(k) ||
      length(k) != 1L ||
      is.na(k) ||
      k != trunc(k) ||
      k < 8 ||
      k > 65535
  ) {
    abort_invalid(
      "`k` must be a single whole number between 8 and 65535.",
      "datasketches_invalid_k",
      call = call
    )
  }
  as.integer(k)
}

# A numeric stream to `update()`. `NA`/`NaN` are allowed here — the C++
# `kll_sketch::update()` silently skips them (documented behaviour). Integer
# input is coerced to double. Returns a double vector.
check_numeric_stream <- function(x, arg = "x", call = rlang::caller_env()) {
  if (!is.numeric(x)) {
    abort_invalid(
      sprintf("`%s` must be a numeric vector.", arg),
      "datasketches_invalid_input",
      call = call
    )
  }
  as.double(x)
}

# Probabilities for `quantile()`. Each must be in [0, 1] and non-missing: a
# missing probability is a validation error, not an `NA` result. Returns double.
check_probs <- function(probs, arg = "probs", call = rlang::caller_env()) {
  if (!is.numeric(probs)) {
    abort_invalid(
      sprintf("`%s` must be a numeric vector.", arg),
      "datasketches_invalid_prob",
      call = call
    )
  }
  probs <- as.double(probs)
  if (anyNA(probs) || any(probs < 0 | probs > 1)) {
    abort_invalid(
      sprintf("`%s` must contain finite probabilities in [0, 1].", arg),
      "datasketches_invalid_prob",
      call = call
    )
  }
  probs
}

# Split points for `cdf()` / `pmf()`. Must be non-missing, finite, and strictly
# increasing (the upstream contract). Returns double.
check_split_points <- function(
  split_points,
  arg = "split_points",
  call = rlang::caller_env()
) {
  if (!is.numeric(split_points)) {
    abort_invalid(
      sprintf("`%s` must be a numeric vector.", arg),
      "datasketches_invalid_split_points",
      call = call
    )
  }
  split_points <- as.double(split_points)
  if (length(split_points) < 1L) {
    abort_invalid(
      sprintf("`%s` must have at least one value.", arg),
      "datasketches_invalid_split_points",
      call = call
    )
  }
  if (anyNA(split_points) || any(!is.finite(split_points))) {
    abort_invalid(
      sprintf("`%s` must be finite and non-missing.", arg),
      "datasketches_invalid_split_points",
      call = call
    )
  }
  if (length(split_points) > 1L && any(diff(split_points) <= 0)) {
    abort_invalid(
      sprintf("`%s` must be strictly increasing.", arg),
      "datasketches_invalid_split_points",
      call = call
    )
  }
  split_points
}

# A logical flag (`inclusive`, `pmf`, `levels`, `items`). Returns the scalar.
check_flag <- function(x, arg, call = rlang::caller_env()) {
  if (!is.logical(x) || length(x) != 1L || is.na(x)) {
    abort_invalid(
      sprintf("`%s` must be a single `TRUE` or `FALSE`.", arg),
      "datasketches_invalid_flag",
      call = call
    )
  }
  x
}

# A KLL doubles sketch instance (the `merge()` argument). Returns invisibly.
check_kll_doubles <- function(x, arg = "other", call = rlang::caller_env()) {
  if (!is_kll_doubles(x)) {
    abort_invalid(
      sprintf("`%s` must be a <kll_doubles_sketch> object.", arg),
      "datasketches_invalid_sketch",
      call = call
    )
  }
  invisible(x)
}

# Internal predicate; not part of the public API.
is_kll_doubles <- function(x) {
  if (!inherits(x, "kll_doubles_sketch") || !is.environment(x)) {
    return(FALSE)
  }

  ptr <- tryCatch(kll_doubles_ptr(x), error = \(.x) NULL)
  !is.null(ptr) && kll_doubles_is_valid_cpp(ptr)
}

# A KLL floats sketch instance (the `merge()` argument). Returns invisibly.
check_kll_floats <- function(x, arg = "other", call = rlang::caller_env()) {
  if (!is_kll_floats(x)) {
    abort_invalid(
      sprintf("`%s` must be a <kll_floats_sketch> object.", arg),
      "datasketches_invalid_sketch",
      call = call
    )
  }
  invisible(x)
}

# Internal predicate; not part of the public API.
is_kll_floats <- function(x) {
  if (!inherits(x, "kll_floats_sketch") || !is.environment(x)) {
    return(FALSE)
  }

  ptr <- tryCatch(kll_floats_ptr(x), error = \(.x) NULL)
  !is.null(ptr) && kll_floats_is_valid_cpp(ptr)
}

# Sketch width `k` for REQ. Mirrors `checked_k()` in `src/req_sketch.cpp`:
# must be even and in [4, 1024]. Returns an integer suitable for the bridge.
check_req_k <- function(k, call = rlang::caller_env()) {
  if (
    !is.numeric(k) ||
      length(k) != 1L ||
      is.na(k) ||
      k != trunc(k) ||
      k < 4 ||
      k > 1024 ||
      (k %% 2) != 0
  ) {
    abort_invalid(
      "`k` must be a single even whole number between 4 and 1024.",
      "datasketches_invalid_k",
      call = call
    )
  }
  as.integer(k)
}

# `num_std_dev` for REQ rank bound queries. Must be 1, 2, or 3.
check_num_std_dev <- function(x, call = rlang::caller_env()) {
  if (
    !is.numeric(x) ||
      length(x) != 1L ||
      is.na(x) ||
      !(x %in% c(1, 2, 3))
  ) {
    abort_invalid(
      "`num_std_dev` must be a single value in `c(1, 2, 3)`.",
      "datasketches_invalid_num_std_dev",
      call = call
    )
  }
  as.integer(x)
}

# A REQ sketch instance (the `merge()` argument). Returns invisibly.
check_req <- function(x, arg = "other", call = rlang::caller_env()) {
  if (!is_req(x)) {
    abort_invalid(
      sprintf("`%s` must be a <req_sketch> object.", arg),
      "datasketches_invalid_sketch",
      call = call
    )
  }
  invisible(x)
}

# Internal predicate; not part of the public API.
is_req <- function(x) {
  if (!inherits(x, "req_sketch") || !is.environment(x)) {
    return(FALSE)
  }

  ptr <- tryCatch(req_ptr(x), error = \(.x) NULL)
  !is.null(ptr) && req_is_valid_cpp(ptr)
}

# `lg_k` (log2 of the number of buckets/slots), shared across the
# hash-sketch families (HLL, CPC, Theta). Bounds differ per family, so the
# caller supplies them; defaults are HLL's [4, 21]. Returns an integer.
check_lg_k <- function(lg_k, min = 4L, max = 21L, call = rlang::caller_env()) {
  if (
    !is.numeric(lg_k) ||
      length(lg_k) != 1L ||
      is.na(lg_k) ||
      lg_k != trunc(lg_k) ||
      lg_k < min ||
      lg_k > max
  ) {
    abort_invalid(
      sprintf(
        "`lg_k` must be a single whole number between %d and %d.",
        min,
        max
      ),
      "datasketches_invalid_lg_k",
      call = call
    )
  }
  as.integer(lg_k)
}

# HLL target encoding (`HLL_4`, `HLL_6`, `HLL_8`). Returns the integer enum
# value expected by `hll_create_cpp()` (HLL_4 = 0, HLL_6 = 1, HLL_8 = 2).
check_hll_type <- function(type, call = rlang::caller_env()) {
  choices <- c(HLL_4 = 0L, HLL_6 = 1L, HLL_8 = 2L)
  if (
    !is.character(type) ||
      length(type) != 1L ||
      is.na(type) ||
      !(type %in% names(choices))
  ) {
    abort_invalid(
      "`type` must be one of \"HLL_4\", \"HLL_6\", or \"HLL_8\".",
      "datasketches_invalid_type",
      call = call
    )
  }
  choices[[type]]
}

# A stream to `update()` for hash-based sketches (HLL, CPC, Theta). Unlike
# `check_numeric_stream()`, character input is also accepted (each element is
# hashed as a string). Returns the vector unchanged in type (numeric is
# coerced to double); `NA`s are left in place for the caller to filter.
check_hashable_stream <- function(x, arg = "x", call = rlang::caller_env()) {
  if (is.numeric(x)) {
    return(as.double(x))
  }
  if (is.character(x)) {
    return(x)
  }
  abort_invalid(
    sprintf("`%s` must be a numeric or character vector.", arg),
    "datasketches_invalid_input",
    call = call
  )
}

# An HLL sketch instance (the `merge()` argument). Returns invisibly.
check_hll <- function(x, arg = "other", call = rlang::caller_env()) {
  if (!is_hll(x)) {
    abort_invalid(
      sprintf("`%s` must be a <hll_sketch> object.", arg),
      "datasketches_invalid_sketch",
      call = call
    )
  }
  invisible(x)
}

# Internal predicate; not part of the public API.
is_hll <- function(x) {
  if (!inherits(x, "hll_sketch") || !is.environment(x)) {
    return(FALSE)
  }

  ptr <- tryCatch(hll_ptr(x), error = \(.x) NULL)
  !is.null(ptr) && hll_is_valid_cpp(ptr)
}

# `seed` for seeded hash-sketch families (CPC, Theta, Tuple). The native
# `uint64_t` is represented as an R double, so only exact whole numbers up to
# `2^53` are accepted. Returns a double suitable for the bridge.
check_seed <- function(seed, call = rlang::caller_env()) {
  check_uint64ish(
    seed,
    lengths = 1L,
    min = 0,
    message = "`seed` must be a single non-negative whole number up to 2^53.",
    class = "datasketches_invalid_seed",
    call = call
  )
}

# A CPC sketch instance (the `merge()` argument). Returns invisibly.
check_cpc <- function(x, arg = "other", call = rlang::caller_env()) {
  if (!is_cpc(x)) {
    abort_invalid(
      sprintf("`%s` must be a <cpc_sketch> object.", arg),
      "datasketches_invalid_sketch",
      call = call
    )
  }
  invisible(x)
}

# Internal predicate; not part of the public API.
is_cpc <- function(x) {
  if (!inherits(x, "cpc_sketch") || !is.environment(x)) {
    return(FALSE)
  }

  ptr <- tryCatch(cpc_ptr(x), error = \(.x) NULL)
  !is.null(ptr) && cpc_is_valid_cpp(ptr)
}

# A Theta sketch instance (the `merge()` / set-operation arguments). Returns
# invisibly.
check_theta <- function(x, arg = "other", call = rlang::caller_env()) {
  if (!is_theta(x)) {
    abort_invalid(
      sprintf("`%s` must be a <theta_sketch> object.", arg),
      "datasketches_invalid_sketch",
      call = call
    )
  }
  invisible(x)
}

# Internal predicate; not part of the public API.
is_theta <- function(x) {
  if (!inherits(x, "theta_sketch") || !is.environment(x)) {
    return(FALSE)
  }

  ptr <- tryCatch(theta_ptr(x), error = \(.x) NULL)
  !is.null(ptr) && theta_is_valid_cpp(ptr)
}

# `lg_max_map_size`/`lg_start_map_size` for the Frequent Items sketch. Both
# are log2 sizes of the internal hash map; `lg_max_map_size` is bounded to a
# practical range, and `lg_start_map_size` must not exceed it (mirrors the
# `std::invalid_argument` the native constructor would otherwise throw).
check_lg_max_map_size <- function(lg_max_map_size, call = rlang::caller_env()) {
  check_lg_k(lg_max_map_size, min = 3L, max = 30L, call = call)
}

check_lg_start_map_size <- function(
  lg_start_map_size,
  lg_max_map_size,
  call = rlang::caller_env()
) {
  lg_start_map_size <- check_lg_k(
    lg_start_map_size,
    min = 3L,
    max = 30L,
    call = call
  )
  if (lg_start_map_size > lg_max_map_size) {
    abort_invalid(
      "`lg_start_map_size` must not be greater than `lg_max_map_size`.",
      "datasketches_invalid_lg_k",
      call = call
    )
  }
  lg_start_map_size
}

# A non-negative whole-number weight for `update()`. May be a single value
# (recycled) or a vector matching the length of `x`. As with other native
# `uint64_t` inputs, only exact whole numbers up to `2^53` are accepted.
# Returns a double vector.
check_weight <- function(weight, n, call = rlang::caller_env()) {
  check_uint64ish(
    weight,
    lengths = c(1L, n),
    min = 0,
    message = "`weight` must be a non-negative whole number up to 2^53, or a vector of such values matching the length of `x`.",
    class = "datasketches_invalid_weight",
    call = call
  )
}

# The `error_type` argument for `$frequent_items()`. Returns the integer enum
# value expected by `fi_get_frequent_items_cpp()` (NO_FALSE_POSITIVES = 0,
# NO_FALSE_NEGATIVES = 1).
check_fi_error_type <- function(error_type, call = rlang::caller_env()) {
  choices <- c(no_false_positives = 0L, no_false_negatives = 1L)
  if (
    !is.character(error_type) ||
      length(error_type) != 1L ||
      is.na(error_type) ||
      !(error_type %in% names(choices))
  ) {
    abort_invalid(
      "`error_type` must be one of \"no_false_positives\" or \"no_false_negatives\".",
      "datasketches_invalid_error_type",
      call = call
    )
  }
  choices[[error_type]]
}

# A Frequent Items sketch instance (the `merge()` argument). Returns
# invisibly.
check_frequent_items <- function(x, arg = "other", call = rlang::caller_env()) {
  if (!is_frequent_items(x)) {
    abort_invalid(
      sprintf("`%s` must be a <frequent_items_sketch> object.", arg),
      "datasketches_invalid_sketch",
      call = call
    )
  }
  invisible(x)
}

# Internal predicate; not part of the public API.
is_frequent_items <- function(x) {
  if (!inherits(x, "frequent_items_sketch") || !is.environment(x)) {
    return(FALSE)
  }

  ptr <- tryCatch(fi_ptr(x), error = \(.x) NULL)
  !is.null(ptr) && fi_is_valid_cpp(ptr)
}

# `num_hashes` for Count-Min. Mirrors the native `uint8_t` parameter: a single
# whole number in [1, 255]. Returns an integer.
check_num_hashes <- function(num_hashes, call = rlang::caller_env()) {
  if (
    !is.numeric(num_hashes) ||
      length(num_hashes) != 1L ||
      is.na(num_hashes) ||
      num_hashes != trunc(num_hashes) ||
      num_hashes < 1 ||
      num_hashes > 255
  ) {
    abort_invalid(
      "`num_hashes` must be a single whole number between 1 and 255.",
      "datasketches_invalid_num_hashes",
      call = call
    )
  }
  as.integer(num_hashes)
}

# `num_buckets` for Count-Min. Mirrors the native constructor: a single whole
# number of at least 3 (fewer buckets give relative error > 1). The combined
# `num_hashes * num_buckets < 2^30` bound (also enforced natively) is checked
# once both values are known. Returns an integer.
check_num_buckets <- function(
  num_buckets,
  num_hashes,
  call = rlang::caller_env()
) {
  if (
    !is.numeric(num_buckets) ||
      length(num_buckets) != 1L ||
      is.na(num_buckets) ||
      num_buckets != trunc(num_buckets) ||
      num_buckets < 3
  ) {
    abort_invalid(
      "`num_buckets` must be a single whole number of at least 3.",
      "datasketches_invalid_num_buckets",
      call = call
    )
  }
  if (as.double(num_buckets) * as.double(num_hashes) >= 2^30) {
    abort_invalid(
      "`num_buckets * num_hashes` must be less than 2^30.",
      "datasketches_invalid_num_buckets",
      call = call
    )
  }
  as.integer(num_buckets)
}

# `relative_error` for `count_min_suggest_num_buckets()`. A single positive,
# finite number.
check_relative_error <- function(relative_error, call = rlang::caller_env()) {
  if (
    !is.numeric(relative_error) ||
      length(relative_error) != 1L ||
      is.na(relative_error) ||
      !is.finite(relative_error) ||
      relative_error <= 0
  ) {
    abort_invalid(
      "`relative_error` must be a single positive number.",
      "datasketches_invalid_relative_error",
      call = call
    )
  }
  as.double(relative_error)
}

# `confidence` for `count_min_suggest_num_hashes()`. A single number in (0, 1].
check_confidence <- function(confidence, call = rlang::caller_env()) {
  if (
    !is.numeric(confidence) ||
      length(confidence) != 1L ||
      is.na(confidence) ||
      confidence <= 0 ||
      confidence > 1
  ) {
    abort_invalid(
      "`confidence` must be a single number in (0, 1].",
      "datasketches_invalid_confidence",
      call = call
    )
  }
  as.double(confidence)
}

# A non-missing, finite weight for `update()`. May be a single value
# (recycled) or a vector matching the length of `x`. Unlike
# `check_weight()` (Frequent Items), Count-Min weights may be negative or
# fractional. Returns a double vector.
check_cm_weight <- function(weight, n, call = rlang::caller_env()) {
  if (
    !is.numeric(weight) ||
      length(weight) == 0L ||
      !(length(weight) %in% c(1L, n)) ||
      anyNA(weight) ||
      any(!is.finite(weight))
  ) {
    abort_invalid(
      "`weight` must be a finite, non-missing number, or a vector of such values matching the length of `x`.",
      "datasketches_invalid_weight",
      call = call
    )
  }
  as.double(weight)
}

# A non-missing item for `$estimate()`/`$lower_bound()`/`$upper_bound()`.
# Unlike `check_hashable_stream()` (used for `update()`), missing values are
# rejected here since there is no sensible "estimate of NA".
check_query_item <- function(item, arg = "item", call = rlang::caller_env()) {
  item <- check_hashable_stream(item, arg = arg, call = call)
  if (anyNA(item)) {
    abort_invalid(
      sprintf("`%s` must not contain missing values.", arg),
      "datasketches_invalid_input",
      call = call
    )
  }
  item
}

# A Count-Min sketch instance (the `merge()` argument). Returns invisibly.
check_count_min <- function(x, arg = "other", call = rlang::caller_env()) {
  if (!is_count_min(x)) {
    abort_invalid(
      sprintf("`%s` must be a <count_min_sketch> object.", arg),
      "datasketches_invalid_sketch",
      call = call
    )
  }
  invisible(x)
}

# Internal predicate; not part of the public API.
is_count_min <- function(x) {
  if (!inherits(x, "count_min_sketch") || !is.environment(x)) {
    return(FALSE)
  }

  ptr <- tryCatch(cm_ptr(x), error = \(.x) NULL)
  !is.null(ptr) && cm_is_valid_cpp(ptr)
}

# `num_values` for Array of Doubles. Mirrors the native `uint8_t` parameter: a
# single whole number in [1, 255]. Returns an integer.
check_num_values <- function(num_values, call = rlang::caller_env()) {
  if (
    !is.numeric(num_values) ||
      length(num_values) != 1L ||
      is.na(num_values) ||
      num_values != trunc(num_values) ||
      num_values < 1 ||
      num_values > 255
  ) {
    abort_invalid(
      "`num_values` must be a single whole number between 1 and 255.",
      "datasketches_invalid_num_values",
      call = call
    )
  }
  as.integer(num_values)
}

# `values` for `update()`: a numeric vector (when `num_values == 1`) or a
# numeric matrix with `num_values` columns, recycled to `n` rows if a single
# row/value is supplied. Returns an `n x num_values` numeric matrix.
check_aod_values <- function(
  values,
  n,
  num_values,
  call = rlang::caller_env()
) {
  if (!is.numeric(values)) {
    abort_invalid(
      "`values` must be numeric.",
      "datasketches_invalid_input",
      call = call
    )
  }
  if (is.matrix(values)) {
    if (ncol(values) != num_values) {
      abort_invalid(
        sprintf("`values` must have `num_values` (%d) columns.", num_values),
        "datasketches_invalid_input",
        call = call
      )
    }
    if (nrow(values) == 1L && n != 1L) {
      values <- values[rep(1L, n), , drop = FALSE]
    } else if (nrow(values) != n) {
      abort_invalid(
        "`values` must have one row per element of `x`, or a single row to recycle.",
        "datasketches_invalid_input",
        call = call
      )
    }
  } else {
    if (num_values != 1L) {
      abort_invalid(
        sprintf(
          "`values` must be a matrix with `num_values` (%d) columns.",
          num_values
        ),
        "datasketches_invalid_input",
        call = call
      )
    }
    if (length(values) == 1L && n != 1L) {
      values <- rep(values, n)
    } else if (length(values) != n) {
      abort_invalid(
        "`values` must be a single value or a vector matching the length of `x`.",
        "datasketches_invalid_input",
        call = call
      )
    }
    values <- matrix(values, ncol = 1L)
  }
  if (anyNA(values) || any(!is.finite(values))) {
    abort_invalid(
      "`values` must contain finite, non-missing numbers.",
      "datasketches_invalid_input",
      call = call
    )
  }
  matrix(as.double(values), ncol = num_values)
}

# An Array of Doubles sketch instance (the `merge()` / set-operation
# arguments). Returns invisibly.
check_array_of_doubles <- function(
  x,
  arg = "other",
  call = rlang::caller_env()
) {
  if (!is_array_of_doubles(x)) {
    abort_invalid(
      sprintf("`%s` must be a <array_of_doubles_sketch> object.", arg),
      "datasketches_invalid_sketch",
      call = call
    )
  }
  invisible(x)
}

# Internal predicate; not part of the public API.
is_array_of_doubles <- function(x) {
  if (!inherits(x, "array_of_doubles_sketch") || !is.environment(x)) {
    return(FALSE)
  }

  ptr <- tryCatch(aod_ptr(x), error = \(.x) NULL)
  !is.null(ptr) && aod_is_valid_cpp(ptr)
}

# `k` for VarOpt: a single whole number in `[1, 2^31 - 2]` (the native
# `var_opt_constants::MAX_K`). Returns an integer.
check_varopt_k <- function(k, call = rlang::caller_env()) {
  max_k <- 2147483646
  if (
    !is.numeric(k) ||
      length(k) != 1L ||
      is.na(k) ||
      k != trunc(k) ||
      k < 1 ||
      k > max_k
  ) {
    abort_invalid(
      sprintf("`k` must be a single whole number between 1 and %d.", max_k),
      "datasketches_invalid_k",
      call = call
    )
  }
  as.integer(k)
}

# `type` for VarOpt: the item type of a fresh sketch, either "double" or
# "character".
check_varopt_type <- function(type, call = rlang::caller_env()) {
  if (
    !is.character(type) ||
      length(type) != 1L ||
      is.na(type) ||
      !(type %in% c("double", "character"))
  ) {
    abort_invalid(
      "`type` must be \"double\" or \"character\".",
      "datasketches_invalid_type",
      call = call
    )
  }
  type
}

# `weight` for VarOpt `update()`. Mirrors the native constraint (rejects
# negative, missing, `NaN`, or infinite weights; zero is allowed). Returns a
# double vector.
check_varopt_weight <- function(weight, n, call = rlang::caller_env()) {
  if (
    !is.numeric(weight) ||
      length(weight) == 0L ||
      !(length(weight) %in% c(1L, n)) ||
      anyNA(weight) ||
      any(!is.finite(weight)) ||
      any(weight < 0)
  ) {
    abort_invalid(
      "`weight` must be a non-negative, finite number, or a vector of such values matching the length of `x`.",
      "datasketches_invalid_weight",
      call = call
    )
  }
  as.double(weight)
}

# A VarOpt sketch instance (the `merge()` / set-operation arguments). Returns
# invisibly.
check_varopt <- function(x, arg = "other", call = rlang::caller_env()) {
  if (!is_varopt(x)) {
    abort_invalid(
      sprintf("`%s` must be a <varopt_sketch> object.", arg),
      "datasketches_invalid_sketch",
      call = call
    )
  }
  invisible(x)
}

# Internal predicate; not part of the public API.
is_varopt <- function(x) {
  if (!inherits(x, "varopt_sketch") || !is.environment(x)) {
    return(FALSE)
  }

  ptr <- tryCatch(vo_ptr(x), error = \(.x) NULL)
  !is.null(ptr) && vo_is_valid_cpp(ptr)
}

# `k` for EBPPS: a single whole number in `[1, 2^31 - 2]` (the native
# `ebpps_constants::MAX_K`). Returns an integer.
check_ebpps_k <- function(k, call = rlang::caller_env()) {
  max_k <- 2147483646
  if (
    !is.numeric(k) ||
      length(k) != 1L ||
      is.na(k) ||
      k != trunc(k) ||
      k < 1 ||
      k > max_k
  ) {
    abort_invalid(
      sprintf("`k` must be a single whole number between 1 and %d.", max_k),
      "datasketches_invalid_k",
      call = call
    )
  }
  as.integer(k)
}

# `type` for EBPPS: the item type of a fresh sketch, either "double" or
# "character".
check_ebpps_type <- function(type, call = rlang::caller_env()) {
  if (
    !is.character(type) ||
      length(type) != 1L ||
      is.na(type) ||
      !(type %in% c("double", "character"))
  ) {
    abort_invalid(
      "`type` must be \"double\" or \"character\".",
      "datasketches_invalid_type",
      call = call
    )
  }
  type
}

# `weight` for EBPPS `update()`. Mirrors the native constraint (rejects
# negative, missing, `NaN`, or infinite weights; zero is allowed). Returns a
# double vector.
check_ebpps_weight <- function(weight, n, call = rlang::caller_env()) {
  if (
    !is.numeric(weight) ||
      length(weight) == 0L ||
      !(length(weight) %in% c(1L, n)) ||
      anyNA(weight) ||
      any(!is.finite(weight)) ||
      any(weight < 0)
  ) {
    abort_invalid(
      "`weight` must be a non-negative, finite number, or a vector of such values matching the length of `x`.",
      "datasketches_invalid_weight",
      call = call
    )
  }
  as.double(weight)
}

# An EBPPS sketch instance (the `merge()` argument). Returns invisibly.
check_ebpps <- function(x, arg = "other", call = rlang::caller_env()) {
  if (!is_ebpps(x)) {
    abort_invalid(
      sprintf("`%s` must be a <ebpps_sketch> object.", arg),
      "datasketches_invalid_sketch",
      call = call
    )
  }
  invisible(x)
}

# Internal predicate; not part of the public API.
is_ebpps <- function(x) {
  if (!inherits(x, "ebpps_sketch") || !is.environment(x)) {
    return(FALSE)
  }

  ptr <- tryCatch(eb_ptr(x), error = \(.x) NULL)
  !is.null(ptr) && eb_is_valid_cpp(ptr)
}

# `max_items` for a Bloom filter sized by accuracy: a single positive whole
# number up to `2^53`. Returns a double (the native side takes a `uint64_t`,
# which may exceed `.Machine$integer.max`).
check_bloom_max_items <- function(max_items, call = rlang::caller_env()) {
  check_uint64ish(
    max_items,
    lengths = 1L,
    min = 1,
    message = "`max_items` must be a single positive whole number up to 2^53.",
    class = "datasketches_invalid_max_items",
    call = call
  )
}

# `fpp` (target false-positive probability) for a Bloom filter sized by
# accuracy: a single number in (0, 1].
check_bloom_fpp <- function(fpp, call = rlang::caller_env()) {
  if (
    !is.numeric(fpp) ||
      length(fpp) != 1L ||
      is.na(fpp) ||
      fpp <= 0 ||
      fpp > 1
  ) {
    abort_invalid(
      "`fpp` must be a single number in (0, 1].",
      "datasketches_invalid_fpp",
      call = call
    )
  }
  as.double(fpp)
}

# `num_bits` for a Bloom filter sized explicitly: a single positive whole
# number up to `2^53`. Returns a double (the native side takes a `uint64_t`,
# which may exceed `.Machine$integer.max`); the native `MAX_FILTER_SIZE_BITS`
# upper bound is enforced natively.
check_bloom_num_bits <- function(num_bits, call = rlang::caller_env()) {
  check_uint64ish(
    num_bits,
    lengths = 1L,
    min = 1,
    message = "`num_bits` must be a single positive whole number up to 2^53.",
    class = "datasketches_invalid_num_bits",
    call = call
  )
}

# `num_hashes` for a Bloom filter sized explicitly: a single whole number in
# `[1, 65535]` (the native `uint16_t` range). Returns an integer.
check_bloom_num_hashes <- function(num_hashes, call = rlang::caller_env()) {
  if (
    !is.numeric(num_hashes) ||
      length(num_hashes) != 1L ||
      is.na(num_hashes) ||
      num_hashes != trunc(num_hashes) ||
      num_hashes < 1 ||
      num_hashes > 65535
  ) {
    abort_invalid(
      "`num_hashes` must be a single whole number between 1 and 65535.",
      "datasketches_invalid_num_hashes",
      call = call
    )
  }
  as.integer(num_hashes)
}

# A Bloom filter instance (the `merge()` / `intersect()` arguments). Returns
# invisibly.
check_bloom_filter <- function(x, arg = "other", call = rlang::caller_env()) {
  if (!is_bloom_filter(x)) {
    abort_invalid(
      sprintf("`%s` must be a <bloom_filter> object.", arg),
      "datasketches_invalid_sketch",
      call = call
    )
  }
  invisible(x)
}

# Internal predicate; not part of the public API.
is_bloom_filter <- function(x) {
  if (!inherits(x, "bloom_filter") || !is.environment(x)) {
    return(FALSE)
  }

  ptr <- tryCatch(bf_ptr(x), error = \(.x) NULL)
  !is.null(ptr) && bf_is_valid_cpp(ptr)
}

# Sketch width `k` for t-Digest. The native constructor accepts any `uint16_t`,
# but values below 10 give the scale function a zero/negative normalizer and
# effectively disable compression; the vendored reference-format deserializer
# itself rejects `k < 10`. Returns an integer suitable for the bridge.
check_tdigest_k <- function(k, call = rlang::caller_env()) {
  if (
    !is.numeric(k) ||
      length(k) != 1L ||
      is.na(k) ||
      k != trunc(k) ||
      k < 10 ||
      k > 65535
  ) {
    abort_invalid(
      "`k` must be a single whole number between 10 and 65535.",
      "datasketches_invalid_k",
      call = call
    )
  }
  as.integer(k)
}

# A t-Digest double sketch instance (the `merge()` argument). Returns
# invisibly.
check_tdigest_double <- function(x, arg = "other", call = rlang::caller_env()) {
  if (!is_tdigest_double(x)) {
    abort_invalid(
      sprintf("`%s` must be a <tdigest_double_sketch> object.", arg),
      "datasketches_invalid_sketch",
      call = call
    )
  }
  invisible(x)
}

# Internal predicate; not part of the public API.
is_tdigest_double <- function(x) {
  if (!inherits(x, "tdigest_double_sketch") || !is.environment(x)) {
    return(FALSE)
  }

  ptr <- tryCatch(td_ptr(x), error = \(.x) NULL)
  !is.null(ptr) && td_is_valid_cpp(ptr)
}
