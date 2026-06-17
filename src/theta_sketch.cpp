#include <algorithm>
#include <cstdint>
#include <memory>
#include <string>
#include <vector>

#include <cpp11.hpp>

#include <R_ext/Utils.h> // R_CheckUserInterrupt

#include "theta_sketch.hpp"
#include "theta_union.hpp"
#include "theta_intersection.hpp"
#include "theta_a_not_b.hpp"
#include "theta_jaccard_similarity.hpp"
#include "native_utils.h"

namespace {

using theta_sketch_t = datasketches::theta_sketch;
using update_theta_sketch_t = datasketches::update_theta_sketch;
using compact_theta_sketch_t = datasketches::compact_theta_sketch;
using theta_union_t = datasketches::theta_union;
using theta_intersection_t = datasketches::theta_intersection;
using theta_a_not_b_t = datasketches::theta_a_not_b;
using theta_jaccard_t = datasketches::theta_jaccard_similarity;

// Theta sketches come in two flavors that share a common abstract base:
// update_theta_sketch (mutable, built via update()) and
// compact_theta_sketch (immutable, the result of compact()/deserialize()/set
// operations). The external pointer holds the abstract base by unique_ptr so
// a single R6 class can represent either; `merge()` and set operations
// replace the held pointer in place (freezing the receiver into compact
// form).
struct theta_holder {
  std::unique_ptr<theta_sketch_t> sk;
};

using theta_ptr = cpp11::external_pointer<theta_holder>;

SEXP theta_sketch_tag() {
  return Rf_install("data.sketches::theta_sketch");
}

bool theta_sketch_is_valid_xptr(cpp11::sexp sketch) {
  SEXP sketch_sexp = static_cast<SEXP>(sketch);
  if (
    TYPEOF(sketch_sexp) != EXTPTRSXP ||
    R_ExternalPtrTag(sketch_sexp) != theta_sketch_tag()
  ) {
    return false;
  }

  theta_ptr ptr(sketch);
  return ptr.get() != nullptr && ptr->sk != nullptr;
}

theta_holder& theta_holder_from_xptr(cpp11::sexp sketch) {
  if (!theta_sketch_is_valid_xptr(sketch)) {
    cpp11::stop("`sketch` is not a valid Theta sketch.");
  }

  theta_ptr ptr(sketch);
  return *ptr;
}

theta_sketch_t& theta_sketch_from_xptr(cpp11::sexp sketch) {
  return *theta_holder_from_xptr(sketch).sk;
}

cpp11::sexp wrap_theta_sketch(std::unique_ptr<theta_sketch_t> sk) {
  theta_ptr ptr(new theta_holder{std::move(sk)});
  SEXP out = static_cast<SEXP>(ptr);
  R_SetExternalPtrTag(out, theta_sketch_tag());
  return out;
}

} // namespace

[[cpp11::register]]
cpp11::sexp theta_create_cpp(int lg_k, double seed) {
  const uint64_t seed_u64 = data_sketches_native::checked_uint64_from_double(seed, "seed");
  auto sk = update_theta_sketch_t::builder()
    .set_lg_k(static_cast<uint8_t>(lg_k))
    .set_seed(seed_u64)
    .build();
  return wrap_theta_sketch(std::make_unique<update_theta_sketch_t>(std::move(sk)));
}

[[cpp11::register]]
bool theta_is_valid_cpp(cpp11::sexp sketch) {
  return theta_sketch_is_valid_xptr(sketch);
}

[[cpp11::register]]
bool theta_is_compact_cpp(cpp11::sexp sketch) {
  auto& sk = theta_sketch_from_xptr(sketch);
  return dynamic_cast<update_theta_sketch_t*>(&sk) == nullptr;
}

[[cpp11::register]]
void theta_update_doubles_cpp(cpp11::sexp sketch, cpp11::doubles values) {
  auto& sk = theta_sketch_from_xptr(sketch);
  auto* upd = dynamic_cast<update_theta_sketch_t*>(&sk);
  if (upd == nullptr) {
    cpp11::stop("`sketch` is a compact Theta sketch and cannot be updated.");
  }
  const double* p = REAL(values.data());
  const R_xlen_t n = values.size();
  for (R_xlen_t i = 0; i < n; ++i) {
    if ((i & 0xFFFF) == 0) {
      R_CheckUserInterrupt();
    }
    upd->update(p[i]);
  }
}

[[cpp11::register]]
void theta_update_strings_cpp(cpp11::sexp sketch, cpp11::strings values) {
  auto& sk = theta_sketch_from_xptr(sketch);
  auto* upd = dynamic_cast<update_theta_sketch_t*>(&sk);
  if (upd == nullptr) {
    cpp11::stop("`sketch` is a compact Theta sketch and cannot be updated.");
  }
  const R_xlen_t n = values.size();
  for (R_xlen_t i = 0; i < n; ++i) {
    if ((i & 0xFFFF) == 0) {
      R_CheckUserInterrupt();
    }
    upd->update(static_cast<std::string>(values[i]));
  }
}

[[cpp11::register]]
int theta_get_lg_k_cpp(cpp11::sexp sketch) {
  auto& sk = theta_sketch_from_xptr(sketch);
  auto* upd = dynamic_cast<update_theta_sketch_t*>(&sk);
  if (upd == nullptr) {
    cpp11::stop("`lg_k` is not defined for a compact Theta sketch.");
  }
  return upd->get_lg_k();
}

// Theta has no direct merge(); two sketches are combined by feeding both into
// a union with the given `lg_k`/`seed`, and replacing the receiver's state
// with the (compact) union result. This freezes the receiver into compact
// form: it can no longer be updated after merge().
[[cpp11::register]]
void theta_merge_cpp(cpp11::sexp sketch, cpp11::sexp other, int lg_k, double seed) {
  theta_holder& holder = theta_holder_from_xptr(sketch);
  auto& sa = *holder.sk;
  auto& sb = theta_sketch_from_xptr(other);
  const uint64_t seed_u64 = data_sketches_native::checked_uint64_from_double(seed, "seed");

  auto u = theta_union_t::builder()
    .set_lg_k(static_cast<uint8_t>(lg_k))
    .set_seed(seed_u64)
    .build();
  u.update(sa);
  u.update(sb);

  holder.sk = std::make_unique<compact_theta_sketch_t>(u.get_result(true));
}

[[cpp11::register]]
double theta_get_estimate_cpp(cpp11::sexp sketch) {
  return theta_sketch_from_xptr(sketch).get_estimate();
}

[[cpp11::register]]
double theta_get_lower_bound_cpp(cpp11::sexp sketch, int num_std_dev) {
  return theta_sketch_from_xptr(sketch).get_lower_bound(
    static_cast<uint8_t>(num_std_dev)
  );
}

[[cpp11::register]]
double theta_get_upper_bound_cpp(cpp11::sexp sketch, int num_std_dev) {
  return theta_sketch_from_xptr(sketch).get_upper_bound(
    static_cast<uint8_t>(num_std_dev)
  );
}

[[cpp11::register]]
bool theta_is_empty_cpp(cpp11::sexp sketch) {
  return theta_sketch_from_xptr(sketch).is_empty();
}

[[cpp11::register]]
bool theta_is_estimation_mode_cpp(cpp11::sexp sketch) {
  return theta_sketch_from_xptr(sketch).is_estimation_mode();
}

[[cpp11::register]]
double theta_get_theta_cpp(cpp11::sexp sketch) {
  return theta_sketch_from_xptr(sketch).get_theta();
}

[[cpp11::register]]
int theta_get_num_retained_cpp(cpp11::sexp sketch) {
  return static_cast<int>(theta_sketch_from_xptr(sketch).get_num_retained());
}

[[cpp11::register]]
int theta_get_seed_hash_cpp(cpp11::sexp sketch) {
  return static_cast<int>(theta_sketch_from_xptr(sketch).get_seed_hash());
}

[[cpp11::register]]
bool theta_is_ordered_cpp(cpp11::sexp sketch) {
  return theta_sketch_from_xptr(sketch).is_ordered();
}

[[cpp11::register]]
std::string theta_to_string_cpp(cpp11::sexp sketch, bool print_items) {
  return theta_sketch_from_xptr(sketch).to_string(print_items);
}

[[cpp11::register]]
cpp11::raws theta_serialize_cpp(cpp11::sexp sketch) {
  auto& sk = theta_sketch_from_xptr(sketch);

  std::vector<uint8_t> bytes;
  auto* upd = dynamic_cast<update_theta_sketch_t*>(&sk);
  if (upd != nullptr) {
    auto compact = upd->compact(true);
    auto vb = compact.serialize_compressed();
    bytes.assign(vb.begin(), vb.end());
  } else {
    auto* cmp = dynamic_cast<compact_theta_sketch_t*>(&sk);
    auto vb = cmp->serialize_compressed();
    bytes.assign(vb.begin(), vb.end());
  }

  cpp11::writable::raws out(bytes.size());
  std::copy(bytes.begin(), bytes.end(), out.begin());
  return out;
}

[[cpp11::register]]
cpp11::sexp theta_deserialize_cpp(cpp11::raws bytes, double seed) {
  const uint64_t seed_u64 = data_sketches_native::checked_uint64_from_double(seed, "seed");
  std::vector<uint8_t> buffer(bytes.begin(), bytes.end());
  auto sk = compact_theta_sketch_t::deserialize(
    buffer.data(),
    buffer.size(),
    seed_u64
  );
  return wrap_theta_sketch(std::make_unique<compact_theta_sketch_t>(std::move(sk)));
}

// Set operations: top-level functions that combine two (possibly update or
// compact) Theta sketches into a new compact-sketch result, without mutating
// either input.

[[cpp11::register]]
cpp11::sexp theta_union_cpp(cpp11::sexp a, cpp11::sexp b, int lg_k, double seed) {
  auto& sa = theta_sketch_from_xptr(a);
  auto& sb = theta_sketch_from_xptr(b);
  const uint64_t seed_u64 = data_sketches_native::checked_uint64_from_double(seed, "seed");

  auto u = theta_union_t::builder()
    .set_lg_k(static_cast<uint8_t>(lg_k))
    .set_seed(seed_u64)
    .build();
  u.update(sa);
  u.update(sb);

  return wrap_theta_sketch(std::make_unique<compact_theta_sketch_t>(u.get_result(true)));
}

[[cpp11::register]]
cpp11::sexp theta_intersection_cpp(cpp11::sexp a, cpp11::sexp b, double seed) {
  auto& sa = theta_sketch_from_xptr(a);
  auto& sb = theta_sketch_from_xptr(b);
  const uint64_t seed_u64 = data_sketches_native::checked_uint64_from_double(seed, "seed");

  theta_intersection_t inter(seed_u64);
  inter.update(sa);
  inter.update(sb);

  return wrap_theta_sketch(std::make_unique<compact_theta_sketch_t>(inter.get_result(true)));
}

[[cpp11::register]]
cpp11::sexp theta_a_not_b_cpp(cpp11::sexp a, cpp11::sexp b, double seed) {
  auto& sa = theta_sketch_from_xptr(a);
  auto& sb = theta_sketch_from_xptr(b);
  const uint64_t seed_u64 = data_sketches_native::checked_uint64_from_double(seed, "seed");

  theta_a_not_b_t a_not_b(seed_u64);
  return wrap_theta_sketch(
    std::make_unique<compact_theta_sketch_t>(a_not_b.compute(sa, sb, true))
  );
}

[[cpp11::register]]
cpp11::doubles theta_jaccard_cpp(cpp11::sexp a, cpp11::sexp b, double seed) {
  auto& sa = theta_sketch_from_xptr(a);
  auto& sb = theta_sketch_from_xptr(b);
  const uint64_t seed_u64 = data_sketches_native::checked_uint64_from_double(seed, "seed");

  auto result = theta_jaccard_t::jaccard(sa, sb, seed_u64);
  cpp11::writable::doubles out(3);
  out[0] = result[0];
  out[1] = result[1];
  out[2] = result[2];
  return out;
}
