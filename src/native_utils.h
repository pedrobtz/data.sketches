#ifndef DATA_SKETCHES_NATIVE_UTILS_H_
#define DATA_SKETCHES_NATIVE_UTILS_H_

#include <cmath>
#include <cstdint>
#include <string>

#include <cpp11.hpp>

namespace data_sketches_native {

constexpr double MAX_SAFE_UINT64_FROM_R = 9007199254740992.0; // 2^53

inline uint64_t checked_uint64_from_double(
  double value,
  const char* arg,
  bool strictly_positive = false
) {
  if (
    !std::isfinite(value) ||
      std::trunc(value) != value ||
      value > MAX_SAFE_UINT64_FROM_R ||
      value < (strictly_positive ? 1.0 : 0.0)
  ) {
    const std::string qualifier = strictly_positive ? "positive" : "non-negative";
    const std::string message =
      std::string("`") + arg + "` must be a finite " + qualifier +
      " whole number up to 2^53.";
    cpp11::stop(message.c_str());
    return 0;
  }

  return static_cast<uint64_t>(value);
}

} // namespace data_sketches_native

#endif // DATA_SKETCHES_NATIVE_UTILS_H_
