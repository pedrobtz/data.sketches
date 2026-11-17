// libFuzzer entry point. The targets and their oracle are in targets.cpp,
// which fuzz.yaml passes as `sources`, so the reach report covers them.
//
// Local replay without libFuzzer (Apple clang has none), from the repo root:
//   clang++ -std=c++17 -g -O1 -fsanitize=address,undefined -DDS_FUZZ_MAIN \
//     $(sed -n 's/^\t*-I\(vendor\/datasketches\/[a-z]*\/include\).*/-Isrc\/\1/p' src/Makevars) \
//     tools/fuzz/harness.cpp tools/fuzz/targets.cpp -o fuzz-replay
//   ./fuzz-replay tools/fuzz/corpus/*

#include <cstddef>
#include <cstdint>

extern "C" int ds_fuzz_one(const uint8_t* data, size_t size);

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
  return ds_fuzz_one(data, size);
}

#ifdef DS_FUZZ_MAIN
#include <cstdio>
#include <fstream>
#include <iterator>
#include <vector>

int main(int argc, char** argv) {
  for (int i = 1; i < argc; i++) {
    std::ifstream in(argv[i], std::ios::binary);
    std::vector<uint8_t> buf((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());
    ds_fuzz_one(buf.data(), buf.size());
  }
  std::printf("replayed %d inputs\n", argc - 1);
  return 0;
}
#endif
