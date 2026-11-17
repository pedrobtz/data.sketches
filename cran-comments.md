## R CMD check results

0 errors | 0 warnings | 0 notes

## Submission summary

This is an update. It upgrades the bundled Apache DataSketches C++ library
from 5.2.0 to 5.3.1, which fixes out-of-bounds reads and writes when
deserializing corrupt sketches, and adds local patches for further
deserialization and allocation-failure bugs found by fuzzing (reported to
the upstream project). Corrupt input now raises a classed R error instead of
crashing. See NEWS.md for the behaviour changes (REQ k >= 256, VarOpt zero
weights, Bloom filter size limits).

## Test environments

GitHub Actions (pedrobtz/r-actions): macOS, Windows and Ubuntu R-release;
Ubuntu R-oldrel-1 and R-devel; Windows R-devel; the clang23, ubuntu-clang and
ubuntu-gcc16 r-devel containers; nosuggests; nold. Also ASan/UBSan (gcc and
clang), valgrind, rchk, LTO, gctorture and the compiler static analyzers.

## Reverse dependencies

There are currently no reverse dependencies on CRAN.
