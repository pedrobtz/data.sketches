# S3 method delegators for sketch classes. Each is a one-line wrapper over the
# R6 method so that `format(sketch)` and `sketch$format()` behave identically and
# there is a single source of truth (the R6 method).

#' @export
format.kll_doubles_sketch <- function(x, ...) {
  x$format(...)
}

#' @export
print.kll_doubles_sketch <- function(x, ...) {
  x$print(...)
}

#' @export
as.character.kll_doubles_sketch <- function(x, ...) {
  x$format(...)
}

#' @export
summary.kll_doubles_sketch <- function(object, ...) {
  object$summary(...)
}

#' @export
format.kll_floats_sketch <- function(x, ...) {
  x$format(...)
}

#' @export
print.kll_floats_sketch <- function(x, ...) {
  x$print(...)
}

#' @export
as.character.kll_floats_sketch <- function(x, ...) {
  x$format(...)
}

#' @export
summary.kll_floats_sketch <- function(object, ...) {
  object$summary(...)
}

#' @export
format.req_sketch <- function(x, ...) {
  x$format(...)
}

#' @export
print.req_sketch <- function(x, ...) {
  x$print(...)
}

#' @export
as.character.req_sketch <- function(x, ...) {
  x$format(...)
}

#' @export
summary.req_sketch <- function(object, ...) {
  object$summary(...)
}

#' @export
format.hll_sketch <- function(x, ...) {
  x$format(...)
}

#' @export
print.hll_sketch <- function(x, ...) {
  x$print(...)
}

#' @export
as.character.hll_sketch <- function(x, ...) {
  x$format(...)
}

#' @export
summary.hll_sketch <- function(object, ...) {
  object$summary(...)
}

#' @export
format.cpc_sketch <- function(x, ...) {
  x$format(...)
}

#' @export
print.cpc_sketch <- function(x, ...) {
  x$print(...)
}

#' @export
as.character.cpc_sketch <- function(x, ...) {
  x$format(...)
}

#' @export
summary.cpc_sketch <- function(object, ...) {
  object$summary(...)
}

#' @export
format.theta_sketch <- function(x, ...) {
  x$format(...)
}

#' @export
print.theta_sketch <- function(x, ...) {
  x$print(...)
}

#' @export
as.character.theta_sketch <- function(x, ...) {
  x$format(...)
}

#' @export
summary.theta_sketch <- function(object, ...) {
  object$summary(...)
}

#' @export
format.frequent_items_sketch <- function(x, ...) {
  x$format(...)
}

#' @export
print.frequent_items_sketch <- function(x, ...) {
  x$print(...)
}

#' @export
as.character.frequent_items_sketch <- function(x, ...) {
  x$format(...)
}

#' @export
summary.frequent_items_sketch <- function(object, ...) {
  object$summary(...)
}

#' @export
format.count_min_sketch <- function(x, ...) {
  x$format(...)
}

#' @export
print.count_min_sketch <- function(x, ...) {
  x$print(...)
}

#' @export
as.character.count_min_sketch <- function(x, ...) {
  x$format(...)
}

#' @export
summary.count_min_sketch <- function(object, ...) {
  object$summary(...)
}

#' @export
format.array_of_doubles_sketch <- function(x, ...) {
  x$format(...)
}

#' @export
print.array_of_doubles_sketch <- function(x, ...) {
  x$print(...)
}

#' @export
as.character.array_of_doubles_sketch <- function(x, ...) {
  x$format(...)
}

#' @export
summary.array_of_doubles_sketch <- function(object, ...) {
  object$summary(...)
}

#' @export
format.varopt_sketch <- function(x, ...) {
  x$format(...)
}

#' @export
print.varopt_sketch <- function(x, ...) {
  x$print(...)
}

#' @export
as.character.varopt_sketch <- function(x, ...) {
  x$format(...)
}

#' @export
summary.varopt_sketch <- function(object, ...) {
  object$summary(...)
}

#' @export
format.ebpps_sketch <- function(x, ...) {
  x$format(...)
}

#' @export
print.ebpps_sketch <- function(x, ...) {
  x$print(...)
}

#' @export
as.character.ebpps_sketch <- function(x, ...) {
  x$format(...)
}

#' @export
summary.ebpps_sketch <- function(object, ...) {
  object$summary(...)
}

#' @export
format.bloom_filter <- function(x, ...) {
  x$format(...)
}

#' @export
print.bloom_filter <- function(x, ...) {
  x$print(...)
}

#' @export
as.character.bloom_filter <- function(x, ...) {
  x$format(...)
}

#' @export
summary.bloom_filter <- function(object, ...) {
  object$summary(...)
}

#' @export
format.tdigest_double_sketch <- function(x, ...) {
  x$format(...)
}

#' @export
print.tdigest_double_sketch <- function(x, ...) {
  x$print(...)
}

#' @export
as.character.tdigest_double_sketch <- function(x, ...) {
  x$format(...)
}

#' @export
summary.tdigest_double_sketch <- function(object, ...) {
  object$summary(...)
}
