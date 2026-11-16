# The workload for alloc-failure.yaml, run once per injected allocation
# failure. With one allocation failed, the package must surface it as an R
# error (cpp11 turns the C++ std::bad_alloc into one; R raises its own
# "cannot allocate") and the process must not die. Each section builds,
# updates, queries, merges and round-trips its families, then checks the
# answer, so a failure absorbed into a wrong result is caught here too.
#
# DS_ALLOC_EXERCISE picks the section, one job each, because the sweep is
# capped by allocation count:
#   quantiles    kll_doubles, kll_floats, req, tdigest_double
#   cardinality  hll, cpc, theta and its set operations, array_of_doubles
#   other        frequent_items, count_min, varopt, ebpps, bloom_filter

library(data.sketches)

section <- Sys.getenv("DS_ALLOC_EXERCISE", "quantiles")
x <- as.double(1:2000)
s <- sprintf("k%d", 1:2000)

check <- function(ok, what) {
  if (!isTRUE(ok)) stop("wrong result after an absorbed failure: ", what)
}

# Every family's sketch must survive $serialize() and `bytes =`.
round_trip <- function(ctor, sk, ...) {
  ctor(bytes = sk$serialize(), ...)
}

if (section == "quantiles") {
  for (ctor in list(kll_doubles, kll_floats, req, tdigest_double)) {
    sk <- ctor(x)
    sk$update(x)
    back <- round_trip(ctor, sk)
    check(back$n() == 4000, "quantile sketch n after round trip")
    q <- back$quantile(0.5)
    check(q > 500 && q < 1500, "median")
  }
  a <- kll_doubles(x)
  a$merge(kll_doubles(x))
  check(a$n() == 4000, "kll merge")
} else if (section == "cardinality") {
  h <- hll(s, lg_k = 8)
  check(abs(round_trip(hll, h)$estimate() - 2000) < 400, "hll estimate")
  cp <- cpc(s, lg_k = 8)
  check(abs(round_trip(cpc, cp)$estimate() - 2000) < 400, "cpc estimate")
  t1 <- theta(s, lg_k = 8)
  t2 <- theta(s[1:1000], lg_k = 8)
  check(abs(theta_union(t1, t2)$estimate() - 2000) < 400, "theta union")
  check(abs(theta_intersection(t1, t2)$estimate() - 1000) < 300, "theta intersection")
  check(round_trip(theta, t1)$estimate() > 0, "theta round trip")
  aod <- array_of_doubles(s, values = matrix(1, 2000, 2), num_values = 2, lg_k = 8)
  check(round_trip(array_of_doubles, aod)$estimate() > 0, "aod round trip")
} else if (section == "other") {
  fi <- frequent_items(rep(s[1:20], 50))
  check(nrow(round_trip(frequent_items, fi)$frequent_items()) > 0, "frequent items")
  cm <- count_min(s, num_hashes = 3, num_buckets = 64)
  check(round_trip(count_min, cm)$estimate("k1") >= 1, "count-min estimate")
  vo <- varopt(x, k = 32)
  check(length(round_trip(varopt, vo)$samples()$item) == 32, "varopt sample")
  eb <- ebpps(x, k = 32)
  check(round_trip(ebpps, eb)$n() == 2000, "ebpps n")
  bf <- bloom_filter(s, max_items = 2000, fpp = 0.01)
  check(all(round_trip(bloom_filter, bf)$query(s)), "bloom membership")
}

cat("alloc-exercise", section, "ok\n")
