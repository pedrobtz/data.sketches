// Regression test for tools/patches/datasketches/0007-kll-merge-allocate-first.patch.
// Fails the k-th allocation made through a KLL sketch's allocator while it
// merges another, for every k, then queries and destroys both sketches. The
// shape is the R call that found it, kll_doubles(x)$merge(kll_doubles(x))
// with x = 1:2000, under alloc-failure.yaml.
// Without the patch, merge_higher_levels() freed items_ and then allocated
// its replacement, so a std::bad_alloc left items_ dangling and the destructor
// freed it a second time: ASan double-free, or "double free or corruption"
// from R at exit.
//
// Run under ASan from the repository root (vendor.yaml does):
//   c++ -std=c++17 -g -O1 -fsanitize=address \
//     -Isrc/vendor/datasketches/common/include -Isrc/vendor/datasketches/kll/include \
//     -Isrc/vendor/datasketches/quantiles/include \
//     tools/vendor/tests/kll-merge-oom.cpp -o kll-merge-oom && ./kll-merge-oom
#include <cstdio>
#include <cstring>
#include <new>
#include "kll_sketch.hpp"

static long countdown = -1;
template <class T> struct failing_alloc {
  using value_type = T;
  failing_alloc() = default;
  template <class U> failing_alloc(const failing_alloc<U>&) {}
  T* allocate(size_t n) {
    if (countdown >= 0 && countdown-- == 0) throw std::bad_alloc();
    void* p = ::operator new(n * sizeof(T));
    std::memset(p, 0xAB, n * sizeof(T));  // reused heap is not zero
    return static_cast<T*>(p);
  }
  void deallocate(T* p, size_t) { ::operator delete(p); }
  template <class U> bool operator==(const failing_alloc<U>&) const { return true; }
  template <class U> bool operator!=(const failing_alloc<U>&) const { return false; }
};
using kll = datasketches::kll_sketch<double, std::less<double>, failing_alloc<double>>;

static kll build() {
  kll s(200, std::less<double>(), failing_alloc<double>());
  for (int i = 1; i <= 2000; i++) s.update(i);
  return s;
}

int main() {
  int thrown = 0;
  for (long k = 0; k < 200; k++) {
    kll a = build();
    kll b = build();
    countdown = k;
    try {
      a.merge(b);
    } catch (const std::bad_alloc&) {
      thrown++;
    }
    countdown = -1;
    (void)b.get_quantile(0.5);
  }  // ~kll runs here, after the failure
  std::printf("survived; %d injected failures\n", thrown);
  return thrown > 0 ? 0 : 1;  // a sweep that never failed proves nothing
}
