# Every exported constructor, paired with a builder for a populated instance.
# A helper, not file scope in test-conditions.R, so that
# devtools::test(shuffle = TRUE) cannot run a test before the list exists.
sketch_builders <- list(
  kll_doubles = function() kll_doubles(as.double(1:100)),
  kll_floats = function() kll_floats(as.double(1:100)),
  req = function() req(as.double(1:100)),
  tdigest_double = function() tdigest_double(as.double(1:100)),
  hll = function() hll(as.character(1:100)),
  cpc = function() cpc(as.character(1:100)),
  theta = function() theta(as.character(1:100)),
  frequent_items = function() frequent_items(),
  count_min = function() count_min(),
  array_of_doubles = function() array_of_doubles(as.character(1:100)),
  varopt = function() varopt(as.double(1:100)),
  ebpps = function() ebpps(as.double(1:100)),
  bloom_filter = function() bloom_filter(max_items = 100, fpp = 0.01)
)
