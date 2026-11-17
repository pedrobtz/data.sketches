# Interrupt `expr` after `seconds` and report whether it actually fired.
# Used by test-interrupt-safety.R; a helper so that shuffled runs cannot
# call it before it is defined.
interrupt_after <- function(expr, seconds) {
  fired <- TRUE
  tryCatch(
    {
      setTimeLimit(elapsed = seconds, transient = TRUE)
      on.exit(setTimeLimit(), add = TRUE)
      force(expr)
      fired <- FALSE
    },
    error = function(e) NULL
  )
  setTimeLimit()
  fired
}
