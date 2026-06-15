#include <algorithm>
#include <cstdint>
#include <memory>
#include <string>
#include <vector>

#include <cpp11.hpp>
#include <cpp11/matrix.hpp>

#include <R_ext/Utils.h> // R_CheckUserInterrupt

#include "array_of_doubles_sketch.hpp"
#include "native_utils.h"

// `tuple_sketch<array<double>, ...>::to_string(true)` formats each retained
// entry's value via `operator<<`, which `array<double>` does not provide.
// Found via ADL when `to_string()` is instantiated below.
namespace datasketches {
inline std::ostream& operator<<(std::ostream& os, const array<double>& arr) {
  os << "[";
  for (uint8_t i = 0; i < arr.size(); ++i) {
    if (i > 0) os << ", ";
    os << arr[i];
  }
  os << "]";
  return os;
}
} // namespace datasketches

namespace {

// `tuple_sketch<Summary, Allocator>` defaults `Allocator` to
// `std::allocator<Summary>` (i.e. `std::allocator<array<double>>`), but
// `update_array_of_doubles_sketch` / `compact_array_of_doubles_sketch`
// extend `tuple_sketch<array<double>, array<double>::allocator_type>`
// (= `std::allocator<double>`). Spell out the allocator explicitly so this
// abstract base matches their actual base class.
using tuple_t =
  datasketches::tuple_sketch<datasketches::array<double>, std::allocator<double>>;
using update_aod_t = datasketches::update_array_of_doubles_sketch;
using compact_aod_t = datasketches::compact_array_of_doubles_sketch;
using update_policy_t = datasketches::default_array_of_doubles_update_policy;
using union_policy_t = datasketches::default_array_of_doubles_union_policy;
using aod_union_t = datasketches::array_of_doubles_union;
using aod_intersection_t = datasketches::array_of_doubles_intersection<union_policy_t>;
// `array_tuple_a_not_b<Array>::compute()` builds its result via the private
// `compact_array_tuple_sketch(uint8_t num_values, Base&& base)` constructor,
// which is only reachable through `array_tuple_a_not_b` itself (a `friend`).
// `compute()` calls `a.get_num_values()`, which the abstract `tuple_t` base
// doesn't expose, so `sa` is dynamic_cast to its concrete update/compact type
// before calling compute() below.
using aod_a_not_b_t =
  datasketches::array_tuple_a_not_b<datasketches::array<double>, std::allocator<double>>;

// An Array of Doubles sketch comes in two flavors that share a common
// abstract base: update_array_of_doubles_sketch (mutable, built via
// update()) and compact_array_of_doubles_sketch (immutable, the result of
// compact()/deserialize()/set operations). `num_values` is fixed at creation
// and cached alongside the pointer because the abstract base does not expose
// `get_num_values()`.
struct aod_holder {
  std::unique_ptr<tuple_t> sk;
  uint8_t num_values;
};

using aod_ptr = cpp11::external_pointer<aod_holder>;

SEXP aod_sketch_tag() {
  return Rf_install("data.sketches::array_of_doubles_sketch");
}

bool aod_sketch_is_valid_xptr(cpp11::sexp sketch) {
  SEXP sketch_sexp = static_cast<SEXP>(sketch);
  if (
    TYPEOF(sketch_sexp) != EXTPTRSXP ||
    R_ExternalPtrTag(sketch_sexp) != aod_sketch_tag()
  ) {
    return false;
  }

  aod_ptr ptr(sketch);
  return ptr.get() != nullptr && ptr->sk != nullptr;
}

aod_holder& aod_holder_from_xptr(cpp11::sexp sketch) {
  if (!aod_sketch_is_valid_xptr(sketch)) {
    cpp11::stop("`sketch` is not a valid Array of Doubles sketch.");
  }

  aod_ptr ptr(sketch);
  return *ptr;
}

tuple_t& aod_sketch_from_xptr(cpp11::sexp sketch) {
  return *aod_holder_from_xptr(sketch).sk;
}

cpp11::sexp wrap_aod_sketch(std::unique_ptr<tuple_t> sk, int num_values) {
  aod_ptr ptr(new aod_holder{std::move(sk), static_cast<uint8_t>(num_values)});
  SEXP out = static_cast<SEXP>(ptr);
  R_SetExternalPtrTag(out, aod_sketch_tag());
  return out;
}

} // namespace

[[cpp11::register]]
cpp11::sexp aod_create_cpp(int lg_k, int num_values, double seed) {
  const uint64_t seed_u64 = data_sketches_native::checked_uint64_from_double(seed, "seed");
  auto policy = update_policy_t(static_cast<uint8_t>(num_values));
  auto sk = update_aod_t::builder(policy)
    .set_lg_k(static_cast<uint8_t>(lg_k))
    .set_seed(seed_u64)
    .build();
  return wrap_aod_sketch(
    std::make_unique<update_aod_t>(std::move(sk)),
    num_values
  );
}

[[cpp11::register]]
bool aod_is_valid_cpp(cpp11::sexp sketch) {
  return aod_sketch_is_valid_xptr(sketch);
}

[[cpp11::register]]
bool aod_is_compact_cpp(cpp11::sexp sketch) {
  auto& sk = aod_sketch_from_xptr(sketch);
  return dynamic_cast<update_aod_t*>(&sk) == nullptr;
}

[[cpp11::register]]
void aod_update_doubles_cpp(
  cpp11::sexp sketch,
  cpp11::doubles keys,
  cpp11::doubles_matrix<cpp11::by_row> values
) {
  aod_holder& holder = aod_holder_from_xptr(sketch);
  auto* upd = dynamic_cast<update_aod_t*>(holder.sk.get());
  if (upd == nullptr) {
    cpp11::stop("`sketch` is a compact sketch and cannot be updated.");
  }

  const R_xlen_t n = keys.size();
  std::vector<double> value(holder.num_values);
  for (R_xlen_t i = 0; i < n; ++i) {
    if ((i & 0xFFFF) == 0) {
      R_CheckUserInterrupt();
    }
    for (uint8_t j = 0; j < holder.num_values; ++j) {
      value[j] = values(i, j);
    }
    upd->update(keys[i], value);
  }
}

[[cpp11::register]]
void aod_update_strings_cpp(
  cpp11::sexp sketch,
  cpp11::strings keys,
  cpp11::doubles_matrix<cpp11::by_row> values
) {
  aod_holder& holder = aod_holder_from_xptr(sketch);
  auto* upd = dynamic_cast<update_aod_t*>(holder.sk.get());
  if (upd == nullptr) {
    cpp11::stop("`sketch` is a compact sketch and cannot be updated.");
  }

  const R_xlen_t n = keys.size();
  std::vector<double> value(holder.num_values);
  for (R_xlen_t i = 0; i < n; ++i) {
    if ((i & 0xFFFF) == 0) {
      R_CheckUserInterrupt();
    }
    for (uint8_t j = 0; j < holder.num_values; ++j) {
      value[j] = values(i, j);
    }
    upd->update(static_cast<std::string>(keys[i]), value);
  }
}

[[cpp11::register]]
int aod_get_lg_k_cpp(cpp11::sexp sketch) {
  auto& sk = aod_sketch_from_xptr(sketch);
  auto* upd = dynamic_cast<update_aod_t*>(&sk);
  if (upd == nullptr) {
    cpp11::stop("`lg_k` is not defined for a compact Array of Doubles sketch.");
  }
  return upd->get_lg_k();
}

[[cpp11::register]]
int aod_get_num_values_cpp(cpp11::sexp sketch) {
  return aod_holder_from_xptr(sketch).num_values;
}

// Array of Doubles has no direct merge(); two sketches are combined by
// feeding both into a union with the given `lg_k`/`seed` and a policy that
// sums the value arrays element-wise, and replacing the receiver's state with
// the (compact) union result. This freezes the receiver into compact form: it
// can no longer be updated after merge().
[[cpp11::register]]
void aod_merge_cpp(cpp11::sexp sketch, cpp11::sexp other, int lg_k, double seed) {
  aod_holder& holder = aod_holder_from_xptr(sketch);
  auto& sa = *holder.sk;
  auto& sb = aod_sketch_from_xptr(other);
  const uint64_t seed_u64 = data_sketches_native::checked_uint64_from_double(seed, "seed");

  auto policy = union_policy_t(holder.num_values);
  auto u = aod_union_t::builder(policy)
    .set_lg_k(static_cast<uint8_t>(lg_k))
    .set_seed(seed_u64)
    .build();
  u.update(sa);
  u.update(sb);

  holder.sk = std::make_unique<compact_aod_t>(u.get_result(true));
}

[[cpp11::register]]
double aod_get_estimate_cpp(cpp11::sexp sketch) {
  return aod_sketch_from_xptr(sketch).get_estimate();
}

[[cpp11::register]]
double aod_get_lower_bound_cpp(cpp11::sexp sketch, int num_std_dev) {
  return aod_sketch_from_xptr(sketch).get_lower_bound(
    static_cast<uint8_t>(num_std_dev)
  );
}

[[cpp11::register]]
double aod_get_upper_bound_cpp(cpp11::sexp sketch, int num_std_dev) {
  return aod_sketch_from_xptr(sketch).get_upper_bound(
    static_cast<uint8_t>(num_std_dev)
  );
}

[[cpp11::register]]
bool aod_is_empty_cpp(cpp11::sexp sketch) {
  return aod_sketch_from_xptr(sketch).is_empty();
}

[[cpp11::register]]
bool aod_is_estimation_mode_cpp(cpp11::sexp sketch) {
  return aod_sketch_from_xptr(sketch).is_estimation_mode();
}

[[cpp11::register]]
double aod_get_theta_cpp(cpp11::sexp sketch) {
  return aod_sketch_from_xptr(sketch).get_theta();
}

[[cpp11::register]]
int aod_get_num_retained_cpp(cpp11::sexp sketch) {
  return static_cast<int>(aod_sketch_from_xptr(sketch).get_num_retained());
}

[[cpp11::register]]
bool aod_is_ordered_cpp(cpp11::sexp sketch) {
  return aod_sketch_from_xptr(sketch).is_ordered();
}

// Estimated sum of each value column over the full input stream: the sum of
// retained values for that column, scaled by `1 / theta`.
[[cpp11::register]]
cpp11::doubles aod_column_sums_cpp(cpp11::sexp sketch) {
  aod_holder& holder = aod_holder_from_xptr(sketch);
  std::vector<double> sums(holder.num_values, 0.0);
  for (auto& entry : *holder.sk) {
    for (uint8_t j = 0; j < holder.num_values; ++j) {
      sums[j] += entry.second[j];
    }
  }
  const double theta = holder.sk->get_theta();
  if (theta > 0 && theta < 1) {
    for (auto& s : sums) {
      s /= theta;
    }
  }
  cpp11::writable::doubles out(sums.begin(), sums.end());
  return out;
}

[[cpp11::register]]
std::string aod_to_string_cpp(cpp11::sexp sketch, bool print_items) {
  return aod_sketch_from_xptr(sketch).to_string(print_items);
}

[[cpp11::register]]
cpp11::raws aod_serialize_cpp(cpp11::sexp sketch) {
  auto& sk = aod_sketch_from_xptr(sketch);

  std::vector<uint8_t> bytes;
  auto* upd = dynamic_cast<update_aod_t*>(&sk);
  if (upd != nullptr) {
    auto compact = upd->compact(true);
    auto vb = compact.serialize();
    bytes.assign(vb.begin(), vb.end());
  } else {
    auto* cmp = dynamic_cast<compact_aod_t*>(&sk);
    auto vb = cmp->serialize();
    bytes.assign(vb.begin(), vb.end());
  }

  cpp11::writable::raws out(bytes.size());
  std::copy(bytes.begin(), bytes.end(), out.begin());
  return out;
}

[[cpp11::register]]
cpp11::sexp aod_deserialize_cpp(cpp11::raws bytes, double seed) {
  const uint64_t seed_u64 = data_sketches_native::checked_uint64_from_double(seed, "seed");
  std::vector<uint8_t> buffer(bytes.begin(), bytes.end());
  auto sk = compact_aod_t::deserialize(
    buffer.data(),
    buffer.size(),
    seed_u64
  );
  const int num_values = sk.get_num_values();
  return wrap_aod_sketch(std::make_unique<compact_aod_t>(std::move(sk)), num_values);
}

// Set operations: top-level functions that combine two (possibly update or
// compact) Array of Doubles sketches into a new compact-sketch result,
// without mutating either input. Value arrays for matching keys are combined
// element-wise by summation (`union`/`intersection`); `a_not_b` keeps `a`'s
// values for the retained entries unchanged.

[[cpp11::register]]
cpp11::sexp aod_union_cpp(cpp11::sexp a, cpp11::sexp b, int lg_k, double seed, int num_values) {
  auto& sa = aod_sketch_from_xptr(a);
  auto& sb = aod_sketch_from_xptr(b);
  const uint64_t seed_u64 = data_sketches_native::checked_uint64_from_double(seed, "seed");

  auto policy = union_policy_t(static_cast<uint8_t>(num_values));
  auto u = aod_union_t::builder(policy)
    .set_lg_k(static_cast<uint8_t>(lg_k))
    .set_seed(seed_u64)
    .build();
  u.update(sa);
  u.update(sb);

  return wrap_aod_sketch(std::make_unique<compact_aod_t>(u.get_result(true)), num_values);
}

[[cpp11::register]]
cpp11::sexp aod_intersection_cpp(cpp11::sexp a, cpp11::sexp b, double seed, int num_values) {
  auto& sa = aod_sketch_from_xptr(a);
  auto& sb = aod_sketch_from_xptr(b);
  const uint64_t seed_u64 = data_sketches_native::checked_uint64_from_double(seed, "seed");

  aod_intersection_t inter(
    seed_u64,
    union_policy_t(static_cast<uint8_t>(num_values))
  );
  inter.update(sa);
  inter.update(sb);

  return wrap_aod_sketch(std::make_unique<compact_aod_t>(inter.get_result(true)), num_values);
}

[[cpp11::register]]
cpp11::sexp aod_a_not_b_cpp(cpp11::sexp a, cpp11::sexp b, double seed, int num_values) {
  auto& sa = aod_sketch_from_xptr(a);
  auto& sb = aod_sketch_from_xptr(b);
  const uint64_t seed_u64 = data_sketches_native::checked_uint64_from_double(seed, "seed");

  aod_a_not_b_t a_not_b(seed_u64);
  if (auto* upd = dynamic_cast<update_aod_t*>(&sa)) {
    return wrap_aod_sketch(
      std::make_unique<compact_aod_t>(a_not_b.compute(*upd, sb, true)),
      num_values
    );
  }
  auto* cmp = dynamic_cast<compact_aod_t*>(&sa);
  return wrap_aod_sketch(
    std::make_unique<compact_aod_t>(a_not_b.compute(*cmp, sb, true)),
    num_values
  );
}
