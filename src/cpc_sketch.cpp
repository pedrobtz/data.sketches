#include <algorithm>
#include <cstdint>
#include <string>
#include <vector>

#include <cpp11.hpp>

#include <R_ext/Utils.h> // R_CheckUserInterrupt

#include "cpc_sketch.hpp"
#include "cpc_union.hpp"
#include "native_utils.h"

namespace {

using cpc_sketch_t = datasketches::cpc_sketch;
using cpc_union_t = datasketches::cpc_union;
using cpc_sketch_ptr = cpp11::external_pointer<cpc_sketch_t>;

SEXP cpc_sketch_tag() {
  return Rf_install("data.sketches::cpc_sketch");
}

bool cpc_sketch_is_valid_xptr(cpp11::sexp sketch) {
  SEXP sketch_sexp = static_cast<SEXP>(sketch);
  if (
    TYPEOF(sketch_sexp) != EXTPTRSXP ||
    R_ExternalPtrTag(sketch_sexp) != cpc_sketch_tag()
  ) {
    return false;
  }

  cpc_sketch_ptr ptr(sketch);
  return ptr.get() != nullptr;
}

cpc_sketch_t& cpc_sketch_from_xptr(cpp11::sexp sketch) {
  if (!cpc_sketch_is_valid_xptr(sketch)) {
    cpp11::stop("`sketch` is not a valid CPC sketch.");
  }

  cpc_sketch_ptr ptr(sketch);
  return *ptr;
}

cpp11::sexp wrap_cpc_sketch(cpc_sketch_t&& sketch) {
  cpc_sketch_ptr ptr(new cpc_sketch_t(std::move(sketch)));
  SEXP out = static_cast<SEXP>(ptr);
  R_SetExternalPtrTag(out, cpc_sketch_tag());
  return out;
}

} // namespace

[[cpp11::register]]
cpp11::sexp cpc_create_cpp(int lg_k, double seed) {
  const uint64_t seed_u64 = data_sketches_native::checked_uint64_from_double(seed, "seed");
  return wrap_cpc_sketch(
    cpc_sketch_t(static_cast<uint8_t>(lg_k), seed_u64)
  );
}

[[cpp11::register]]
bool cpc_is_valid_cpp(cpp11::sexp sketch) {
  return cpc_sketch_is_valid_xptr(sketch);
}

[[cpp11::register]]
void cpc_update_doubles_cpp(cpp11::sexp sketch, cpp11::doubles values) {
  auto& sk = cpc_sketch_from_xptr(sketch);
  const double* p = REAL(values.data());
  const R_xlen_t n = values.size();
  for (R_xlen_t i = 0; i < n; ++i) {
    if ((i & 0xFFFF) == 0) {
      R_CheckUserInterrupt();
    }
    sk.update(p[i]);
  }
}

[[cpp11::register]]
void cpc_update_strings_cpp(cpp11::sexp sketch, cpp11::strings values) {
  auto& sk = cpc_sketch_from_xptr(sketch);
  const R_xlen_t n = values.size();
  for (R_xlen_t i = 0; i < n; ++i) {
    if ((i & 0xFFFF) == 0) {
      R_CheckUserInterrupt();
    }
    sk.update(static_cast<std::string>(values[i]));
  }
}

// CPC has no direct merge(); two sketches are combined by feeding both into a
// union sized for the larger `lg_k`, then replacing the receiver's state with
// the union result. Both sketches must share the same `seed` (validated in R
// before this is called); a mismatched seed raises a native error here.
[[cpp11::register]]
void cpc_merge_cpp(cpp11::sexp sketch, cpp11::sexp other, double seed) {
  auto& sk = cpc_sketch_from_xptr(sketch);
  auto& other_sk = cpc_sketch_from_xptr(other);
  uint8_t lg_max_k = std::max(sk.get_lg_k(), other_sk.get_lg_k());
  const uint64_t seed_u64 = data_sketches_native::checked_uint64_from_double(seed, "seed");
  cpc_union_t u(lg_max_k, seed_u64);
  u.update(sk);
  u.update(other_sk);
  sk = u.get_result();
}

[[cpp11::register]]
bool cpc_is_empty_cpp(cpp11::sexp sketch) {
  return cpc_sketch_from_xptr(sketch).is_empty();
}

[[cpp11::register]]
int cpc_get_lg_k_cpp(cpp11::sexp sketch) {
  return cpc_sketch_from_xptr(sketch).get_lg_k();
}

[[cpp11::register]]
double cpc_get_estimate_cpp(cpp11::sexp sketch) {
  return cpc_sketch_from_xptr(sketch).get_estimate();
}

[[cpp11::register]]
double cpc_get_lower_bound_cpp(cpp11::sexp sketch, int kappa) {
  return cpc_sketch_from_xptr(sketch).get_lower_bound(
    static_cast<unsigned>(kappa)
  );
}

[[cpp11::register]]
double cpc_get_upper_bound_cpp(cpp11::sexp sketch, int kappa) {
  return cpc_sketch_from_xptr(sketch).get_upper_bound(
    static_cast<unsigned>(kappa)
  );
}

[[cpp11::register]]
std::string cpc_to_string_cpp(cpp11::sexp sketch) {
  return cpc_sketch_from_xptr(sketch).to_string();
}

[[cpp11::register]]
cpp11::raws cpc_serialize_cpp(cpp11::sexp sketch) {
  auto bytes = cpc_sketch_from_xptr(sketch).serialize();
  cpp11::writable::raws out(bytes.size());
  std::copy(bytes.begin(), bytes.end(), out.begin());
  return out;
}

[[cpp11::register]]
cpp11::sexp cpc_deserialize_cpp(cpp11::raws bytes, double seed) {
  const uint64_t seed_u64 = data_sketches_native::checked_uint64_from_double(seed, "seed");
  std::vector<uint8_t> buffer(bytes.begin(), bytes.end());
  return wrap_cpc_sketch(
    cpc_sketch_t::deserialize(
      buffer.data(),
      buffer.size(),
      seed_u64
    )
  );
}
