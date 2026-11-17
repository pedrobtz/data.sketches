# Regenerates tools/fuzz/corpus/: one seed per family and state, each the
# family selector byte (the `case` in targets.cpp) followed by the bytes
# `$serialize()` returns. Run from the repository root with the package
# installed or loaded. Seeds ending in -v520 were written by DataSketches
# 5.2.0 (data.sketches 0.1.1); they are kept, as old payloads users still
# hold, and are not regenerated:
#   Rscript tools/fuzz/make-corpus.R

library(data.sketches)

out <- "tools/fuzz/corpus"
dir.create(out, showWarnings = FALSE, recursive = TRUE)
unlink(setdiff(list.files(out, full.names = TRUE), list.files(out, "-v520$", full.names = TRUE)))

set.seed(20261116)
nums <- c(rnorm(5000), runif(2000, -1e6, 1e6))
strs <- sprintf("item-%d", sample.int(400, 5000, replace = TRUE))

seed <- function(family, name, sketch) {
  bytes <- c(as.raw(family), sketch$serialize())
  writeBin(bytes, file.path(out, sprintf("%02d-%s", family, name)))
}

# Each family: empty, a few items (exact mode), many items (estimation mode).
seed(0, "kll-doubles-empty", kll_doubles())
seed(0, "kll-doubles-few", kll_doubles(c(1, 2, 3)))
seed(0, "kll-doubles-many", kll_doubles(nums, k = 50))
seed(1, "kll-floats-empty", kll_floats())
seed(1, "kll-floats-few", kll_floats(c(1, 2, 3)))
seed(1, "kll-floats-many", kll_floats(nums, k = 50))
seed(2, "req-empty", req())
seed(2, "req-few", req(c(1, 2, 3)))
seed(2, "req-many", req(nums, k = 12))
seed(2, "req-lra", req(nums, k = 12, hra = FALSE))
seed(3, "tdigest-empty", tdigest_double())
seed(3, "tdigest-few", tdigest_double(c(1, 2, 3)))
seed(3, "tdigest-many", tdigest_double(nums))
seed(4, "hll-empty", hll())
seed(4, "hll-few", hll(strs[1:5], lg_k = 8))
for (type in c("HLL_4", "HLL_6", "HLL_8")) {
  seed(4, paste0("hll-many-", type), hll(strs, lg_k = 8, type = type))
}
seed(5, "cpc-empty", cpc())
seed(5, "cpc-few", cpc(strs[1:5], lg_k = 8))
seed(5, "cpc-many", cpc(c(strs, as.character(nums)), lg_k = 8))
seed(6, "theta-empty", theta())
seed(6, "theta-few", theta(strs[1:5], lg_k = 8))
seed(6, "theta-many", theta(as.character(nums), lg_k = 8))
seed(7, "aod-empty", array_of_doubles(num_values = 2))
seed(7, "aod-few", array_of_doubles(strs[1:5], values = matrix(1, 5, 2), num_values = 2, lg_k = 8))
seed(7, "aod-many", array_of_doubles(
  as.character(nums), values = matrix(nums, length(nums), 2), num_values = 2, lg_k = 8
))
seed(8, "fi-empty", frequent_items())
seed(8, "fi-few", frequent_items(strs[1:5]))
seed(8, "fi-many", frequent_items(strs, lg_max_map_size = 4))
seed(9, "cm-empty", count_min(num_hashes = 3, num_buckets = 16))
seed(9, "cm-many", count_min(strs, num_hashes = 3, num_buckets = 16))
seed(10, "varopt-double-few", varopt(nums[1:5], k = 16))
seed(10, "varopt-double-many", varopt(nums, k = 16))
seed(10, "varopt-string-many", varopt(strs, k = 16))
seed(11, "ebpps-double-few", ebpps(nums[1:5], k = 16))
seed(11, "ebpps-double-many", ebpps(nums, k = 16))
seed(11, "ebpps-string-many", ebpps(strs, k = 16))
seed(12, "bloom-empty", bloom_filter(max_items = 100, fpp = 0.05))
seed(12, "bloom-many", bloom_filter(strs, max_items = 100, fpp = 0.05))

cat(length(list.files(out)), "seeds written to", out, "\n")
