## R CMD check results

0 errors | 0 warnings | 0 notes

## Submission summary

This is a patch release. It fixes a memory leak when a long-running
computation is interrupted, preserves the accuracy of Theta and Array of
Doubles sketches across serialization round-trips, and gives errors raised
from compiled code the package's documented condition classes. See NEWS.md
for details.

## Reverse dependencies

There are currently no reverse dependencies on CRAN.
