#' Prepare a maximum coverage prioritization problem
#'
#' Specify a maximum coverage systematic conservation prioritization problem
#' from input data in a variety of formats. These are constructor functions for
#' \code{maxcover_model} objects which encapsulate prioritization problems in
#' a standardized format.
#'
#' @details In the context of systematic reserve design, the maximum coverage
#'   problem seeks to find the set of planning units that maximizes the overall
#'   level of representation across a suite of conservation features, while
#'   keeping cost within a fixed budget. The cost is often either the area of
#'   the planning units or the opportunity cost of foregone commericial
#'   activities (e.g. from logging or agriculture). Representation level is
#'   typically given by the occupancy within each planning unit, however, some
#'   measure of abundance or probability of occurence may also be used.
#'
#'   This problem is roughly the opposite of what the conservation planning
#'   software Marxan does.
#'
#' @param pu RasterLayer or SpatialPolygonsDataFrame object; the planning
#'   units to use in the reserve design exercise and their corresponding cost.
#'   If a RasterLayer object is provided the cost should be stored in the cell
#'   values and if a SpatialPolygonsDataFrame object is provided it should have
#'   an attribute field named \code{pu}.
#'
#'   If \code{pu} is a RasterLayer, it may be desirable to exlcude some
#'   planning units from the analysis, for example those outside the study
#'   area. To exclude planning units, set the cost for those raster cells to
#'   \code{NA}.
#' @param features RasterStack object; the distribution of conservation
#'   features. If \code{pu} is a Raster object then \code{features} should be
#'   defined on the same raster template. If \code{pu} is a
#'   SpatialPolygonsDataFrame \code{features} will be summarize over the
#'   polygons using \code{\link{summarize_features}}. Not required if
#'   \code{rij} is provided.
#' @param budget numeric; budget for reserve.
#' @param rij numeric matrix (optional); matrix of representation levels of
#'   conservation features (rows) within planning units (columns). \code{rij}
#'   can be a sparse matrix from the \code{slam} package (i.e. a
#'   \code{\link[slam]{simple_triplet_matrix}}) or a normal base matrix object.
#'   Alternatively, a data frame representation of this matrix with three
#'   variables: feature index (\code{rij$feature}), planning unit index
#'   (\code{rij$pu}), and corresponding representation level
#'   (\code{rij$amount}). If this matrix is not provided it will be calculated
#'   based on the planning units and RasterStack of conservation feature
#'   distributions.
#' @param locked_in integer; indices of planning units to lock in to final
#'   solution. For example, it may be desirable to lock in planning units
#'   already within protected areas.
#' @param locked_out integer; indices of planning units to lock out of final
#'   solution. For example, it may be desirable to lock in planning units that
#'   are already heavily developed and therefore have little viable habitat.
#'
#' @return A \code{maxcoverage_model} object describing the prioritization
#'   problem to be solved. This is an S3 object consisting of a list with the
#'   following components:
#'
#' \itemize{
#'   \item \code{cost}: numeric vector of planning unit costs
#'   \item \code{rij}: representation matrix
#'   \item \code{budget}: budger for reserve
#'   \item \code{locked_in}: indices of locked in planning units
#'   \item \code{locked_out}: indices of locked out planning units
#'   \item \code{included}: logical vector indicating which planning units are
#'     to be included in the analysis. If all units are to be included, this is
#'     single value (\code{TRUE}). Using a subset of planning units is only
#'     permitted if the \code{pu} argument is provided as a RasterLayer object.
#' }
#'
#' @export
#' @examples
#' # 5x5 raster template
#' e <- raster::extent(0, 1, 0, 1)
#' r <- raster::raster(e, nrows = 5, ncols = 5, vals = 1)
#'
#' # generate 4 random feature distributions
#' set.seed(1)
#' f <- raster::stack(r, r, r, r)
#' f[] <- sample(0:1, raster::nlayers(f) * raster::ncell(f), replace = TRUE)
#' f <- setNames(f, letters[1:raster::nlayers(f)])
#' # genrate cost layer
#' cost <- r
#' cost[] <- rnorm(raster::ncell(cost), mean = 100, sd = 10)
#' cost <- setNames(cost, "cost")
#'
#' # prepare prioritization model with budget at 25% of total cost
#' b_25 <- 0.25 * raster::cellStats(cost, "sum")
#' model <- maxcover_model(pu = cost, features = f, budget = b_25)
#'
#' # the representation matrix (rij) can be supplied explicitly,
#' # in which case the features argument is no longer required
#' rep_mat <- unname(t(f[]))
#' model <- maxcover_model(pu = cost, rij = rep_mat, budget = b_25)
#'
#' # cells can be locked in or out of the final solution
#' model <- maxcover_model(pu = cost, features = f, budget = b_25,
#'                         locked_in = 6:10,
#'                         locked_out = 16:20)
#'
#' # if some cells are to be exlcuded, e.g. those outside study area, set
#' # the cost to NA for these cells.
#' cost_na <- cost
#' cost_na[6:10] <- NA
#' model_na <- maxcover_model(pu = cost_na, features = f, budget = b_25)
#' # the model object now contains an included component specifying which
#' # cells are to be included
#' model_na$included
#' which(!model_na$included)
#' # note that the representation matrix now has fewer columns because
#' # the decision variables corresponding to exlcuded cells have been removed
#' model$rij
#' model_na$rij
#'
#' # planning units can also be supplied as a SpatialPolygonsDataFrame object
#' # with cost stored as an attribute (pu$cost). Typically the function takes
#' # longer to execute with polygons because summarizing features over planning
#' # units is less efficient.
#' cost_spdf <- raster::rasterToPolygons(cost)
#' model_spdf <- maxcover_model(pu = cost_spdf, features = f, budget = b_25,)
maxcover_model <- function(pu, features, budget, rij,
                             locked_in = integer(),
                             locked_out = integer())  {
  UseMethod("maxcover_model")
}

#' @export
maxcover_model.Raster <- function(
  pu, features, budget, rij,
  locked_in = integer(),
  locked_out = integer()) {
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
              assertthat::is.number(budget), budget > 0,
              # budget isn't exceeded by locked in cells
              sum(cost[][locked_in], na.rm = TRUE) <= budget)

  # convert 1-band RasterStack to RasterLayer
  pu <- pu[[1]]

  # check for NA cells indicating planning units to exclude
  pu_na <- is.na(pu[])
  if (any(pu_na)) {
    # logical vector indicating included planning units
    included <- !pu_na
  } else {
    # all planning units included
    included <- TRUE
  }
  rm(pu_na)

  # prepare cost vector
  cost <- pu[]
  # subset to included planning units
  cost <- cost[included]

  # representation matrix rij
  if (missing(rij)) {
    # if not provided, calculate rij
    assert_that(inherits(features, "Raster"),
                raster::compareRaster(pu, features))
    # subset to included planning units
    features <- features[][included,]
    rij <- slam::as.simple_triplet_matrix(t(unname(features)))
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
    # subset to included planning units
    if (!isTRUE(included)) {
      rij <- rij[, included]
    }
  }
  # feature representations levels must be not be missing
  if (!all(is.finite(rij$v) & is.numeric(rij$v))) {
    stop("Representation matrix cannot have missing or non-numeric values.")
  }

  # shift locked cells if some planning units are excluded
  if (!isTRUE(included)) {
    # locked in
    if (length(locked_out) > 0) {
      lock <- rep(FALSE, raster::ncell(pu))
      lock[locked_in] <- TRUE
      lock <- lock[included]
      locked_in <- which(lock)
    }
    # locked out
    if (length(locked_out) > 0) {
      lock <- rep(FALSE, raster::ncell(pu))
      lock[locked_out] <- TRUE
      lock <- lock[included]
      locked_out <- which(lock)
    }
  }

  structure(
    list(
      cost = cost,
      rij = rij,
      budget = budget,
      locked_in = sort(as.integer(locked_in)),
      locked_out = sort(as.integer(locked_out)),
      included = included
    ),
    class = c("maxcover_model", "prioritizr_model")
  )
}

#' @export
maxcover_model.SpatialPolygons <- function(
  pu, features, budget, rij,
  locked_in = integer(),
  locked_out = integer()) {
  # assertions on arguments
  assert_that("cost" %in% names(pu),
              is_integer(locked_in),
              all(locked_in > 0),
              all(locked_in <= raster::ncell(pu)),
              is_integer(locked_out),
              all(locked_out > 0),
              all(locked_out <= raster::ncell(pu)),
              # can't be locked in and out
              length(intersect(locked_in, locked_out)) == 0,
              is.numeric(budget),
              # budget isn't exceeded by locked in cells
              sum(pu$cost[locked_in], na.rm = TRUE) <= budget)

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
  # feature representations levels must be not be missing
  if (!all(is.finite(rij$v) & is.numeric(rij$v))) {
    stop("Representation matrix cannot have missing or non-numeric values.")
  }

  structure(
    list(
      cost = pu[],
      rij = rij,
      budget = budget,
      locked_in = as.integer(locked_in),
      locked_out = as.integer(locked_out),
      included = TRUE
    ),
    class = c("maxcover_model", "prioritizr_model")
  )
}