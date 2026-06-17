#include <cstdint>
#include <memory>
#include <string>
#include <vector>

#include <cpp11.hpp>

#include <R_ext/Utils.h> // R_CheckUserInterrupt

#include "var_opt_sketch.hpp"
#include "var_opt_union.hpp"

namespace {

using vo_double_t = datasketches::var_opt_sketch<double>;
using vo_string_t = datasketches::var_opt_sketch<std::string>;
using vo_double_union_t = datasketches::var_opt_union<double>;
using vo_string_union_t = datasketches::var_opt_union<std::string>;

// A VarOpt sketch samples either numeric (double) or character (std::string)
// items; the item type is fixed at creation and exactly one of `d`/`s` is
// non-null for the lifetime of the holder.
struct vo_holder {
  std::unique_ptr<vo_double_t> d;
  std::unique_ptr<vo_string_t> s;
};

using vo_ptr = cpp11::external_pointer<vo_holder>;

SEXP vo_sketch_tag() {
  return Rf_install("data.sketches::var_opt_sketch");
}

bool vo_sketch_is_valid_xptr(cpp11::sexp sketch) {
  SEXP sketch_sexp = static_cast<SEXP>(sketch);
  if (
    TYPEOF(sketch_sexp) != EXTPTRSXP ||
    R_ExternalPtrTag(sketch_sexp) != vo_sketch_tag()
  ) {
    return false;
  }

  vo_ptr ptr(sketch);
  return ptr.get() != nullptr && (ptr->d != nullptr || ptr->s != nullptr);
}

vo_holder& vo_holder_from_xptr(cpp11::sexp sketch) {
  if (!vo_sketch_is_valid_xptr(sketch)) {
    cpp11::stop("`sketch` is not a valid VarOpt sketch.");
  }

  vo_ptr ptr(sketch);
  return *ptr;
}

cpp11::sexp wrap_vo_sketch(std::unique_ptr<vo_double_t> sk) {
  vo_ptr ptr(new vo_holder{std::move(sk), nullptr});
  SEXP out = static_cast<SEXP>(ptr);
  R_SetExternalPtrTag(out, vo_sketch_tag());
  return out;
}

cpp11::sexp wrap_vo_sketch(std::unique_ptr<vo_string_t> sk) {
  vo_ptr ptr(new vo_holder{nullptr, std::move(sk)});
  SEXP out = static_cast<SEXP>(ptr);
  R_SetExternalPtrTag(out, vo_sketch_tag());
  return out;
}

} // namespace

[[cpp11::register]]
cpp11::sexp vo_create_cpp(int k, bool is_string) {
  if (is_string) {
    return wrap_vo_sketch(std::make_unique<vo_string_t>(static_cast<uint32_t>(k)));
  }
  return wrap_vo_sketch(std::make_unique<vo_double_t>(static_cast<uint32_t>(k)));
}

[[cpp11::register]]
bool vo_is_valid_cpp(cpp11::sexp sketch) {
  return vo_sketch_is_valid_xptr(sketch);
}

[[cpp11::register]]
bool vo_is_string_cpp(cpp11::sexp sketch) {
  return vo_holder_from_xptr(sketch).s != nullptr;
}

[[cpp11::register]]
void vo_update_doubles_cpp(cpp11::sexp sketch, cpp11::doubles items, cpp11::doubles weights) {
  auto& holder = vo_holder_from_xptr(sketch);
  if (!holder.d) {
    cpp11::stop("`sketch` does not hold numeric items.");
  }

  const R_xlen_t n = items.size();
  const R_xlen_t m = weights.size();
  for (R_xlen_t i = 0; i < n; ++i) {
    if ((i & 0xFFFF) == 0) {
      R_CheckUserInterrupt();
    }
    holder.d->update(items[i], weights[i % m]);
  }
}

[[cpp11::register]]
void vo_update_strings_cpp(cpp11::sexp sketch, cpp11::strings items, cpp11::doubles weights) {
  auto& holder = vo_holder_from_xptr(sketch);
  if (!holder.s) {
    cpp11::stop("`sketch` does not hold character items.");
  }

  const R_xlen_t n = items.size();
  const R_xlen_t m = weights.size();
  for (R_xlen_t i = 0; i < n; ++i) {
    if ((i & 0xFFFF) == 0) {
      R_CheckUserInterrupt();
    }
    holder.s->update(static_cast<std::string>(items[i]), weights[i % m]);
  }
}

[[cpp11::register]]
int vo_get_k_cpp(cpp11::sexp sketch) {
  auto& holder = vo_holder_from_xptr(sketch);
  return static_cast<int>(holder.d ? holder.d->get_k() : holder.s->get_k());
}

[[cpp11::register]]
double vo_get_n_cpp(cpp11::sexp sketch) {
  auto& holder = vo_holder_from_xptr(sketch);
  return static_cast<double>(holder.d ? holder.d->get_n() : holder.s->get_n());
}

[[cpp11::register]]
int vo_get_num_samples_cpp(cpp11::sexp sketch) {
  auto& holder = vo_holder_from_xptr(sketch);
  return static_cast<int>(holder.d ? holder.d->get_num_samples() : holder.s->get_num_samples());
}

[[cpp11::register]]
bool vo_is_empty_cpp(cpp11::sexp sketch) {
  auto& holder = vo_holder_from_xptr(sketch);
  return holder.d ? holder.d->is_empty() : holder.s->is_empty();
}

// Returns a list(item = <doubles or strings>, weight = <doubles>) with one
// row per retained sample, in the same order as `estimate_subset_sum()`'s
// internal predicate-call order (H region, then R region with weight
// correction applied via the const_iterator).
[[cpp11::register]]
cpp11::list vo_samples_doubles_cpp(cpp11::sexp sketch) {
  using namespace cpp11::literals;
  auto& holder = vo_holder_from_xptr(sketch);
  if (!holder.d) {
    cpp11::stop("`sketch` does not hold numeric items.");
  }

  cpp11::writable::doubles items;
  cpp11::writable::doubles weights;
  for (const auto& entry : *holder.d) {
    items.push_back(entry.first);
    weights.push_back(entry.second);
  }

  cpp11::writable::list out;
  out.push_back("item"_nm = items);
  out.push_back("weight"_nm = weights);
  return out;
}

[[cpp11::register]]
cpp11::list vo_samples_strings_cpp(cpp11::sexp sketch) {
  using namespace cpp11::literals;
  auto& holder = vo_holder_from_xptr(sketch);
  if (!holder.s) {
    cpp11::stop("`sketch` does not hold character items.");
  }

  cpp11::writable::strings items;
  cpp11::writable::doubles weights;
  for (const auto& entry : *holder.s) {
    items.push_back(entry.first);
    weights.push_back(entry.second);
  }

  cpp11::writable::list out;
  out.push_back("item"_nm = items);
  out.push_back("weight"_nm = weights);
  return out;
}

// `indicator` has one element per retained sample (same order as
// `$samples()`), `TRUE` where the predicate matches. Returns
// list(lower_bound, estimate, upper_bound, total_weight).
[[cpp11::register]]
cpp11::list vo_estimate_subset_sum_cpp(cpp11::sexp sketch, cpp11::logicals indicator) {
  using namespace cpp11::literals;
  auto& holder = vo_holder_from_xptr(sketch);

  R_xlen_t i = 0;
  auto predicate = [&](const auto&) {
    return indicator[i++] != FALSE;
  };

  datasketches::subset_summary result = holder.d
    ? holder.d->estimate_subset_sum(predicate)
    : holder.s->estimate_subset_sum(predicate);

  cpp11::writable::list out;
  out.push_back("lower_bound"_nm = result.lower_bound);
  out.push_back("estimate"_nm = result.estimate);
  out.push_back("upper_bound"_nm = result.upper_bound);
  out.push_back("total_weight"_nm = result.total_sketch_weight);
  return out;
}

// VarOpt has no direct merge(); two sketches are combined by feeding both
// into a union sized for the larger configured `k`, and replacing the
// receiver's state with the union result.
[[cpp11::register]]
void vo_merge_cpp(cpp11::sexp sketch, cpp11::sexp other, int max_k) {
  auto& a = vo_holder_from_xptr(sketch);
  auto& b = vo_holder_from_xptr(other);

  if (a.d) {
    vo_double_union_t u(static_cast<uint32_t>(max_k));
    u.update(*a.d);
    u.update(*b.d);
    a.d = std::make_unique<vo_double_t>(u.get_result());
  } else {
    vo_string_union_t u(static_cast<uint32_t>(max_k));
    u.update(*a.s);
    u.update(*b.s);
    a.s = std::make_unique<vo_string_t>(u.get_result());
  }
}

// Set operation: a top-level function that combines two VarOpt sketches into
// a new result sketch, without mutating either input.
[[cpp11::register]]
cpp11::sexp vo_union_cpp(cpp11::sexp a, cpp11::sexp b, int max_k) {
  auto& ha = vo_holder_from_xptr(a);
  auto& hb = vo_holder_from_xptr(b);

  if (ha.d) {
    vo_double_union_t u(static_cast<uint32_t>(max_k));
    u.update(*ha.d);
    u.update(*hb.d);
    return wrap_vo_sketch(std::make_unique<vo_double_t>(u.get_result()));
  }
  vo_string_union_t u(static_cast<uint32_t>(max_k));
  u.update(*ha.s);
  u.update(*hb.s);
  return wrap_vo_sketch(std::make_unique<vo_string_t>(u.get_result()));
}

[[cpp11::register]]
std::string vo_to_string_cpp(cpp11::sexp sketch, bool print_items) {
  auto& holder = vo_holder_from_xptr(sketch);
  std::string out = holder.d ? holder.d->to_string() : holder.s->to_string();
  if (print_items) {
    out += holder.d ? holder.d->items_to_string() : holder.s->items_to_string();
  }
  return out;
}

[[cpp11::register]]
cpp11::raws vo_serialize_cpp(cpp11::sexp sketch) {
  auto& holder = vo_holder_from_xptr(sketch);

  std::vector<uint8_t> bytes;
  if (holder.d) {
    bytes.push_back(0);
    auto vb = holder.d->serialize();
    bytes.insert(bytes.end(), vb.begin(), vb.end());
  } else {
    bytes.push_back(1);
    auto vb = holder.s->serialize();
    bytes.insert(bytes.end(), vb.begin(), vb.end());
  }

  cpp11::writable::raws out(bytes.size());
  std::copy(bytes.begin(), bytes.end(), out.begin());
  return out;
}

// `bytes` is a one-byte item-type tag (0 = double, 1 = character) followed by
// the native serialized payload.
[[cpp11::register]]
cpp11::sexp vo_deserialize_cpp(cpp11::raws bytes) {
  if (bytes.size() < 1) {
    cpp11::stop("`bytes` is too short to be a valid VarOpt sketch payload.");
  }

  const uint8_t tag = static_cast<uint8_t>(bytes[0]);
  std::vector<uint8_t> body(bytes.begin() + 1, bytes.end());

  if (tag == 0) {
    auto sk = vo_double_t::deserialize(body.data(), body.size());
    return wrap_vo_sketch(std::make_unique<vo_double_t>(std::move(sk)));
  }
  if (tag == 1) {
    auto sk = vo_string_t::deserialize(body.data(), body.size());
    return wrap_vo_sketch(std::make_unique<vo_string_t>(std::move(sk)));
  }
  cpp11::stop("Unrecognized item-type tag in `bytes`.");
}
