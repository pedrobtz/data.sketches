#include <algorithm>
#include <cstdint>
#include <string>
#include <vector>

#include <cpp11.hpp>

#include <R_ext/Utils.h> // R_CheckUserInterrupt

#include "req_sketch.hpp"

namespace {

using req_doubles_sketch = datasketches::req_sketch<double>;
using req_sketch_ptr = cpp11::external_pointer<req_doubles_sketch>;

SEXP req_sketch_tag() {
  return Rf_install("data.sketches::req_sketch");
}

bool req_sketch_is_valid_xptr(cpp11::sexp sketch) {
  SEXP sketch_sexp = static_cast<SEXP>(sketch);
  if (
    TYPEOF(sketch_sexp) != EXTPTRSXP ||
    R_ExternalPtrTag(sketch_sexp) != req_sketch_tag()
  ) {
    return false;
  }

  req_sketch_ptr ptr(sketch);
  return ptr.get() != nullptr;
}

req_doubles_sketch& req_sketch_from_xptr(cpp11::sexp sketch) {
  if (!req_sketch_is_valid_xptr(sketch)) {
    cpp11::stop("`sketch` is not a valid REQ sketch.");
  }

  req_sketch_ptr ptr(sketch);
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

// `k` must be even and in [4, 1024] (req_constants::MIN_K = 4).
uint16_t checked_k(int k) {
  if (k < 4 || k > 1024 || (k % 2) != 0) {
    cpp11::stop("`k` must be an even integer between 4 and 1024.");
  }
  return static_cast<uint16_t>(k);
}

} // namespace

[[cpp11::register]]
cpp11::sexp req_create_cpp(int k, bool hra) {
  req_sketch_ptr ptr(new req_doubles_sketch(checked_k(k), hra));
  SEXP out = static_cast<SEXP>(ptr);
  R_SetExternalPtrTag(out, req_sketch_tag());
  return out;
}

[[cpp11::register]]
bool req_is_valid_cpp(cpp11::sexp sketch) {
  return req_sketch_is_valid_xptr(sketch);
}

[[cpp11::register]]
void req_update_cpp(cpp11::sexp sketch, cpp11::doubles values) {
  auto& sk = req_sketch_from_xptr(sketch);
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
void req_merge_cpp(cpp11::sexp sketch, cpp11::sexp other) {
  auto& sk = req_sketch_from_xptr(sketch);
  auto& other_sk = req_sketch_from_xptr(other);
  sk.merge(other_sk);
}

[[cpp11::register]]
bool req_is_empty_cpp(cpp11::sexp sketch) {
  return req_sketch_from_xptr(sketch).is_empty();
}

[[cpp11::register]]
bool req_is_estimation_mode_cpp(cpp11::sexp sketch) {
  return req_sketch_from_xptr(sketch).is_estimation_mode();
}

[[cpp11::register]]
int req_get_k_cpp(cpp11::sexp sketch) {
  return req_sketch_from_xptr(sketch).get_k();
}

[[cpp11::register]]
bool req_is_hra_cpp(cpp11::sexp sketch) {
  return req_sketch_from_xptr(sketch).is_HRA();
}

[[cpp11::register]]
double req_get_n_cpp(cpp11::sexp sketch) {
  return static_cast<double>(req_sketch_from_xptr(sketch).get_n());
}

[[cpp11::register]]
double req_get_num_retained_cpp(cpp11::sexp sketch) {
  return static_cast<double>(req_sketch_from_xptr(sketch).get_num_retained());
}

[[cpp11::register]]
double req_get_min_item_cpp(cpp11::sexp sketch) {
  return req_sketch_from_xptr(sketch).get_min_item();
}

[[cpp11::register]]
double req_get_max_item_cpp(cpp11::sexp sketch) {
  return req_sketch_from_xptr(sketch).get_max_item();
}

[[cpp11::register]]
cpp11::doubles req_get_quantiles_cpp(
  cpp11::sexp sketch,
  cpp11::doubles ranks,
  bool inclusive
) {
  auto& sk = req_sketch_from_xptr(sketch);
  cpp11::writable::doubles out(ranks.size());
  for (R_xlen_t i = 0; i < ranks.size(); ++i) {
    out[i] = sk.get_quantile(ranks[i], inclusive);
  }
  return out;
}

[[cpp11::register]]
cpp11::doubles req_get_ranks_cpp(
  cpp11::sexp sketch,
  cpp11::doubles values,
  bool inclusive
) {
  auto& sk = req_sketch_from_xptr(sketch);
  cpp11::writable::doubles out(values.size());
  for (R_xlen_t i = 0; i < values.size(); ++i) {
    out[i] = sk.get_rank(values[i], inclusive);
  }
  return out;
}

[[cpp11::register]]
cpp11::doubles req_get_pmf_cpp(
  cpp11::sexp sketch,
  cpp11::doubles split_points,
  bool inclusive
) {
  auto split_points_vector = doubles_to_vector(split_points);
  auto out = req_sketch_from_xptr(sketch).get_PMF(
    split_points_vector.data(),
    split_points_vector.size(),
    inclusive
  );
  return vector_to_doubles(out);
}

[[cpp11::register]]
cpp11::doubles req_get_cdf_cpp(
  cpp11::sexp sketch,
  cpp11::doubles split_points,
  bool inclusive
) {
  auto split_points_vector = doubles_to_vector(split_points);
  auto out = req_sketch_from_xptr(sketch).get_CDF(
    split_points_vector.data(),
    split_points_vector.size(),
    inclusive
  );
  return vector_to_doubles(out);
}

// REQ error is rank-dependent (unlike KLL's single normalized rank error), so
// these vectorize over `ranks` for the sketch's current k/hra/n.
[[cpp11::register]]
cpp11::doubles req_rank_lower_bound_cpp(
  cpp11::sexp sketch,
  cpp11::doubles ranks,
  int num_std_dev
) {
  auto& sk = req_sketch_from_xptr(sketch);
  cpp11::writable::doubles out(ranks.size());
  for (R_xlen_t i = 0; i < ranks.size(); ++i) {
    out[i] = sk.get_rank_lower_bound(ranks[i], static_cast<uint8_t>(num_std_dev));
  }
  return out;
}

[[cpp11::register]]
cpp11::doubles req_rank_upper_bound_cpp(
  cpp11::sexp sketch,
  cpp11::doubles ranks,
  int num_std_dev
) {
  auto& sk = req_sketch_from_xptr(sketch);
  cpp11::writable::doubles out(ranks.size());
  for (R_xlen_t i = 0; i < ranks.size(); ++i) {
    out[i] = sk.get_rank_upper_bound(ranks[i], static_cast<uint8_t>(num_std_dev));
  }
  return out;
}

[[cpp11::register]]
std::string req_to_string_cpp(
  cpp11::sexp sketch,
  bool print_levels,
  bool print_items
) {
  return req_sketch_from_xptr(sketch).to_string(print_levels, print_items);
}

[[cpp11::register]]
cpp11::raws req_serialize_cpp(cpp11::sexp sketch) {
  auto bytes = req_sketch_from_xptr(sketch).serialize();
  cpp11::writable::raws out(bytes.size());
  std::copy(bytes.begin(), bytes.end(), out.begin());
  return out;
}

[[cpp11::register]]
cpp11::sexp req_deserialize_cpp(cpp11::raws bytes) {
  std::vector<uint8_t> buffer(bytes.begin(), bytes.end());
  auto sketch = req_doubles_sketch::deserialize(buffer.data(), buffer.size());
  req_sketch_ptr ptr(new req_doubles_sketch(std::move(sketch)));
  SEXP out = static_cast<SEXP>(ptr);
  R_SetExternalPtrTag(out, req_sketch_tag());
  return out;
}
