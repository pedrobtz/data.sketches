# data.sketches: Probabilistic Streaming Data Sketches

Provides an 'R' interface to the 'Apache DataSketches'
(<https://datasketches.apache.org/>) library of streaming algorithms for
approximate analytics on data too large to hold or process exactly.
Sketches are compact, mergeable summaries that answer queries such as
approximate distinct counts, quantiles and ranks, frequent items and
point-frequency estimates, weighted sampling, and set membership within
known error bounds. Implements Karnin-Lang-Liberty (KLL), Relative Error
Quantiles (REQ), t-Digest, HyperLogLog (HLL), Compressed Probabilistic
Counting (CPC), Theta, Frequent Items, Count-Min, Array of Doubles,
Variance Optimal (VarOpt), Exact and Bounded Probabilistic
Proportional-to-Size (EBPPS), and Bloom filter sketches, with native
serialization for interoperability with other 'Apache DataSketches'
implementations.

## See also

Useful links:

- <https://github.com/pedrobtz/data.sketches>

- <https://pedrobtz.github.io/data.sketches/>

- Report bugs at <https://github.com/pedrobtz/data.sketches/issues>

## Author

**Maintainer**: Pedro Baltazar <pedrobtz@gmail.com> \[copyright holder\]

Other contributors:

- The Apache Software Foundation (Copyright holder of the bundled Apache
  DataSketches C++ library) \[copyright holder\]
