// Regression test for tools/patches/datasketches/0004-fi-exception-safe-resize.patch
// (issue #35). Fails the k-th allocation made through a Frequent Items
// sketch's allocator, for every k, then queries and destroys the sketch.
// Without the patch, a failure inside reverse_purge_hash_map::resize() left
// the map half-reassigned and the destructor ran ~std::string on garbage:
// ASan SEGV, or "double free or corruption" from R at exit.
//
// Run under ASan from the repository root (vendor.yaml does):
//   c++ -std=c++17 -g -O1 -fsanitize=address \
//     -Isrc/vendor/datasketches/common/include -Isrc/vendor/datasketches/fi/include \
//     tools/vendor/tests/fi-oom.cpp -o fi-oom && ./fi-oom
#include <cstdio>
#include <cstring>
#include <new>
#include <string>
#include "frequent_items_sketch.hpp"
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
using str = std::basic_string<char, std::char_traits<char>, failing_alloc<char>>;
using fi = datasketches::frequent_items_sketch<str, uint64_t, std::hash<str>, std::equal_to<str>, failing_alloc<str>>;
int main() {
  int thrown = 0;
  for (long k = 0; k < 400; k++) {
    fi sk(8, 3, std::equal_to<str>(), failing_alloc<str>());
    countdown = k;
    try {
      for (int i = 0; i < 300; i++) sk.update(str(("a-long-item-name-that-defeats-sso-" + std::to_string(i)).c_str()));
    } catch (const std::bad_alloc&) { thrown++; }
    countdown = -1;
    // The sketch must still be usable: query and serialize it.
    volatile auto n = sk.get_num_active_items(); (void)n;
    for (const auto& r : sk.get_frequent_items(datasketches::NO_FALSE_NEGATIVES, 0)) (void)r.get_item().size();
  }  // ~fi runs here, after the failure
  std::printf("survived; %d injected failures\n", thrown);
}
