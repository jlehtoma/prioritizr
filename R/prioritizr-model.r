#' Prepare systematic conservation prioritization problem
#'
#' Specify a systematic conservation prioritization problem from input data in a
#' variety of formats. The are constructor functions for \code{prioritizr_model}
#' objects which encapsulate prioritization problems in a standardized format.
#'
#' @param pu RasterLayer or SpatialPolygonsDataFrame object; the planning
#'   units to use in the reserve design exercise and their corresponding cost.
#'   If a RasterLayer object is provided the cost should be stored in the cell
#'   values and if a SpatialPolygonsDataFrame object is provided it should have
#'   an attribute field named \code{pu}.
#' @param features RasterStack object; the distribution of conservation
#'   features. If \code{pu} is a Raster object then \code{features} should be
#'   defined on the same raster template. If \code{pu} is a
#'   SpatialPolygonsDataFrame \code{features} will be summarize over the
#'   polygons using \code{\link{summarize_features}}.
#' @param targets numeric; representation targets either as proportion (between
#'   0 and 1) of total representation level when \code{target_type = "relative"}
#'   (the default), or absolute targets when \code{target_type = "absolute"}.
#'   The order of the targets should match the ordering in the \code{features}
#'   argument.
#' @param rij numeric matrix (optional); matrix of representation levels of
#'   conservation features (rows) within planning units (columns). \code{rij} be
#'   a sparse matrix from the \code{slam} package (i.e. a
#'   \code{\link[slam]{simple_triplet_matrix}}) or a normal base matrix object.
#'   Alternatively, a data frame representation of this matrix with three
#'   variables: feature index (\code{rij$feature}), planning unit index
#'   (\code{rij$pu}), and corresponding representation level
#'   (\code{rij$amount}). If this matrix is not provided it will be calculated
#'   based on the planning units and RasterStack of conservation feature
#'   distributions.
#' @param locked_in integer; indices of planning units to lock in to final
#'   solution. For example, it may be desirable to lock in planning units
#'   already within protected areas
#' @param locked_out integer; indices of planning units to lock out of final
#'   solution. For example, it may be desirable to lock in planning units that
#'   are already heavily developed and therefore have little viable habitat.
#' @param target_type "relative" or "absolute"; specifies whether the
#'   \code{target} argument should be interpreted as relative to the total level
#'   of representation or as an absolute target
#'
#' @return A \code{prioritizr_model} object describing the prioritization
#'   problem to be solved. This is an S3 object consisting of a list with the
#'   following components:
#'
#' \itemize{
#'   \item \code{cost}: numeric vector of planning unit costs
#'   \item \code{rij}: representation matrix
#'   \item \code{targets}: absolute feature targets
#'   \item \code{locked_in}: indices of locked in planning units
#'   \item \code{locked_out}: indices of locked out planning units
#' }
#'
#' @export
#' @examples
#' # raster 100x100 template
#' e <- raster::extent(0, 100, 0, 100)
#' r <- raster::raster(e, nrows = 100, ncols = 100, vals = 1)
#'
#' # generate 9 feature distributions with different scales and range sizes
#' f <- mapply(function(x, y, r) gaussian_field(r = r, range = x, prop = y),
#'             rep(c(5, 15, 25), each = 3),
#'             rep(c(0.1, 0.25, 0.5), times = 3),
#'             MoreArgs = list(r = r))
#' f <- raster::stack(f)
#' f <- setNames(f, letters[1:raster::nlayers(f)])
#' # genrate cost layer
#' cost <- gaussian_field(r, 20, mean = 1000, variance = 500)
#' cost <- setNames(cost, "cost")
#' # prepare prioritization model
#' model <- prioritizr_model(pu = cost, features = f,
#'                           # 20% targets
#'                           targets = 0.2,
#'                           # lock first 10 planning units in
#'                           locked_in = 1:10,
#'                           # lock last 10 planning units out
#'                           locked_out = 91:100)
#'
#' # targets can also be species specific
#' ss_targets <- runif(raster::nlayers(f))
#' ss_targets
#' model <- prioritizr_model(pu = cost, features = f, targets = ss_targets)
#'
#' # or targets can be absolute
#' abs_targets <- ss_targets * raster::cellStats(f, "sum")
#' abs_targets
#' model <- prioritizr_model(pu = cost, features = f,
#'                           targets = abs_targets, target_type = "absolute")
#'
#' # planning units can also be supplied as a SpatialPolygonsDataFrame object
#' # with cost stored as an attribute (pu$cost). Typically the function takes
#' # longer to execute with polygons because summarizing features over planning
#' # units is less efficient.
#' model_spdf <- prioritizr_model(pu = cost, features = f, targets = 0.2)
prioritizr_model <- function(pu, features, targets, rij,
                             locked_in = integer(),
                             locked_out = integer(),
                             target_type = c("relative", "absolute"))  {
  UseMethod("prioritizr_model")
}

#' @export
prioritizr_model.Raster <- function(pu, features, targets, rij,
                                    locked_in = integer(),
                                    locked_out = integer(),
                                    target_type = c("relative", "absolute")) {
  # assertions on arguments
  assert_that(raster::nlayers(pu) == 1,
              is_integer(locked_in),
              all(locked_in > 0),
              all(locked_in <= raster::ncell(pu)),
              is_integer(locked_out),
              all(locked_out > 0),
              all(locked_out <= raster::ncell(pu)),
              # can't be locked in and out
              length(intersect(locked_in, locked_out)) == 0,
              is.numeric(targets))

  # convert 1-band RasterStack to RasterLayer
  pu <- pu[[1]]

  # representation matrix rij
  if (missing(rij)) {
    # if not provided, calculate it
    assert_that(inherits(features, "Raster"),
                raster::compareRaster(pu, features))
    rij <- slam::as.simple_triplet_matrix(t(unname(features[])))
  } else {
    # ensure that rij is a matrix, sparse matrix, or data frame
    assert_that(inherits(rij, c("matrix", "simple_triplet_matrix",
                                "data.frame")))
    if (is.matrix(rij)) {
      rij <- slam::as.simple_triplet_matrix(unname(rij))
    } else if (is.data.frame(rij)) {
      rij <- df_to_matrix(rij,
                          ncol = raster::ncell(pu),
                          vars = c("feature", "pu", "amount"))
    }
    # number of columns should be equal to number of planning units
    assert_that(rij$ncol == raster::ncell(pu))
  }

  # representation targets
  target_type <- match.arg(target_type)
  assert_that(length(targets) == rij$nrow || length(targets) == 1)
  if (length(targets) == 1) {
    targets <- rep(targets, rij$nrow)
  }
  # set proportional targets or check absolute targets
  if (target_type == "relative") {
    # convert relative targets to absolute targets
    targets <- set_targets(slam::row_sums(rij), targets)
  } else {
    # check that all targets are attainable
    assert_that(all(targets <= slam::row_sums(rij)))
  }

  structure(
    list(
      cost = pu[],
      rij = rij,
      targets = targets,
      locked_in = sort(as.integer(locked_in)),
      locked_out = sort(as.integer(locked_out))
    ),
    class = "prioritizr_model"
  )
}

#' @export
prioritizr_model.SpatialPolygons <- function(pu, features, targets, rij,
                                    locked_in = integer(),
                                    locked_out = integer(),
                                    target_type = c("relative", "absolute")) {
  # assertions on arguments
  assert_that("cost" %in% names(pu),
              is_integer(locked_in),
              all(locked_in > 0),
              all(locked_in <= raster::ncell(pu)),
              is_integer(locked_out),
              all(locked_out > 0),
              all(locked_out <= raster::ncell(pu)),
              # can't be locked in and out
              length(intersect(locked_in, locked_out)),
              is.numeric(targets))

  # representation matrix rij
  if (missing(rij)) {
    # if not provided, calculate it
    assert_that(inherits(features, "Raster"))
    rij <- summarize_features(pu, features)
  } else {
    # ensure that rij is a matrix, sparse matrix, or data frame
    assert_that(inherits(rij, c("matrix", "simple_triplet_matrix",
                                "data.frame")))
    if (is.matrix(rij)) {
      rij <- slam::as.simple_triplet_matrix(unname(rij))
    } else if (is.data.frame(rij)) {
      rij <- df_to_matrix(rij,
                          ncol = length(pu),
                          vars = c("feature", "pu", "amount"))
    }
    # number of columns should be equal to number of planning units
    assert_that(rij$ncol == length(pu))
  }

  # representation targets
  target_type <- match.arg(target_type)
  assert_that(length(targets) == rij$nrow || length(targets) == 1)
  if (length(targets) == 1) {
    targets <- rep(targets, rij$nrow)
  }
  # set proportional targets or check absolute targets
  if (target_type == "relative") {
    # convert relative targets to absolute targets
    targets <- set_targets(slam::row_sums(rij), targets)
  } else {
    # check that all targets are attainable
    assert_that(all(targets <= slam::row_sums(rij)))
  }

  structure(
    list(
      cost = pu[],
      rij = rij,
      targets = targets,
      locked_in = as.integer(locked_in),
      locked_out = as.integer(locked_out)
    ),
    class = "prioritizr_model"
  )
}
