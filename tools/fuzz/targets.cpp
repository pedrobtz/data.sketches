// Fuzz targets for every `bytes =` path in the package: the same upstream
// deserialize() call, with the same template arguments and the same seed, that
// src/<family>.cpp makes when an R user passes a payload in.
//
// The first input byte picks the family; the rest is exactly the `bytes`
// vector R would hand over (for VarOpt and EBPPS that includes the package's
// own one-byte item-type tag).
//
// Oracle: a payload the library accepts must round-trip. Deserialize it,
// serialize the result as the package does, deserialize that, serialize again:
// the second deserialize must succeed and the two serializations must be
// byte-identical. A rejected payload (any std::exception from the first
// deserialize) is the expected outcome for most inputs and is not a finding;
// a crash, a sanitizer report or a broken round trip is.
//
// Compiled without R, so it reaches only the vendored headers and the
// package's framing, which is what parses untrusted bytes.

#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <exception>
#include <string>
#include <tuple>
#include <vector>

#include "array_of_doubles_sketch.hpp"
#include "bloom_filter.hpp"
#include "common_defs.hpp"
#include "count_min.hpp"
#include "cpc_sketch.hpp"
#include "ebpps_sketch.hpp"
#include "frequent_items_sketch.hpp"
#include "hll.hpp"
#include "kll_sketch.hpp"
#include "req_sketch.hpp"
#include "tdigest.hpp"
#include "theta_sketch.hpp"
#include "var_opt_sketch.hpp"

namespace {

using bytes_t = std::vector<uint8_t>;
const uint64_t seed = datasketches::DEFAULT_SEED;

[[noreturn]] void fail(const char* family, const char* what) {
  std::fprintf(stderr, "ORACLE FAILURE [%s]: %s\n", family, what);
  std::abort();
}

// Deserialize, then require the round trip. `De` maps (ptr, size) to a
// sketch; `Se` maps a sketch to the bytes the package's serialize binding
// returns; `Key` maps a sketch to what must survive the trip. For most
// families the key is the serialization itself. Frequent Items is the
// exception: its reverse-purge hash map is rebuilt in a new insertion order
// on every deserialize, so its bytes permute the items while the content is
// unchanged, and its key is the content (see fi_key).
template <class De, class Se, class Key>
void round_trip(const char* family, const uint8_t* data, size_t size, De de, Se se, Key key) {
  // Every binding copies the R raw vector into a fresh std::vector before
  // deserializing, so the library always sees a heap-aligned buffer. Do the
  // same: the upstream parsers load multi-byte fields through casts, and an
  // offset pointer would report misalignment R users can never hit.
  const bytes_t input(data, data + size);
  bytes_t bytes;
  decltype(key(de(input.data(), 0))) first, second;
  try {
    auto sk = de(input.data(), input.size());
    bytes = se(sk);
    first = key(sk);
  } catch (const std::exception&) {
    return;  // rejected payload: R would raise datasketches_invalid_bytes
  }
  try {
    auto again = de(bytes.data(), bytes.size());
    second = key(again);
  } catch (const std::exception& e) {
    std::fprintf(stderr, "re-deserialize threw: %s\n", e.what());
    fail(family, "the library rejected its own serialization");
  }
  if (first != second) fail(family, "the round trip changed the sketch");
}

template <class De, class Se>
void round_trip(const char* family, const uint8_t* data, size_t size, De de, Se se) {
  round_trip(family, data, size, de, se, se);
}

// The serialize binding every untagged family uses.
template <class Sk>
bytes_t plain(const Sk& s) {
  auto v = s.serialize();
  return bytes_t(v.begin(), v.end());
}

// The VarOpt and EBPPS bindings prefix the native payload with an item-type
// tag (0 = double, 1 = character); the round trip is of the payload after it.
template <class D, class S>
void tagged(const char* family, const uint8_t* data, size_t size) {
  if (size < 1) return;  // R raises before reaching the library
  const uint8_t tag = data[0];
  if (tag == 0) {
    round_trip(family, data + 1, size - 1,
               [](const uint8_t* p, size_t n) { return D::deserialize(p, n); }, plain<D>);
  } else if (tag == 1) {
    round_trip(family, data + 1, size - 1,
               [](const uint8_t* p, size_t n) { return S::deserialize(p, n); }, plain<S>);
  }
  // Any other tag: R raises "Unrecognized item-type tag" before the library.
}

// Everything `$get_frequent_items()`, `$get_estimate()` and friends can
// observe: the total weight, the error offset and every tracked item with its
// estimate and bounds, sorted by item so hash-map order does not matter.
using fi_t = datasketches::frequent_items_sketch<std::string>;
struct fi_key_t {
  double total_weight = 0, max_error = 0;
  std::vector<std::tuple<std::string, double, double, double>> items;
  bool operator!=(const fi_key_t& o) const {
    return total_weight != o.total_weight || max_error != o.max_error || items != o.items;
  }
};
fi_key_t fi_key(const fi_t& s) {
  fi_key_t k;
  k.total_weight = static_cast<double>(s.get_total_weight());
  k.max_error = static_cast<double>(s.get_maximum_error());
  for (const auto& row : s.get_frequent_items(datasketches::NO_FALSE_NEGATIVES, 0)) {
    k.items.emplace_back(row.get_item(), static_cast<double>(row.get_estimate()),
                         static_cast<double>(row.get_lower_bound()),
                         static_cast<double>(row.get_upper_bound()));
  }
  std::sort(k.items.begin(), k.items.end());
  return k;
}

// HLL's key is its compact serialization, with the coupons of a list or set
// sorted: those are written in hash-table order, which depends on insertion
// history, so the same coupons can come out in a different order. The mode
// is the low two bits of byte 7 (LIST 0, SET 1, HLL 2); coupons start after
// the 8- or 12-byte preamble. HLL arrays are compared byte for byte.
bytes_t hll_key(const datasketches::hll_sketch& s) {
  auto v = s.serialize_compact();
  bytes_t b(v.begin(), v.end());
  if (b.size() < 8) return b;
  const uint8_t mode = b[7] & 0x03;
  if (mode > 1) return b;
  const size_t start = (mode == 0) ? 8 : 12;
  std::vector<uint32_t> coupons;
  for (size_t i = start; i + 4 <= b.size(); i += 4) {
    uint32_t c;
    std::memcpy(&c, b.data() + i, sizeof(c));
    coupons.push_back(c);
  }
  std::sort(coupons.begin(), coupons.end());
  for (size_t i = 0; i < coupons.size(); ++i) std::memcpy(b.data() + start + 4 * i, &coupons[i], sizeof(uint32_t));
  return b;
}

// t-Digest's key is its serialization with one bit masked: an empty sketch's
// reverse_merge flag (bit 2 of the flags byte, offset 5). It only says which
// way the next internal merge runs, so it means nothing for an empty sketch,
// and upstream's empty-image path drops it on reading
// (`if (is_empty) return tdigest(k, allocator)`). A payload flagged non-empty
// but holding nothing keeps it for one round trip and loses it on the next;
// nothing observable changes. Everything else must still match exactly.
bytes_t tdigest_key(const datasketches::tdigest_double& s) {
  auto v = s.serialize();
  bytes_t b(v.begin(), v.end());
  if (b.size() > 5 && (b[5] & 0x01)) b[5] &= static_cast<uint8_t>(~0x04);
  return b;
}

}  // namespace

extern "C" int ds_fuzz_one(const uint8_t* data, size_t size) {
  if (size < 1) return 0;
  const uint8_t family = data[0];
  data += 1;
  size -= 1;

  using namespace datasketches;
  switch (family % 13) {
    case 0:
      round_trip("kll_doubles", data, size,
                 [](const uint8_t* p, size_t n) { return kll_sketch<double>::deserialize(p, n); },
                 plain<kll_sketch<double>>);
      break;
    case 1:
      round_trip("kll_floats", data, size,
                 [](const uint8_t* p, size_t n) { return kll_sketch<float>::deserialize(p, n); },
                 plain<kll_sketch<float>>);
      break;
    case 2:
      round_trip("req", data, size,
                 [](const uint8_t* p, size_t n) { return req_sketch<double>::deserialize(p, n); },
                 plain<req_sketch<double>>);
      break;
    case 3:
      round_trip("tdigest_double", data, size,
                 [](const uint8_t* p, size_t n) { return tdigest_double::deserialize(p, n); },
                 plain<tdigest_double>, tdigest_key);
      break;
    case 4:
      if (size < 8) break;  // hll() rejects a shorter payload in R
      round_trip("hll", data, size,
                 [](const uint8_t* p, size_t n) { return hll_sketch::deserialize(p, n); },
                 [](const hll_sketch& s) {
                   auto v = s.serialize_compact();
                   return bytes_t(v.begin(), v.end());
                 },
                 hll_key);
      break;
    case 5:
      round_trip("cpc", data, size,
                 [](const uint8_t* p, size_t n) { return cpc_sketch::deserialize(p, n, seed); },
                 plain<cpc_sketch>);
      break;
    case 6:
      round_trip("theta", data, size,
                 [](const uint8_t* p, size_t n) { return compact_theta_sketch::deserialize(p, n, seed); },
                 [](const compact_theta_sketch& s) {
                   auto v = s.serialize_compressed();
                   return bytes_t(v.begin(), v.end());
                 });
      break;
    case 7:
      round_trip("array_of_doubles", data, size,
                 [](const uint8_t* p, size_t n) {
                   return compact_array_of_doubles_sketch::deserialize(p, n, seed);
                 },
                 plain<compact_array_of_doubles_sketch>);
      break;
    case 8:
      round_trip("frequent_items", data, size,
                 [](const uint8_t* p, size_t n) {
                   return frequent_items_sketch<std::string>::deserialize(p, n);
                 },
                 plain<fi_t>, fi_key);
      break;
    case 9: {
      // An empty Count-Min image still declares its table, and any reader
      // allocates num_hashes * num_buckets counters for it: a legitimate empty
      // sketch can be large, so this is the format, not a bug. Skip the ones
      // past 64 MiB, which would only measure the fuzzer's memory limit.
      if (size >= 16 && (data[3] & 0x01)) {
        uint32_t nbuckets;
        std::memcpy(&nbuckets, data + 8, sizeof(nbuckets));
        const uint64_t cells = static_cast<uint64_t>(nbuckets) * data[12];
        if (cells * sizeof(double) > (64ULL << 20)) break;
      }
      round_trip("count_min", data, size,
                 [](const uint8_t* p, size_t n) { return count_min_sketch<double>::deserialize(p, n, seed); },
                 plain<count_min_sketch<double>>);
      break;
    }
    case 10: {
      // An empty or warmup-mode VarOpt image declares its capacity through k
      // and the resize factor (X1 preallocates all of k), and any reader
      // allocates it: like an empty Count-Min table, that is the format, not
      // a bug. Skip k past 2^20 there, which would only measure the fuzzer's
      // memory limit. Full mode is bounded by its items, checked by 0015.
      if (size >= 9) {
        const uint8_t prelongs = data[1] & 0x3f;
        uint32_t k;
        std::memcpy(&k, data + 5, sizeof(k));
        if (prelongs != 4 && k > (1u << 20)) break;
      }
      tagged<var_opt_sketch<double>, var_opt_sketch<std::string>>("varopt", data, size);
      break;
    }
    case 11:
      tagged<ebpps_sketch<double>, ebpps_sketch<std::string>>("ebpps", data, size);
      break;
    case 12: {
      // An empty Bloom image declares its capacity (num_longs), and any reader
      // allocates and zeroes that many bits: a legitimate empty filter can be
      // gigabytes (the library allows about 2^34 bits), so this is the format,
      // not a bug. Skip past 64 MiB, which only measures the fuzzer's time.
      if (size >= 20 && (data[3] & 0x04)) {
        uint32_t num_longs;
        std::memcpy(&num_longs, data + 16, sizeof(num_longs));
        if (static_cast<uint64_t>(num_longs) * 8 > (64ULL << 20)) break;
      }
      round_trip("bloom_filter", data, size,
                 [](const uint8_t* p, size_t n) { return bloom_filter::deserialize(p, n); },
                 plain<bloom_filter>);
      break;
    }
  }
  return 0;
}
