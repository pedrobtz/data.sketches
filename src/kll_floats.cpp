#include <algorithm>
#include <cstdint>
#include <limits>
#include <string>
#include <vector>

#include <cpp11.hpp>

#include <R_ext/Utils.h> // R_CheckUserInterrupt

#include "kll_sketch.hpp"

namespace {

using kll_floats_sketch = datasketches::kll_sketch<float>;
using kll_floats_ptr = cpp11::external_pointer<kll_floats_sketch>;

SEXP kll_floats_tag() {
  return Rf_install("data.sketches::kll_floats_sketch");
}

bool kll_floats_is_valid_xptr(cpp11::sexp sketch) {
  SEXP sketch_sexp = static_cast<SEXP>(sketch);
  if (
    TYPEOF(sketch_sexp) != EXTPTRSXP ||
    R_ExternalPtrTag(sketch_sexp) != kll_floats_tag()
  ) {
    return false;
  }

  kll_floats_ptr ptr(sketch);
  return ptr.get() != nullptr;
}

kll_floats_sketch& kll_floats_from_xptr(cpp11::sexp sketch) {
  if (!kll_floats_is_valid_xptr(sketch)) {
    cpp11::stop("`sketch` is not a valid KLL floats sketch.");
  }

  kll_floats_ptr ptr(sketch);
  return *ptr;
}

std::vector<float> doubles_to_float_vector(cpp11::doubles values) {
  std::vector<float> out;
  out.reserve(values.size());
  for (double value : values) {
    out.push_back(static_cast<float>(value));
  }
  return out;
}

cpp11::writable::doubles vector_to_doubles(const std::vector<double>& values) {
  cpp11::writable::doubles out(values.size());
  std::copy(values.begin(), values.end(), out.begin());
  return out;
}

uint16_t checked_k(int k) {
  if (k < 8 || k > static_cast<int>(std::numeric_limits<uint16_t>::max())) {
    cpp11::stop("`k` must be an integer between 8 and 65535.");
  }
  return static_cast<uint16_t>(k);
}

} // namespace

[[cpp11::register]]
cpp11::sexp kll_floats_create_cpp(int k) {
  kll_floats_ptr ptr(new kll_floats_sketch(checked_k(k)));
  SEXP out = static_cast<SEXP>(ptr);
  R_SetExternalPtrTag(out, kll_floats_tag());
  return out;
}

[[cpp11::register]]
bool kll_floats_is_valid_cpp(cpp11::sexp sketch) {
  return kll_floats_is_valid_xptr(sketch);
}

[[cpp11::register]]
void kll_floats_update_cpp(cpp11::sexp sketch, cpp11::doubles values) {
  auto& sk = kll_floats_from_xptr(sketch);
  // Loop over the raw buffer rather than cpp11's element accessor: for a
  // multi-million element vector the per-element accessor overhead dominates,
  // while a direct pointer walk into the same sketch.update() does not.
  const double* p = REAL(values.data());
  const R_xlen_t n = values.size();
  for (R_xlen_t i = 0; i < n; ++i) {
    // Let the user abort a multi-million element update; checking every element
    // would dominate the loop, so probe on a 64k boundary.
    if ((i & 0xFFFF) == 0) {
      R_CheckUserInterrupt();
    }
    sk.update(static_cast<float>(p[i]));
  }
}

[[cpp11::register]]
void kll_floats_merge_cpp(cpp11::sexp sketch, cpp11::sexp other) {
  auto& sk = kll_floats_from_xptr(sketch);
  auto& other_sk = kll_floats_from_xptr(other);
  sk.merge(other_sk);
}

[[cpp11::register]]
bool kll_floats_is_empty_cpp(cpp11::sexp sketch) {
  return kll_floats_from_xptr(sketch).is_empty();
}

[[cpp11::register]]
bool kll_floats_is_estimation_mode_cpp(cpp11::sexp sketch) {
  return kll_floats_from_xptr(sketch).is_estimation_mode();
}

[[cpp11::register]]
int kll_floats_get_k_cpp(cpp11::sexp sketch) {
  return kll_floats_from_xptr(sketch).get_k();
}

[[cpp11::register]]
double kll_floats_get_n_cpp(cpp11::sexp sketch) {
  return static_cast<double>(kll_floats_from_xptr(sketch).get_n());
}

[[cpp11::register]]
double kll_floats_get_num_retained_cpp(cpp11::sexp sketch) {
  return static_cast<double>(kll_floats_from_xptr(sketch).get_num_retained());
}

[[cpp11::register]]
double kll_floats_get_min_item_cpp(cpp11::sexp sketch) {
  return static_cast<double>(kll_floats_from_xptr(sketch).get_min_item());
}

[[cpp11::register]]
double kll_floats_get_max_item_cpp(cpp11::sexp sketch) {
  return static_cast<double>(kll_floats_from_xptr(sketch).get_max_item());
}

[[cpp11::register]]
cpp11::doubles kll_floats_get_quantiles_cpp(
  cpp11::sexp sketch,
  cpp11::doubles ranks,
  bool inclusive
) {
  auto& sk = kll_floats_from_xptr(sketch);
  cpp11::writable::doubles out(ranks.size());
  for (R_xlen_t i = 0; i < ranks.size(); ++i) {
    out[i] = static_cast<double>(sk.get_quantile(ranks[i], inclusive));
  }
  return out;
}

[[cpp11::register]]
cpp11::doubles kll_floats_get_ranks_cpp(
  cpp11::sexp sketch,
  cpp11::doubles values,
  bool inclusive
) {
  auto& sk = kll_floats_from_xptr(sketch);
  cpp11::writable::doubles out(values.size());
  for (R_xlen_t i = 0; i < values.size(); ++i) {
    out[i] = sk.get_rank(static_cast<float>(values[i]), inclusive);
  }
  return out;
}

[[cpp11::register]]
cpp11::doubles kll_floats_get_pmf_cpp(
  cpp11::sexp sketch,
  cpp11::doubles split_points,
  bool inclusive
) {
  auto split_points_vector = doubles_to_float_vector(split_points);
  auto out = kll_floats_from_xptr(sketch).get_PMF(
    split_points_vector.data(),
    split_points_vector.size(),
    inclusive
  );
  return vector_to_doubles(out);
}

[[cpp11::register]]
cpp11::doubles kll_floats_get_cdf_cpp(
  cpp11::sexp sketch,
  cpp11::doubles split_points,
  bool inclusive
) {
  auto split_points_vector = doubles_to_float_vector(split_points);
  auto out = kll_floats_from_xptr(sketch).get_CDF(
    split_points_vector.data(),
    split_points_vector.size(),
    inclusive
  );
  return vector_to_doubles(out);
}

// Instance rank error reflects the sketch's *effective* k (min_k_ after a merge
// of sketches built with different k). A calculation based only on configured k
// would be overconfident post-merge.
[[cpp11::register]]
double kll_floats_rank_error_cpp(cpp11::sexp sketch, bool as_pmf) {
  return kll_floats_from_xptr(sketch).get_normalized_rank_error(as_pmf);
}

[[cpp11::register]]
std::string kll_floats_to_string_cpp(
  cpp11::sexp sketch,
  bool print_levels,
  bool print_items
) {
  return kll_floats_from_xptr(sketch).to_string(print_levels, print_items);
}

[[cpp11::register]]
cpp11::raws kll_floats_serialize_cpp(cpp11::sexp sketch) {
  auto bytes = kll_floats_from_xptr(sketch).serialize();
  cpp11::writable::raws out(bytes.size());
  std::copy(bytes.begin(), bytes.end(), out.begin());
  return out;
}

[[cpp11::register]]
cpp11::sexp kll_floats_deserialize_cpp(cpp11::raws bytes) {
  std::vector<uint8_t> buffer(bytes.begin(), bytes.end());
  auto sketch = kll_floats_sketch::deserialize(buffer.data(), buffer.size());
  kll_floats_ptr ptr(new kll_floats_sketch(std::move(sketch)));
  SEXP out = static_cast<SEXP>(ptr);
  R_SetExternalPtrTag(out, kll_floats_tag());
  return out;
}
