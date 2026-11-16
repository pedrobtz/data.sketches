# Payloads that crashed or misbehaved in the vendored deserializers, found by
# tools/fuzz (issues #33 and #35). Each file is the fuzz input as hex (`xxd -p`;
# R CMD check reports some raw payloads as executables): one family-selector
# byte (the `case` in tools/fuzz/targets.cpp), then the `bytes` R hands over.
# Every one must be rejected as a classed condition, never accepted. The
# `-fuzz-` files are one representative per distinct failure site from a
# 15-minute libFuzzer campaign; tools/patches/datasketches/ has the fixes,
# and src/vendor/PROVENANCE maps them to the families.
#
# Without sanitizers an out-of-bounds read can still end in an exception, so
# this test alone does not prove the fix; under ASan/UBSan (native-checks.yaml)
# it does, because the unpatched behaviour is a sanitizer report.

test_that("payloads that crashed the deserializers raise datasketches_invalid_bytes", {
  constructors <- list(
    "00" = kll_doubles,
    "01" = kll_floats,
    "02" = req,
    "03" = tdigest_double,
    "04" = hll,
    "05" = cpc,
    "06" = theta,
    "07" = array_of_doubles,
    "08" = frequent_items,
    "09" = count_min,
    "10" = varopt,
    "11" = ebpps,
    "12" = bloom_filter
  )
  read_hex <- function(path) {
    hex <- paste(readLines(path), collapse = "")
    as.raw(strtoi(substring(hex, seq(1, nchar(hex), 2), seq(2, nchar(hex), 2)), 16L))
  }
  files <- list.files(test_path("fixtures", "bytes"), "[.]hex$", full.names = TRUE)
  expect_gte(length(files), 30L)

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
