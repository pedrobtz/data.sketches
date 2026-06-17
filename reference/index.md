# Package index

## Quantile sketches

KLL, REQ, and t-Digest sketches for approximate quantiles, ranks, CDF,
and PMF. t-Digest concentrates accuracy near the tails of the
distribution.

- [`kll_doubles()`](https://pedrobtz.github.io/data.sketches/reference/kll_doubles.md)
  : KLL sketch for approximate quantiles of a numeric stream
- [`kll_floats()`](https://pedrobtz.github.io/data.sketches/reference/kll_floats.md)
  : KLL sketch for approximate quantiles of a numeric stream stored as
  floats
- [`req()`](https://pedrobtz.github.io/data.sketches/reference/req.md) :
  REQ sketch for relative-error approximate quantiles of a numeric
  stream
- [`tdigest_double()`](https://pedrobtz.github.io/data.sketches/reference/tdigest_double.md)
  : t-Digest sketch for approximate quantiles of a numeric stream

## Cardinality sketches

HLL, CPC, and Theta sketches for approximate distinct counting. Theta
sketches additionally support set operations.

- [`hll()`](https://pedrobtz.github.io/data.sketches/reference/hll.md) :
  HLL sketch for approximate distinct counting
- [`cpc()`](https://pedrobtz.github.io/data.sketches/reference/cpc.md) :
  CPC sketch for approximate distinct counting
- [`theta()`](https://pedrobtz.github.io/data.sketches/reference/theta.md)
  : Theta sketch for approximate distinct counting and set operations
- [`theta_union()`](https://pedrobtz.github.io/data.sketches/reference/theta_set_operations.md)
  [`theta_intersection()`](https://pedrobtz.github.io/data.sketches/reference/theta_set_operations.md)
  [`theta_difference()`](https://pedrobtz.github.io/data.sketches/reference/theta_set_operations.md)
  [`theta_jaccard()`](https://pedrobtz.github.io/data.sketches/reference/theta_set_operations.md)
  : Theta sketch set operations

## Frequency sketches

Frequent Items and Count-Min sketches for approximate frequency
estimation over a numeric or character stream.

- [`frequent_items()`](https://pedrobtz.github.io/data.sketches/reference/frequent_items.md)
  : Frequent Items sketch for approximate frequency estimation
- [`count_min()`](https://pedrobtz.github.io/data.sketches/reference/count_min.md)
  : Count-Min sketch for approximate point-frequency estimation
- [`count_min_suggest_num_buckets()`](https://pedrobtz.github.io/data.sketches/reference/count_min_suggest.md)
  [`count_min_suggest_num_hashes()`](https://pedrobtz.github.io/data.sketches/reference/count_min_suggest.md)
  : Suggest Count-Min sketch parameters

## Tuple sketches

Array of Doubles sketches, a Theta-extension that associates a
fixed-size array of doubles with each retained key, for approximate
distinct counting alongside per-column sums. Supports set operations.

- [`array_of_doubles()`](https://pedrobtz.github.io/data.sketches/reference/array_of_doubles.md)
  : Array of Doubles (Tuple) sketch for estimating sums alongside
  distinct counts
- [`array_of_doubles_union()`](https://pedrobtz.github.io/data.sketches/reference/array_of_doubles_set_operations.md)
  [`array_of_doubles_intersection()`](https://pedrobtz.github.io/data.sketches/reference/array_of_doubles_set_operations.md)
  [`array_of_doubles_difference()`](https://pedrobtz.github.io/data.sketches/reference/array_of_doubles_set_operations.md)
  : Array of Doubles sketch set operations

## Sampling sketches

VarOpt and EBPPS sketches sample weighted items from a stream: VarOpt
for variance-optimal subset-sum estimation, and EBPPS as a modern
alternative to reservoir sampling.

- [`varopt()`](https://pedrobtz.github.io/data.sketches/reference/varopt.md)
  : VarOpt sketch for variance-optimal sampling and subset-sum
  estimation
- [`varopt_union()`](https://pedrobtz.github.io/data.sketches/reference/varopt_union.md)
  : Combine two VarOpt sketches
- [`ebpps()`](https://pedrobtz.github.io/data.sketches/reference/ebpps.md)
  : EBPPS sketch for proportional-to-size sampling

## Filters

Bloom filters for approximate set membership, sized up front by accuracy
or by an explicit number of bits and hash functions.

- [`bloom_filter()`](https://pedrobtz.github.io/data.sketches/reference/bloom_filter.md)
  : Bloom filter for approximate set membership
- [`bloom_filter_suggest_num_filter_bits()`](https://pedrobtz.github.io/data.sketches/reference/bloom_filter_suggest.md)
  [`bloom_filter_suggest_num_hashes()`](https://pedrobtz.github.io/data.sketches/reference/bloom_filter_suggest.md)
  : Suggest Bloom filter sizing parameters
