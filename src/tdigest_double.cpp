#include <algorithm>
#include <cstdint>
#include <string>
#include <vector>

#include <cpp11.hpp>

#include <R_ext/Utils.h> // R_CheckUserInterrupt

#include "tdigest.hpp"

namespace {

using tdigest_double_sketch = datasketches::tdigest_double;
using tdigest_double_ptr = cpp11::external_pointer<tdigest_double_sketch>;

SEXP tdigest_double_tag() {
  return Rf_install("data.sketches::tdigest_double_sketch");
}

bool tdigest_double_is_valid_xptr(cpp11::sexp sketch) {
  SEXP sketch_sexp = static_cast<SEXP>(sketch);
  if (
    TYPEOF(sketch_sexp) != EXTPTRSXP ||
    R_ExternalPtrTag(sketch_sexp) != tdigest_double_tag()
  ) {
    return false;
  }

  tdigest_double_ptr ptr(sketch);
  return ptr.get() != nullptr;
}

tdigest_double_sketch& tdigest_double_from_xptr(cpp11::sexp sketch) {
  if (!tdigest_double_is_valid_xptr(sketch)) {
    cpp11::stop("`sketch` is not a valid t-Digest double sketch.");
  }

  tdigest_double_ptr ptr(sketch);
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

} // namespace

[[cpp11::register]]
cpp11::sexp td_create_cpp(int k) {
  tdigest_double_ptr ptr(new tdigest_double_sketch(static_cast<uint16_t>(k)));
  SEXP out = static_cast<SEXP>(ptr);
  R_SetExternalPtrTag(out, tdigest_double_tag());
  return out;
}

[[cpp11::register]]
bool td_is_valid_cpp(cpp11::sexp sketch) {
  return tdigest_double_is_valid_xptr(sketch);
}

[[cpp11::register]]
void td_update_cpp(cpp11::sexp sketch, cpp11::doubles values) {
  auto& sk = tdigest_double_from_xptr(sketch);
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
void td_merge_cpp(cpp11::sexp sketch, cpp11::sexp other) {
  auto& sk = tdigest_double_from_xptr(sketch);
  auto& other_sk = tdigest_double_from_xptr(other);
  sk.merge(other_sk);
}

[[cpp11::register]]
bool td_is_empty_cpp(cpp11::sexp sketch) {
  return tdigest_double_from_xptr(sketch).is_empty();
}

[[cpp11::register]]
int td_get_k_cpp(cpp11::sexp sketch) {
  return tdigest_double_from_xptr(sketch).get_k();
}

[[cpp11::register]]
double td_get_total_weight_cpp(cpp11::sexp sketch) {
  return static_cast<double>(tdigest_double_from_xptr(sketch).get_total_weight());
}

[[cpp11::register]]
double td_get_min_value_cpp(cpp11::sexp sketch) {
  return tdigest_double_from_xptr(sketch).get_min_value();
}

[[cpp11::register]]
double td_get_max_value_cpp(cpp11::sexp sketch) {
  return tdigest_double_from_xptr(sketch).get_max_value();
}

[[cpp11::register]]
cpp11::doubles td_get_quantiles_cpp(cpp11::sexp sketch, cpp11::doubles ranks) {
  auto& sk = tdigest_double_from_xptr(sketch);
  cpp11::writable::doubles out(ranks.size());
  for (R_xlen_t i = 0; i < ranks.size(); ++i) {
    out[i] = sk.get_quantile(ranks[i]);
  }
  return out;
}

[[cpp11::register]]
cpp11::doubles td_get_ranks_cpp(cpp11::sexp sketch, cpp11::doubles values) {
  auto& sk = tdigest_double_from_xptr(sketch);
  cpp11::writable::doubles out(values.size());
  for (R_xlen_t i = 0; i < values.size(); ++i) {
    out[i] = sk.get_rank(values[i]);
  }
  return out;
}

[[cpp11::register]]
cpp11::doubles td_get_pmf_cpp(cpp11::sexp sketch, cpp11::doubles split_points) {
  auto split_points_vector = doubles_to_vector(split_points);
  auto out = tdigest_double_from_xptr(sketch).get_PMF(
    split_points_vector.data(),
    split_points_vector.size()
  );
  return vector_to_doubles(out);
}

[[cpp11::register]]
cpp11::doubles td_get_cdf_cpp(cpp11::sexp sketch, cpp11::doubles split_points) {
  auto split_points_vector = doubles_to_vector(split_points);
  auto out = tdigest_double_from_xptr(sketch).get_CDF(
    split_points_vector.data(),
    split_points_vector.size()
  );
  return vector_to_doubles(out);
}

[[cpp11::register]]
std::string td_to_string_cpp(cpp11::sexp sketch, bool print_centroids) {
  return tdigest_double_from_xptr(sketch).to_string(print_centroids);
}

[[cpp11::register]]
cpp11::raws td_serialize_cpp(cpp11::sexp sketch) {
  auto bytes = tdigest_double_from_xptr(sketch).serialize();
  cpp11::writable::raws out(bytes.size());
  std::copy(bytes.begin(), bytes.end(), out.begin());
  return out;
}

[[cpp11::register]]
cpp11::sexp td_deserialize_cpp(cpp11::raws bytes) {
  std::vector<uint8_t> buffer(bytes.begin(), bytes.end());
  auto sketch = tdigest_double_sketch::deserialize(buffer.data(), buffer.size());
  tdigest_double_ptr ptr(new tdigest_double_sketch(std::move(sketch)));
  SEXP out = static_cast<SEXP>(ptr);
  R_SetExternalPtrTag(out, tdigest_double_tag());
  return out;
}
