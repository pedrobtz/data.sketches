#include <cstdint>
#include <memory>
#include <string>
#include <vector>

#include <cpp11.hpp>

#include <R_ext/Utils.h> // R_CheckUserInterrupt

#include "ebpps_sketch.hpp"

namespace {

using eb_double_t = datasketches::ebpps_sketch<double>;
using eb_string_t = datasketches::ebpps_sketch<std::string>;

// An EBPPS sketch samples either numeric (double) or character (std::string)
// items; the item type is fixed at creation and exactly one of `d`/`s` is
// non-null for the lifetime of the holder.
struct eb_holder {
  std::unique_ptr<eb_double_t> d;
  std::unique_ptr<eb_string_t> s;
};

using eb_ptr = cpp11::external_pointer<eb_holder>;

SEXP eb_sketch_tag() {
  return Rf_install("data.sketches::ebpps_sketch");
}

bool eb_sketch_is_valid_xptr(cpp11::sexp sketch) {
  SEXP sketch_sexp = static_cast<SEXP>(sketch);
  if (
    TYPEOF(sketch_sexp) != EXTPTRSXP ||
    R_ExternalPtrTag(sketch_sexp) != eb_sketch_tag()
  ) {
    return false;
  }

  eb_ptr ptr(sketch);
  return ptr.get() != nullptr && (ptr->d != nullptr || ptr->s != nullptr);
}

eb_holder& eb_holder_from_xptr(cpp11::sexp sketch) {
  if (!eb_sketch_is_valid_xptr(sketch)) {
    cpp11::stop("`sketch` is not a valid EBPPS sketch.");
  }

  eb_ptr ptr(sketch);
  return *ptr;
}

cpp11::sexp wrap_eb_sketch(std::unique_ptr<eb_double_t> sk) {
  eb_ptr ptr(new eb_holder{std::move(sk), nullptr});
  SEXP out = static_cast<SEXP>(ptr);
  R_SetExternalPtrTag(out, eb_sketch_tag());
  return out;
}

cpp11::sexp wrap_eb_sketch(std::unique_ptr<eb_string_t> sk) {
  eb_ptr ptr(new eb_holder{nullptr, std::move(sk)});
  SEXP out = static_cast<SEXP>(ptr);
  R_SetExternalPtrTag(out, eb_sketch_tag());
  return out;
}

} // namespace

[[cpp11::register]]
cpp11::sexp eb_create_cpp(int k, bool is_string) {
  if (is_string) {
    return wrap_eb_sketch(std::make_unique<eb_string_t>(static_cast<uint32_t>(k)));
  }
  return wrap_eb_sketch(std::make_unique<eb_double_t>(static_cast<uint32_t>(k)));
}

[[cpp11::register]]
bool eb_is_valid_cpp(cpp11::sexp sketch) {
  return eb_sketch_is_valid_xptr(sketch);
}

[[cpp11::register]]
bool eb_is_string_cpp(cpp11::sexp sketch) {
  return eb_holder_from_xptr(sketch).s != nullptr;
}

[[cpp11::register]]
void eb_update_doubles_cpp(cpp11::sexp sketch, cpp11::doubles items, cpp11::doubles weights) {
  auto& holder = eb_holder_from_xptr(sketch);
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
void eb_update_strings_cpp(cpp11::sexp sketch, cpp11::strings items, cpp11::doubles weights) {
  auto& holder = eb_holder_from_xptr(sketch);
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
int eb_get_k_cpp(cpp11::sexp sketch) {
  auto& holder = eb_holder_from_xptr(sketch);
  return static_cast<int>(holder.d ? holder.d->get_k() : holder.s->get_k());
}

[[cpp11::register]]
double eb_get_n_cpp(cpp11::sexp sketch) {
  auto& holder = eb_holder_from_xptr(sketch);
  return static_cast<double>(holder.d ? holder.d->get_n() : holder.s->get_n());
}

[[cpp11::register]]
double eb_get_cumulative_weight_cpp(cpp11::sexp sketch) {
  auto& holder = eb_holder_from_xptr(sketch);
  return holder.d ? holder.d->get_cumulative_weight() : holder.s->get_cumulative_weight();
}

[[cpp11::register]]
double eb_get_c_cpp(cpp11::sexp sketch) {
  auto& holder = eb_holder_from_xptr(sketch);
  return holder.d ? holder.d->get_c() : holder.s->get_c();
}

[[cpp11::register]]
bool eb_is_empty_cpp(cpp11::sexp sketch) {
  auto& holder = eb_holder_from_xptr(sketch);
  return holder.d ? holder.d->is_empty() : holder.s->is_empty();
}

[[cpp11::register]]
cpp11::doubles eb_result_doubles_cpp(cpp11::sexp sketch) {
  auto& holder = eb_holder_from_xptr(sketch);
  if (!holder.d) {
    cpp11::stop("`sketch` does not hold numeric items.");
  }

  auto result = holder.d->get_result();
  cpp11::writable::doubles out(result.begin(), result.end());
  return out;
}

[[cpp11::register]]
cpp11::strings eb_result_strings_cpp(cpp11::sexp sketch) {
  auto& holder = eb_holder_from_xptr(sketch);
  if (!holder.s) {
    cpp11::stop("`sketch` does not hold character items.");
  }

  auto result = holder.s->get_result();
  cpp11::writable::strings out(result.size());
  for (size_t i = 0; i < result.size(); ++i) {
    out[i] = result[i];
  }
  return out;
}

// Mutating merge: absorbs `other` into `sketch`. The native implementation
// merges the smaller-cumulative-weight sketch into the larger one and sets
// `k` to `min(a.k(), b.k())`.
[[cpp11::register]]
void eb_merge_cpp(cpp11::sexp sketch, cpp11::sexp other) {
  auto& a = eb_holder_from_xptr(sketch);
  auto& b = eb_holder_from_xptr(other);

  if (a.d) {
    a.d->merge(*b.d);
  } else {
    a.s->merge(*b.s);
  }
}

[[cpp11::register]]
std::string eb_to_string_cpp(cpp11::sexp sketch, bool print_items) {
  auto& holder = eb_holder_from_xptr(sketch);
  std::string out = holder.d ? holder.d->to_string() : holder.s->to_string();
  if (print_items) {
    out += holder.d ? holder.d->items_to_string() : holder.s->items_to_string();
  }
  return out;
}

[[cpp11::register]]
cpp11::raws eb_serialize_cpp(cpp11::sexp sketch) {
  auto& holder = eb_holder_from_xptr(sketch);

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
cpp11::sexp eb_deserialize_cpp(cpp11::raws bytes) {
  if (bytes.size() < 1) {
    cpp11::stop("`bytes` is too short to be a valid EBPPS sketch payload.");
  }

  const uint8_t tag = static_cast<uint8_t>(bytes[0]);
  std::vector<uint8_t> body(bytes.begin() + 1, bytes.end());

  if (tag == 0) {
    auto sk = eb_double_t::deserialize(body.data(), body.size());
    return wrap_eb_sketch(std::make_unique<eb_double_t>(std::move(sk)));
  }
  if (tag == 1) {
    auto sk = eb_string_t::deserialize(body.data(), body.size());
    return wrap_eb_sketch(std::make_unique<eb_string_t>(std::move(sk)));
  }
  cpp11::stop("Unrecognized item-type tag in `bytes`.");
}
