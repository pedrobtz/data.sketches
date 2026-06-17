#include <algorithm>
#include <cstdint>
#include <string>
#include <vector>

#include <cpp11.hpp>

#include <R_ext/Utils.h> // R_CheckUserInterrupt

#include "frequent_items_sketch.hpp"
#include "native_utils.h"

namespace {

using fi_sketch_t = datasketches::frequent_items_sketch<std::string>;
using fi_sketch_ptr = cpp11::external_pointer<fi_sketch_t>;

SEXP fi_sketch_tag() {
  return Rf_install("data.sketches::frequent_items_sketch");
}

bool fi_sketch_is_valid_xptr(cpp11::sexp sketch) {
  SEXP sketch_sexp = static_cast<SEXP>(sketch);
  if (
    TYPEOF(sketch_sexp) != EXTPTRSXP ||
    R_ExternalPtrTag(sketch_sexp) != fi_sketch_tag()
  ) {
    return false;
  }

  fi_sketch_ptr ptr(sketch);
  return ptr.get() != nullptr;
}

fi_sketch_t& fi_sketch_from_xptr(cpp11::sexp sketch) {
  if (!fi_sketch_is_valid_xptr(sketch)) {
    cpp11::stop("`sketch` is not a valid Frequent Items sketch.");
  }

  fi_sketch_ptr ptr(sketch);
  return *ptr;
}

cpp11::sexp wrap_fi_sketch(fi_sketch_t&& sketch) {
  fi_sketch_ptr ptr(new fi_sketch_t(std::move(sketch)));
  SEXP out = static_cast<SEXP>(ptr);
  R_SetExternalPtrTag(out, fi_sketch_tag());
  return out;
}

} // namespace

[[cpp11::register]]
cpp11::sexp fi_create_cpp(int lg_max_map_size, int lg_start_map_size) {
  return wrap_fi_sketch(
    fi_sketch_t(
      static_cast<uint8_t>(lg_max_map_size),
      static_cast<uint8_t>(lg_start_map_size)
    )
  );
}

[[cpp11::register]]
bool fi_is_valid_cpp(cpp11::sexp sketch) {
  return fi_sketch_is_valid_xptr(sketch);
}

[[cpp11::register]]
void fi_update_cpp(cpp11::sexp sketch, cpp11::strings items, cpp11::doubles weights) {
  auto& sk = fi_sketch_from_xptr(sketch);
  const R_xlen_t n = items.size();
  const R_xlen_t m = weights.size();
  for (R_xlen_t i = 0; i < n; ++i) {
    if ((i & 0xFFFF) == 0) {
      R_CheckUserInterrupt();
    }
    const uint64_t weight =
      data_sketches_native::checked_uint64_from_double(weights[i % m], "weight");
    sk.update(static_cast<std::string>(items[i]), weight);
  }
}

// Frequent Items has a direct merge(); the other sketch may have a different
// map size.
[[cpp11::register]]
void fi_merge_cpp(cpp11::sexp sketch, cpp11::sexp other) {
  auto& sk = fi_sketch_from_xptr(sketch);
  auto& other_sk = fi_sketch_from_xptr(other);
  sk.merge(other_sk);
}

[[cpp11::register]]
bool fi_is_empty_cpp(cpp11::sexp sketch) {
  return fi_sketch_from_xptr(sketch).is_empty();
}

[[cpp11::register]]
double fi_get_num_active_items_cpp(cpp11::sexp sketch) {
  return static_cast<double>(fi_sketch_from_xptr(sketch).get_num_active_items());
}

[[cpp11::register]]
double fi_get_total_weight_cpp(cpp11::sexp sketch) {
  return static_cast<double>(fi_sketch_from_xptr(sketch).get_total_weight());
}

[[cpp11::register]]
double fi_get_maximum_error_cpp(cpp11::sexp sketch) {
  return static_cast<double>(fi_sketch_from_xptr(sketch).get_maximum_error());
}

[[cpp11::register]]
double fi_get_epsilon_cpp(cpp11::sexp sketch) {
  return fi_sketch_from_xptr(sketch).get_epsilon();
}

[[cpp11::register]]
cpp11::doubles fi_get_estimate_cpp(cpp11::sexp sketch, cpp11::strings items) {
  auto& sk = fi_sketch_from_xptr(sketch);
  const R_xlen_t n = items.size();
  cpp11::writable::doubles out(n);
  for (R_xlen_t i = 0; i < n; ++i) {
    out[i] = static_cast<double>(sk.get_estimate(static_cast<std::string>(items[i])));
  }
  return out;
}

[[cpp11::register]]
cpp11::doubles fi_get_lower_bound_cpp(cpp11::sexp sketch, cpp11::strings items) {
  auto& sk = fi_sketch_from_xptr(sketch);
  const R_xlen_t n = items.size();
  cpp11::writable::doubles out(n);
  for (R_xlen_t i = 0; i < n; ++i) {
    out[i] = static_cast<double>(sk.get_lower_bound(static_cast<std::string>(items[i])));
  }
  return out;
}

[[cpp11::register]]
cpp11::doubles fi_get_upper_bound_cpp(cpp11::sexp sketch, cpp11::strings items) {
  auto& sk = fi_sketch_from_xptr(sketch);
  const R_xlen_t n = items.size();
  cpp11::writable::doubles out(n);
  for (R_xlen_t i = 0; i < n; ++i) {
    out[i] = static_cast<double>(sk.get_upper_bound(static_cast<std::string>(items[i])));
  }
  return out;
}

// Returns a list with parallel `item`/`estimate`/`lower_bound`/`upper_bound`
// vectors, suitable for `as.data.frame()`. `threshold` is `NA` to use the
// sketch's own `get_maximum_error()` as the threshold.
[[cpp11::register]]
cpp11::list fi_get_frequent_items_cpp(cpp11::sexp sketch, int err_type, cpp11::doubles threshold) {
  auto& sk = fi_sketch_from_xptr(sketch);
  const auto error_type = static_cast<datasketches::frequent_items_error_type>(err_type);

  auto rows = (threshold.size() == 1 && !ISNA(threshold[0]))
    ? sk.get_frequent_items(
        error_type,
        data_sketches_native::checked_uint64_from_double(threshold[0], "threshold")
      )
    : sk.get_frequent_items(error_type);

  const size_t n = rows.size();
  cpp11::writable::strings items(n);
  cpp11::writable::doubles estimates(n);
  cpp11::writable::doubles lower_bounds(n);
  cpp11::writable::doubles upper_bounds(n);
  for (size_t i = 0; i < n; ++i) {
    items[i] = rows[i].get_item();
    estimates[i] = static_cast<double>(rows[i].get_estimate());
    lower_bounds[i] = static_cast<double>(rows[i].get_lower_bound());
    upper_bounds[i] = static_cast<double>(rows[i].get_upper_bound());
  }

  using namespace cpp11::literals;
  cpp11::writable::list out;
  out.push_back("item"_nm = items);
  out.push_back("estimate"_nm = estimates);
  out.push_back("lower_bound"_nm = lower_bounds);
  out.push_back("upper_bound"_nm = upper_bounds);
  return out;
}

[[cpp11::register]]
std::string fi_to_string_cpp(cpp11::sexp sketch, bool print_items) {
  return fi_sketch_from_xptr(sketch).to_string(print_items);
}

[[cpp11::register]]
cpp11::raws fi_serialize_cpp(cpp11::sexp sketch) {
  auto bytes = fi_sketch_from_xptr(sketch).serialize();
  cpp11::writable::raws out(bytes.size());
  std::copy(bytes.begin(), bytes.end(), out.begin());
  return out;
}

[[cpp11::register]]
cpp11::sexp fi_deserialize_cpp(cpp11::raws bytes) {
  std::vector<uint8_t> buffer(bytes.begin(), bytes.end());
  return wrap_fi_sketch(fi_sketch_t::deserialize(buffer.data(), buffer.size()));
}
