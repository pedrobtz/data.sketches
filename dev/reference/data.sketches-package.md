# data.sketches: Probabilistic Streaming Data Sketches

Provides an interface to the 'Apache DataSketches'
(<https://datasketches.apache.org/>) library of streaming algorithms for
approximate analytics on data too large to hold or process exactly.
Sketches are compact, mergeable summaries built in a single pass over a
stream that answer queries such as approximate distinct counts,
quantiles and ranks, frequent items and point-frequency estimates,
weighted sampling, and set membership with mathematically proven error
bounds. Implements Karnin-Lang-Liberty (KLL), Relative Error Quantiles
(REQ), t-Digest, HyperLogLog (HLL), Compressed Probabilistic Counting
(CPC), Theta, Frequent Items, Count-Min, Array of Doubles, Variance
Optimal (VarOpt), Exact and Bounded Probabilistic Proportional-to-Size
(EBPPS), and Bloom filter sketches, with native serialization for
interoperability with other 'Apache DataSketches' implementations.

## See also

Useful links:

- <https://github.com/pedrobtz/data.sketches>

- <https://pedrobtz.github.io/data.sketches/>

- Report bugs at <https://github.com/pedrobtz/data.sketches/issues>

## Author

**Maintainer**: Pedro Baltazar <pedrobtz@gmail.com> \[copyright holder\]

Authors:

- Pedro Baltazar <pedrobtz@gmail.com> \[copyright holder\]

Other contributors:

- The Apache Software Foundation (Bundled Apache DataSketches C++
  library, src/vendor/datasketches/) \[contributor, copyright holder\]

- Yahoo Inc. (Apache DataSketches C++, 2015-2018 and 2021-2025)
  \[copyright holder\]

- Verizon Media (Apache DataSketches C++, 2019-2020) \[copyright
  holder\]

- Stephan Brumme (Bundled xxhash64.h (MIT)) \[contributor, copyright
  holder\]

- Sun Microsystems, Inc. (FDLIBM log code adapted in bundled
  fdlibm_log.hpp) \[copyright holder\]

- Austin Appleby (Bundled public-domain MurmurHash3 code)
  \[contributor\]

- Sean Eron Anderson (Bundled public-domain bit-hack code in
  ceiling_power_of_2.hpp) \[contributor\]
