#include <algorithm>
#include <cstdint>
#include <string>
#include <vector>

#include <cpp11.hpp>

#include <R_ext/Utils.h> // R_CheckUserInterrupt

#include "hll.hpp"

namespace {

using hll_sketch_t = datasketches::hll_sketch;
using hll_union_t = datasketches::hll_union;
using hll_sketch_ptr = cpp11::external_pointer<hll_sketch_t>;

SEXP hll_sketch_tag() {
  return Rf_install("data.sketches::hll_sketch");
}

bool hll_sketch_is_valid_xptr(cpp11::sexp sketch) {
  SEXP sketch_sexp = static_cast<SEXP>(sketch);
  if (
    TYPEOF(sketch_sexp) != EXTPTRSXP ||
    R_ExternalPtrTag(sketch_sexp) != hll_sketch_tag()
  ) {
    return false;
  }

  hll_sketch_ptr ptr(sketch);
  return ptr.get() != nullptr;
}

hll_sketch_t& hll_sketch_from_xptr(cpp11::sexp sketch) {
  if (!hll_sketch_is_valid_xptr(sketch)) {
    cpp11::stop("`sketch` is not a valid HLL sketch.");
  }

  hll_sketch_ptr ptr(sketch);
  return *ptr;
}

cpp11::sexp wrap_hll_sketch(hll_sketch_t&& sketch) {
  hll_sketch_ptr ptr(new hll_sketch_t(std::move(sketch)));
  SEXP out = static_cast<SEXP>(ptr);
  R_SetExternalPtrTag(out, hll_sketch_tag());
  return out;
}

// `lg_k` is bounds-checked in R via `check_lg_k()`; this just narrows the type.
uint8_t to_lg_k(int lg_k) {
  return static_cast<uint8_t>(lg_k);
}

datasketches::target_hll_type to_target_type(int type) {
  return static_cast<datasketches::target_hll_type>(type);
}

} // namespace

[[cpp11::register]]
cpp11::sexp hll_create_cpp(int lg_k, int type) {
  return wrap_hll_sketch(hll_sketch_t(to_lg_k(lg_k), to_target_type(type)));
}

[[cpp11::register]]
bool hll_is_valid_cpp(cpp11::sexp sketch) {
  return hll_sketch_is_valid_xptr(sketch);
}

[[cpp11::register]]
void hll_update_doubles_cpp(cpp11::sexp sketch, cpp11::doubles values) {
  auto& sk = hll_sketch_from_xptr(sketch);
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
void hll_update_strings_cpp(cpp11::sexp sketch, cpp11::strings values) {
  auto& sk = hll_sketch_from_xptr(sketch);
  const R_xlen_t n = values.size();
  for (R_xlen_t i = 0; i < n; ++i) {
    if ((i & 0xFFFF) == 0) {
      R_CheckUserInterrupt();
    }
    sk.update(static_cast<std::string>(values[i]));
  }
}

// HLL has no direct merge(); two sketches are combined by feeding both into a
// union sized for the larger `lg_config_k`, then replacing the receiver's
// state with the union result in the receiver's own target type.
[[cpp11::register]]
void hll_merge_cpp(cpp11::sexp sketch, cpp11::sexp other) {
  auto& sk = hll_sketch_from_xptr(sketch);
  auto& other_sk = hll_sketch_from_xptr(other);
  uint8_t lg_max_k = std::max(sk.get_lg_config_k(), other_sk.get_lg_config_k());
  hll_union_t u(lg_max_k);
  u.update(sk);
  u.update(other_sk);
  sk = u.get_result(sk.get_target_type());
}

[[cpp11::register]]
bool hll_is_empty_cpp(cpp11::sexp sketch) {
  return hll_sketch_from_xptr(sketch).is_empty();
}

[[cpp11::register]]
bool hll_is_compact_cpp(cpp11::sexp sketch) {
  return hll_sketch_from_xptr(sketch).is_compact();
}

[[cpp11::register]]
int hll_get_lg_config_k_cpp(cpp11::sexp sketch) {
  return hll_sketch_from_xptr(sketch).get_lg_config_k();
}

[[cpp11::register]]
int hll_get_target_type_cpp(cpp11::sexp sketch) {
  return static_cast<int>(hll_sketch_from_xptr(sketch).get_target_type());
}

[[cpp11::register]]
double hll_get_estimate_cpp(cpp11::sexp sketch) {
  return hll_sketch_from_xptr(sketch).get_estimate();
}

[[cpp11::register]]
double hll_get_lower_bound_cpp(cpp11::sexp sketch, int num_std_dev) {
  return hll_sketch_from_xptr(sketch).get_lower_bound(
    static_cast<uint8_t>(num_std_dev)
  );
}

[[cpp11::register]]
double hll_get_upper_bound_cpp(cpp11::sexp sketch, int num_std_dev) {
  return hll_sketch_from_xptr(sketch).get_upper_bound(
    static_cast<uint8_t>(num_std_dev)
  );
}

[[cpp11::register]]
std::string hll_to_string_cpp(
  cpp11::sexp sketch,
  bool summary,
  bool detail,
  bool aux_detail,
  bool all
) {
  return hll_sketch_from_xptr(sketch).to_string(summary, detail, aux_detail, all);
}

[[cpp11::register]]
cpp11::raws hll_serialize_cpp(cpp11::sexp sketch) {
  auto bytes = hll_sketch_from_xptr(sketch).serialize_compact();
  cpp11::writable::raws out(bytes.size());
  std::copy(bytes.begin(), bytes.end(), out.begin());
  return out;
}

[[cpp11::register]]
cpp11::sexp hll_deserialize_cpp(cpp11::raws bytes) {
  if (bytes.size() < datasketches::hll_constants::EMPTY_SKETCH_SIZE_BYTES) {
    cpp11::stop("`bytes` is too short to be a valid HLL sketch payload.");
  }
  std::vector<uint8_t> buffer(bytes.begin(), bytes.end());
  return wrap_hll_sketch(hll_sketch_t::deserialize(buffer.data(), buffer.size()));
}
