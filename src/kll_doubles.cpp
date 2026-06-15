#include <algorithm>
#include <cstdint>
#include <limits>
#include <string>
#include <vector>

#include <cpp11.hpp>

#include <R_ext/Utils.h> // R_CheckUserInterrupt

#include "kll_sketch.hpp"

namespace {

using kll_doubles_sketch = datasketches::kll_sketch<double>;
using kll_doubles_ptr = cpp11::external_pointer<kll_doubles_sketch>;

SEXP kll_doubles_tag() {
  return Rf_install("data.sketches::kll_doubles_sketch");
}

bool kll_doubles_is_valid_xptr(cpp11::sexp sketch) {
  SEXP sketch_sexp = static_cast<SEXP>(sketch);
  if (
    TYPEOF(sketch_sexp) != EXTPTRSXP ||
    R_ExternalPtrTag(sketch_sexp) != kll_doubles_tag()
  ) {
    return false;
  }

  kll_doubles_ptr ptr(sketch);
  return ptr.get() != nullptr;
}

kll_doubles_sketch& kll_doubles_from_xptr(cpp11::sexp sketch) {
  if (!kll_doubles_is_valid_xptr(sketch)) {
    cpp11::stop("`sketch` is not a valid KLL doubles sketch.");
  }

  kll_doubles_ptr ptr(sketch);
  return *ptr;
}

std::vector<double> doubles_to_vector(cpp11::doubles values) {
  std::vector<double> out;
  out.reserve(values.size());
  for (double value : values) {
    out.push_back(value);
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
cpp11::sexp kll_doubles_create_cpp(int k) {
  kll_doubles_ptr ptr(new kll_doubles_sketch(checked_k(k)));
  SEXP out = static_cast<SEXP>(ptr);
  R_SetExternalPtrTag(out, kll_doubles_tag());
  return out;
}

[[cpp11::register]]
bool kll_doubles_is_valid_cpp(cpp11::sexp sketch) {
  return kll_doubles_is_valid_xptr(sketch);
}

[[cpp11::register]]
void kll_doubles_update_cpp(cpp11::sexp sketch, cpp11::doubles values) {
  auto& sk = kll_doubles_from_xptr(sketch);
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
    sk.update(p[i]);
  }
}

[[cpp11::register]]
void kll_doubles_merge_cpp(cpp11::sexp sketch, cpp11::sexp other) {
  auto& sk = kll_doubles_from_xptr(sketch);
  auto& other_sk = kll_doubles_from_xptr(other);
  sk.merge(other_sk);
}

[[cpp11::register]]
bool kll_doubles_is_empty_cpp(cpp11::sexp sketch) {
  return kll_doubles_from_xptr(sketch).is_empty();
}

[[cpp11::register]]
bool kll_doubles_is_estimation_mode_cpp(cpp11::sexp sketch) {
  return kll_doubles_from_xptr(sketch).is_estimation_mode();
}

[[cpp11::register]]
int kll_doubles_get_k_cpp(cpp11::sexp sketch) {
  return kll_doubles_from_xptr(sketch).get_k();
}

[[cpp11::register]]
double kll_doubles_get_n_cpp(cpp11::sexp sketch) {
  return static_cast<double>(kll_doubles_from_xptr(sketch).get_n());
}

[[cpp11::register]]
double kll_doubles_get_num_retained_cpp(cpp11::sexp sketch) {
  return static_cast<double>(kll_doubles_from_xptr(sketch).get_num_retained());
}

[[cpp11::register]]
double kll_doubles_get_min_item_cpp(cpp11::sexp sketch) {
  return kll_doubles_from_xptr(sketch).get_min_item();
}

[[cpp11::register]]
double kll_doubles_get_max_item_cpp(cpp11::sexp sketch) {
  return kll_doubles_from_xptr(sketch).get_max_item();
}

[[cpp11::register]]
cpp11::doubles kll_doubles_get_quantiles_cpp(
  cpp11::sexp sketch,
  cpp11::doubles ranks,
  bool inclusive
) {
  auto& sk = kll_doubles_from_xptr(sketch);
  cpp11::writable::doubles out(ranks.size());
  for (R_xlen_t i = 0; i < ranks.size(); ++i) {
    out[i] = sk.get_quantile(ranks[i], inclusive);
  }
  return out;
}

[[cpp11::register]]
cpp11::doubles kll_doubles_get_ranks_cpp(
  cpp11::sexp sketch,
  cpp11::doubles values,
  bool inclusive
) {
  auto& sk = kll_doubles_from_xptr(sketch);
  cpp11::writable::doubles out(values.size());
  for (R_xlen_t i = 0; i < values.size(); ++i) {
    out[i] = sk.get_rank(values[i], inclusive);
  }
  return out;
}

[[cpp11::register]]
cpp11::doubles kll_doubles_get_pmf_cpp(
  cpp11::sexp sketch,
  cpp11::doubles split_points,
  bool inclusive
) {
  auto split_points_vector = doubles_to_vector(split_points);
  auto out = kll_doubles_from_xptr(sketch).get_PMF(
    split_points_vector.data(),
    split_points_vector.size(),
    inclusive
  );
  return vector_to_doubles(out);
}

[[cpp11::register]]
cpp11::doubles kll_doubles_get_cdf_cpp(
  cpp11::sexp sketch,
  cpp11::doubles split_points,
  bool inclusive
) {
  auto split_points_vector = doubles_to_vector(split_points);
  auto out = kll_doubles_from_xptr(sketch).get_CDF(
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
double kll_doubles_rank_error_cpp(cpp11::sexp sketch, bool as_pmf) {
  return kll_doubles_from_xptr(sketch).get_normalized_rank_error(as_pmf);
}

[[cpp11::register]]
std::string kll_doubles_to_string_cpp(
  cpp11::sexp sketch,
  bool print_levels,
  bool print_items
) {
  return kll_doubles_from_xptr(sketch).to_string(print_levels, print_items);
}

[[cpp11::register]]
cpp11::raws kll_doubles_serialize_cpp(cpp11::sexp sketch) {
  auto bytes = kll_doubles_from_xptr(sketch).serialize();
  cpp11::writable::raws out(bytes.size());
  std::copy(bytes.begin(), bytes.end(), out.begin());
  return out;
}

[[cpp11::register]]
cpp11::sexp kll_doubles_deserialize_cpp(cpp11::raws bytes) {
  std::vector<uint8_t> buffer(bytes.begin(), bytes.end());
  auto sketch = kll_doubles_sketch::deserialize(buffer.data(), buffer.size());
  kll_doubles_ptr ptr(new kll_doubles_sketch(std::move(sketch)));
  SEXP out = static_cast<SEXP>(ptr);
  R_SetExternalPtrTag(out, kll_doubles_tag());
  return out;
}
