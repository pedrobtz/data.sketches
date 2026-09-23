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

Other contributors:

- The Apache Software Foundation (Author of bundled Apache DataSketches
  C++ code) \[contributor\]

- Stephan Brumme (Author of bundled xxhash64.h code) \[contributor\]

- Austin Appleby (Author of bundled public-domain MurmurHash3 code)
  \[contributor\]

- Sean Eron Anderson (Author of bundled public-domain bit-hack code used
  in ceiling_power_of_2.hpp) \[contributor\]
