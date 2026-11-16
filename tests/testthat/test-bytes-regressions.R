# Payloads that crashed or misbehaved in the vendored deserializers, found by
# tools/fuzz (issues #33 and #35). Each file is the fuzz input as hex (`xxd -p`;
# R CMD check reports some raw payloads as executables): one family-selector
# byte (the `case` in tools/fuzz/targets.cpp), then the `bytes` R hands over.
# Every one must be rejected as a classed condition, never accepted.
#
# Without sanitizers an out-of-bounds read can still end in an exception, so
# this test alone does not prove the fix; under ASan/UBSan (native-checks.yaml)
# it does, because the 5.2.0 and unpatched behaviour is a sanitizer report.
#
#   01 kll_floats  heap over-read                     fixed in 5.3.1
#   02 req         heap over-read; 8 GiB allocation   fixed in 5.3.1
#   04 hll         lg_k used unchecked as a shift     tools/patches 0001
#   05 cpc         heap over-read                     fixed in 5.3.0
#   09 count_min   heap over-read                     fixed in 5.3.0
#   11 ebpps       NaN/huge item count cast (UB)      tools/patches 0003
#   12 bloom       over-read past the empty preamble  tools/patches 0002

test_that("payloads that crashed the deserializers raise datasketches_invalid_bytes", {
  constructors <- list(
    "01" = kll_floats,
    "02" = req,
    "04" = hll,
    "05" = cpc,
    "09" = count_min,
    "11" = ebpps,
    "12" = bloom_filter
  )
  read_hex <- function(path) {
    hex <- paste(readLines(path), collapse = "")
    as.raw(strtoi(substring(hex, seq(1, nchar(hex), 2), seq(2, nchar(hex), 2)), 16L))
  }
  files <- list.files(test_path("fixtures", "bytes"), "[.]hex$", full.names = TRUE)
  expect_gte(length(files), 10L)

  for (f in files) {
    raw <- read_hex(f)
    family <- sprintf("%02d", as.integer(raw[[1L]]))
    ctor <- constructors[[family]]
    expect_false(is.null(ctor), info = basename(f))
    expect_error(
      ctor(bytes = raw[-1L]),
      class = "datasketches_invalid_bytes",
      info = basename(f)
    )
  }
})
