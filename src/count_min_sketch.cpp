#include <algorithm>
#include <cstdint>
#include <sstream>
#include <string>
#include <vector>

#include <cpp11.hpp>

#include <R_ext/Utils.h> // R_CheckUserInterrupt

#include "count_min.hpp"
#include "native_utils.h"

namespace {

using cm_sketch_t = datasketches::count_min_sketch<double>;
using cm_sketch_ptr = cpp11::external_pointer<cm_sketch_t>;

SEXP cm_sketch_tag() {
  return Rf_install("data.sketches::count_min_sketch");
}

bool cm_sketch_is_valid_xptr(cpp11::sexp sketch) {
  SEXP sketch_sexp = static_cast<SEXP>(sketch);
  if (
    TYPEOF(sketch_sexp) != EXTPTRSXP ||
    R_ExternalPtrTag(sketch_sexp) != cm_sketch_tag()
  ) {
    return false;
  }

  cm_sketch_ptr ptr(sketch);
  return ptr.get() != nullptr;
}

cm_sketch_t& cm_sketch_from_xptr(cpp11::sexp sketch) {
  if (!cm_sketch_is_valid_xptr(sketch)) {
    cpp11::stop("`sketch` is not a valid Count-Min sketch.");
  }

  cm_sketch_ptr ptr(sketch);
  return *ptr;
}

cpp11::sexp wrap_cm_sketch(cm_sketch_t&& sketch) {
  cm_sketch_ptr ptr(new cm_sketch_t(std::move(sketch)));
  SEXP out = static_cast<SEXP>(ptr);
  R_SetExternalPtrTag(out, cm_sketch_tag());
  return out;
}

} // namespace

[[cpp11::register]]
cpp11::sexp cm_create_cpp(int num_hashes, int num_buckets, double seed) {
  const uint64_t seed_u64 = data_sketches_native::checked_uint64_from_double(seed, "seed");
  return wrap_cm_sketch(
    cm_sketch_t(
      static_cast<uint8_t>(num_hashes),
      static_cast<uint32_t>(num_buckets),
      seed_u64
    )
  );
}

[[cpp11::register]]
bool cm_is_valid_cpp(cpp11::sexp sketch) {
  return cm_sketch_is_valid_xptr(sketch);
}

[[cpp11::register]]
double cm_get_num_hashes_cpp(cpp11::sexp sketch) {
  return static_cast<double>(cm_sketch_from_xptr(sketch).get_num_hashes());
}

[[cpp11::register]]
double cm_get_num_buckets_cpp(cpp11::sexp sketch) {
  return static_cast<double>(cm_sketch_from_xptr(sketch).get_num_buckets());
}

[[cpp11::register]]
double cm_get_seed_cpp(cpp11::sexp sketch) {
  return static_cast<double>(cm_sketch_from_xptr(sketch).get_seed());
}

[[cpp11::register]]
double cm_get_relative_error_cpp(cpp11::sexp sketch) {
  return cm_sketch_from_xptr(sketch).get_relative_error();
}

[[cpp11::register]]
double cm_get_total_weight_cpp(cpp11::sexp sketch) {
  return cm_sketch_from_xptr(sketch).get_total_weight();
}

[[cpp11::register]]
bool cm_is_empty_cpp(cpp11::sexp sketch) {
  return cm_sketch_from_xptr(sketch).is_empty();
}

// Numeric items are hashed via the raw bytes of the IEEE-754 double, the same
// scheme used for update and estimate so the two stay consistent.
[[cpp11::register]]
void cm_update_doubles_cpp(cpp11::sexp sketch, cpp11::doubles values, cpp11::doubles weights) {
  auto& sk = cm_sketch_from_xptr(sketch);
  const R_xlen_t n = values.size();
  const R_xlen_t m = weights.size();
  for (R_xlen_t i = 0; i < n; ++i) {
    if ((i & 0xFFFF) == 0) {
      R_CheckUserInterrupt();
    }
    const double value = values[i];
    sk.update(static_cast<const void*>(&value), sizeof(double), weights[i % m]);
  }
}

[[cpp11::register]]
void cm_update_strings_cpp(cpp11::sexp sketch, cpp11::strings values, cpp11::doubles weights) {
  auto& sk = cm_sketch_from_xptr(sketch);
  const R_xlen_t n = values.size();
  const R_xlen_t m = weights.size();
  for (R_xlen_t i = 0; i < n; ++i) {
    if ((i & 0xFFFF) == 0) {
      R_CheckUserInterrupt();
    }
    sk.update(static_cast<std::string>(values[i]), weights[i % m]);
  }
}

[[cpp11::register]]
cpp11::doubles cm_get_estimate_doubles_cpp(cpp11::sexp sketch, cpp11::doubles items) {
  auto& sk = cm_sketch_from_xptr(sketch);
  const R_xlen_t n = items.size();
  cpp11::writable::doubles out(n);
  for (R_xlen_t i = 0; i < n; ++i) {
    const double value = items[i];
    out[i] = sk.get_estimate(static_cast<const void*>(&value), sizeof(double));
  }
  return out;
}

[[cpp11::register]]
cpp11::doubles cm_get_estimate_strings_cpp(cpp11::sexp sketch, cpp11::strings items) {
  auto& sk = cm_sketch_from_xptr(sketch);
  const R_xlen_t n = items.size();
  cpp11::writable::doubles out(n);
  for (R_xlen_t i = 0; i < n; ++i) {
    out[i] = sk.get_estimate(static_cast<std::string>(items[i]));
  }
  return out;
}

[[cpp11::register]]
cpp11::doubles cm_get_lower_bound_doubles_cpp(cpp11::sexp sketch, cpp11::doubles items) {
  auto& sk = cm_sketch_from_xptr(sketch);
  const R_xlen_t n = items.size();
  cpp11::writable::doubles out(n);
  for (R_xlen_t i = 0; i < n; ++i) {
    const double value = items[i];
    out[i] = sk.get_lower_bound(static_cast<const void*>(&value), sizeof(double));
  }
  return out;
}

[[cpp11::register]]
cpp11::doubles cm_get_lower_bound_strings_cpp(cpp11::sexp sketch, cpp11::strings items) {
  auto& sk = cm_sketch_from_xptr(sketch);
  const R_xlen_t n = items.size();
  cpp11::writable::doubles out(n);
  for (R_xlen_t i = 0; i < n; ++i) {
    out[i] = sk.get_lower_bound(static_cast<std::string>(items[i]));
  }
  return out;
}

[[cpp11::register]]
cpp11::doubles cm_get_upper_bound_doubles_cpp(cpp11::sexp sketch, cpp11::doubles items) {
  auto& sk = cm_sketch_from_xptr(sketch);
  const R_xlen_t n = items.size();
  cpp11::writable::doubles out(n);
  for (R_xlen_t i = 0; i < n; ++i) {
    const double value = items[i];
    out[i] = sk.get_upper_bound(static_cast<const void*>(&value), sizeof(double));
  }
  return out;
}

[[cpp11::register]]
cpp11::doubles cm_get_upper_bound_strings_cpp(cpp11::sexp sketch, cpp11::strings items) {
  auto& sk = cm_sketch_from_xptr(sketch);
  const R_xlen_t n = items.size();
  cpp11::writable::doubles out(n);
  for (R_xlen_t i = 0; i < n; ++i) {
    out[i] = sk.get_upper_bound(static_cast<std::string>(items[i]));
  }
  return out;
}

// Direct native merge(); R validates that `num_hashes`, `num_buckets`, and
// `seed` match before calling this (the same checks the native merge would
// otherwise throw `std::invalid_argument` for).
[[cpp11::register]]
void cm_merge_cpp(cpp11::sexp sketch, cpp11::sexp other) {
  auto& sk = cm_sketch_from_xptr(sketch);
  auto& other_sk = cm_sketch_from_xptr(other);
  sk.merge(other_sk);
}

[[cpp11::register]]
std::string cm_to_string_cpp(cpp11::sexp sketch) {
  std::ostringstream os;
  os << cm_sketch_from_xptr(sketch).to_string();
  return os.str();
}

[[cpp11::register]]
cpp11::raws cm_serialize_cpp(cpp11::sexp sketch) {
  auto bytes = cm_sketch_from_xptr(sketch).serialize();
  cpp11::writable::raws out(bytes.size());
  std::copy(bytes.begin(), bytes.end(), out.begin());
  return out;
}

[[cpp11::register]]
cpp11::sexp cm_deserialize_cpp(cpp11::raws bytes, double seed) {
  const uint64_t seed_u64 = data_sketches_native::checked_uint64_from_double(seed, "seed");
  std::vector<uint8_t> buffer(bytes.begin(), bytes.end());
  return wrap_cm_sketch(
    cm_sketch_t::deserialize(buffer.data(), buffer.size(), seed_u64)
  );
}

[[cpp11::register]]
double cm_suggest_num_buckets_cpp(double relative_error) {
  return static_cast<double>(cm_sketch_t::suggest_num_buckets(relative_error));
}

[[cpp11::register]]
double cm_suggest_num_hashes_cpp(double confidence) {
  return static_cast<double>(cm_sketch_t::suggest_num_hashes(confidence));
}
