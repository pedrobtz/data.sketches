# Sourced by both alloc-failure.yaml's baseline run and tools/alloc-exercise.R,
# so the sweep's startup floor lies past everything here. The package calls
# rlang:: without importing it, so rlang's namespace, its DLL and the abort()
# machinery load lazily on the first classed error. Failing one of those
# allocations is R failing to load a package, not this package failing, and
# without the warm-up it buries the sweep in "there is no package called
# 'rlang'". One classed error from R and one from the C++ bridge loads them.
library(data.sketches)
invisible(loadNamespace("rlang"))
invisible(loadNamespace("R6"))
invisible(tryCatch(kll_doubles(k = 2), error = conditionMessage))
invisible(tryCatch(kll_doubles(bytes = as.raw(rep(255L, 64L))), error = conditionMessage))
