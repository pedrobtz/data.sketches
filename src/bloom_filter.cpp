#include <cstdint>
#include <string>
#include <vector>

#include <cpp11.hpp>

#include <R_ext/Utils.h> // R_CheckUserInterrupt

#include "bloom_filter.hpp"
#include "native_utils.h"

namespace {

using bf_t = datasketches::bloom_filter;
using bf_ptr = cpp11::external_pointer<bf_t>;

SEXP bf_tag() {
  return Rf_install("data.sketches::bloom_filter");
}

bool bf_is_valid_xptr(cpp11::sexp filter) {
  SEXP filter_sexp = static_cast<SEXP>(filter);
  if (
    TYPEOF(filter_sexp) != EXTPTRSXP ||
    R_ExternalPtrTag(filter_sexp) != bf_tag()
  ) {
    return false;
  }

  bf_ptr ptr(filter);
  return ptr.get() != nullptr;
}

bf_t& bf_from_xptr(cpp11::sexp filter) {
  if (!bf_is_valid_xptr(filter)) {
    cpp11::stop("`filter` is not a valid Bloom filter.");
  }

  bf_ptr ptr(filter);
  return *ptr;
}

cpp11::sexp wrap_bf(bf_t&& filter) {
  bf_ptr ptr(new bf_t(std::move(filter)));
  SEXP out = static_cast<SEXP>(ptr);
  R_SetExternalPtrTag(out, bf_tag());
  return out;
}

} // namespace

[[cpp11::register]]
cpp11::sexp bf_create_by_accuracy_cpp(double max_items, double fpp, double seed) {
  const uint64_t max_items_u64 =
    data_sketches_native::checked_uint64_from_double(max_items, "max_items", true);
  const uint64_t seed_u64 = data_sketches_native::checked_uint64_from_double(seed, "seed");
  return wrap_bf(datasketches::bloom_filter::builder::create_by_accuracy(
    max_items_u64,
    fpp,
    seed_u64
  ));
}

[[cpp11::register]]
cpp11::sexp bf_create_by_size_cpp(double num_bits, int num_hashes, double seed) {
  const uint64_t num_bits_u64 =
    data_sketches_native::checked_uint64_from_double(num_bits, "num_bits", true);
  const uint64_t seed_u64 = data_sketches_native::checked_uint64_from_double(seed, "seed");
  return wrap_bf(datasketches::bloom_filter::builder::create_by_size(
    num_bits_u64,
    static_cast<uint16_t>(num_hashes),
    seed_u64
  ));
}

[[cpp11::register]]
bool bf_is_valid_cpp(cpp11::sexp filter) {
  return bf_is_valid_xptr(filter);
}

[[cpp11::register]]
void bf_update_doubles_cpp(cpp11::sexp filter, cpp11::doubles items) {
  auto& f = bf_from_xptr(filter);
  const R_xlen_t n = items.size();
  for (R_xlen_t i = 0; i < n; ++i) {
    if ((i & 0xFFFF) == 0) {
      R_CheckUserInterrupt();
    }
    const double value = items[i];
    f.update(static_cast<const void*>(&value), sizeof(double));
  }
}

[[cpp11::register]]
void bf_update_strings_cpp(cpp11::sexp filter, cpp11::strings items) {
  auto& f = bf_from_xptr(filter);
  const R_xlen_t n = items.size();
  for (R_xlen_t i = 0; i < n; ++i) {
    if ((i & 0xFFFF) == 0) {
      R_CheckUserInterrupt();
    }
    f.update(static_cast<std::string>(items[i]));
  }
}

[[cpp11::register]]
cpp11::writable::logicals bf_query_doubles_cpp(cpp11::sexp filter, cpp11::doubles items) {
  auto& f = bf_from_xptr(filter);
  const R_xlen_t n = items.size();
  cpp11::writable::logicals out(n);
  for (R_xlen_t i = 0; i < n; ++i) {
    if ((i & 0xFFFF) == 0) {
      R_CheckUserInterrupt();
    }
    const double value = items[i];
    out[i] = f.query(static_cast<const void*>(&value), sizeof(double));
  }
  return out;
}

[[cpp11::register]]
cpp11::writable::logicals bf_query_strings_cpp(cpp11::sexp filter, cpp11::strings items) {
  auto& f = bf_from_xptr(filter);
  const R_xlen_t n = items.size();
  cpp11::writable::logicals out(n);
  for (R_xlen_t i = 0; i < n; ++i) {
    if ((i & 0xFFFF) == 0) {
      R_CheckUserInterrupt();
    }
    out[i] = f.query(static_cast<std::string>(items[i]));
  }
  return out;
}

// Returns the query result for each item *before* it is added to the filter.
[[cpp11::register]]
cpp11::writable::logicals bf_query_and_update_doubles_cpp(cpp11::sexp filter, cpp11::doubles items) {
  auto& f = bf_from_xptr(filter);
  const R_xlen_t n = items.size();
  cpp11::writable::logicals out(n);
  for (R_xlen_t i = 0; i < n; ++i) {
    if ((i & 0xFFFF) == 0) {
      R_CheckUserInterrupt();
    }
    const double value = items[i];
    out[i] = f.query_and_update(static_cast<const void*>(&value), sizeof(double));
  }
  return out;
}

[[cpp11::register]]
cpp11::writable::logicals bf_query_and_update_strings_cpp(cpp11::sexp filter, cpp11::strings items) {
  auto& f = bf_from_xptr(filter);
  const R_xlen_t n = items.size();
  cpp11::writable::logicals out(n);
  for (R_xlen_t i = 0; i < n; ++i) {
    if ((i & 0xFFFF) == 0) {
      R_CheckUserInterrupt();
    }
    out[i] = f.query_and_update(static_cast<std::string>(items[i]));
  }
  return out;
}

[[cpp11::register]]
double bf_get_capacity_cpp(cpp11::sexp filter) {
  return static_cast<double>(bf_from_xptr(filter).get_capacity());
}

[[cpp11::register]]
int bf_get_num_hashes_cpp(cpp11::sexp filter) {
  return static_cast<int>(bf_from_xptr(filter).get_num_hashes());
}

[[cpp11::register]]
double bf_get_seed_cpp(cpp11::sexp filter) {
  return static_cast<double>(bf_from_xptr(filter).get_seed());
}

[[cpp11::register]]
double bf_get_bits_used_cpp(cpp11::sexp filter) {
  return static_cast<double>(bf_from_xptr(filter).get_bits_used());
}

[[cpp11::register]]
bool bf_is_empty_cpp(cpp11::sexp filter) {
  return bf_from_xptr(filter).is_empty();
}

[[cpp11::register]]
void bf_reset_cpp(cpp11::sexp filter) {
  bf_from_xptr(filter).reset();
}

[[cpp11::register]]
bool bf_is_compatible_cpp(cpp11::sexp a, cpp11::sexp b) {
  return bf_from_xptr(a).is_compatible(bf_from_xptr(b));
}

// In-place logical OR: `a` becomes the union of `a` and `b`. Both filters
// must be compatible (same seed, num_hashes, and capacity); R validates this
// before calling.
[[cpp11::register]]
void bf_union_cpp(cpp11::sexp a, cpp11::sexp b) {
  bf_from_xptr(a).union_with(bf_from_xptr(b));
}

// In-place logical AND: `a` becomes the intersection of `a` and `b`.
[[cpp11::register]]
void bf_intersect_cpp(cpp11::sexp a, cpp11::sexp b) {
  bf_from_xptr(a).intersect(bf_from_xptr(b));
}

[[cpp11::register]]
void bf_invert_cpp(cpp11::sexp filter) {
  bf_from_xptr(filter).invert();
}

[[cpp11::register]]
std::string bf_to_string_cpp(cpp11::sexp filter, bool print_filter) {
  return bf_from_xptr(filter).to_string(print_filter);
}

[[cpp11::register]]
cpp11::raws bf_serialize_cpp(cpp11::sexp filter) {
  auto bytes = bf_from_xptr(filter).serialize();
  cpp11::writable::raws out(bytes.size());
  std::copy(bytes.begin(), bytes.end(), out.begin());
  return out;
}

[[cpp11::register]]
cpp11::sexp bf_deserialize_cpp(cpp11::raws bytes) {
  std::vector<uint8_t> buffer(bytes.begin(), bytes.end());
  return wrap_bf(datasketches::bloom_filter::deserialize(buffer.data(), buffer.size()));
}

[[cpp11::register]]
double bf_suggest_num_filter_bits_cpp(double max_items, double fpp) {
  const uint64_t max_items_u64 =
    data_sketches_native::checked_uint64_from_double(max_items, "max_items", true);
  return static_cast<double>(
    datasketches::bloom_filter::builder::suggest_num_filter_bits(max_items_u64, fpp)
  );
}

[[cpp11::register]]
int bf_suggest_num_hashes_cpp(double max_items, double num_bits) {
  const uint64_t max_items_u64 =
    data_sketches_native::checked_uint64_from_double(max_items, "max_items", true);
  const uint64_t num_bits_u64 =
    data_sketches_native::checked_uint64_from_double(num_bits, "num_bits", true);
  return static_cast<int>(
    datasketches::bloom_filter::builder::suggest_num_hashes(
      max_items_u64,
      num_bits_u64
    )
  );
}
