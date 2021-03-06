
# a variety of functions that all deal with sampling from the big lists of
# quantities that were simulated by, for example, simulate_and_calc_Q

# these functions are where the actual Monte Carlo and Importance Sampling
# takes place.


#### NON-EXPORTED FUNCTIONS #####
# non-exported helper function to format printing of mixing proportions of relationships
#
# If R is just a single name it just prints that name.  If it is a named vector of
# proportions, it prints them as they are
# @param R the relationship.
# @param colchars What characters should go between then relationships in the formatting
# @examples
# format_mixed_r(c(U=.9997, FS=.0001, PO=.00001, HS=.0002))
format_mixed_r <- function(R, colchars = ",") {
  if (length(R) == 1) {
    return(paste(R))
  }

  if (is.null(names(R))) stop("argument R must be a named vector if it has length > 1 in format_mixed_r")

  paste(paste(names(R), R, sep = "="), collapse = colchars)
}


## This is the importance sampling workhorse function...
# Q is for Qvals, nu is the relationship in the numerator of lambda,
# de is the relationship in the denominator of lambda which always be
# U in the current context, tr is the true
# relationship, which will typically be taken to be "U" in these
# contexts, and pstar is the relationship of the importance sampling
# distribution, which in this context will almost always by nu.
# FNRs are the false negative rates you want to investigate.
# In some cases you might want to specify the Lambda_Star cutoffs
# instead of the FNRs.  You can do that, too---just specify those
# lambda_star values as a vector and they will be added to the
# lambda_star values used by the FNRs.
imp_samp <- function(Q, nu, de, tr, pstar, FNRs, lambda_stars = NULL, Q_for_FNRs) {
  # get the importance weights and the corresponding lambdas when
  # the sample is from pstar
  iw <- tibble(lambda = Q[[pstar]][[nu]] - Q[[pstar]][[de]],
                   impwt = exp(Q[[pstar]][[tr]] - Q[[pstar]][[pstar]])) %>%
    dplyr::arrange(dplyr::desc(lambda)) %>%
    dplyr::mutate(FPR = cumsum(impwt))

  # and now we gotta get the lambdas for the true correct relationship
  trues <- Q_for_FNRs[[nu]][[nu]] - Q_for_FNRs[[nu]][[de]]

  # get the lambda values those correspond to
  cutoffs <- quantile(trues, probs = FNRs)

  if (!is.null(lambda_stars)) {  # here we need to add stuff on there
    fnrs2 <- colMeans(outer(trues, lambda_stars, "<"))  # this gets the false negative rates corresponding to the lambda_stars
    # then add those values into FNRs and cutoffs
    FNRs <- c(FNRs, fnrs2)
    cutoffs <- c(cutoffs, lambda_stars)
  }

  # then get the FPRs for each of those
  fpr <- lapply(cutoffs, function(x) {
    tmp <- iw$impwt
    tmp[iw$lambda < x] <- 0.0
    mean(tmp) # mean here is summing them up and then dividing by length
  }) %>% unlist() %>% unname()

  # also get the estimated standard error of the estimate
  se <- lapply(cutoffs, function(x) {
    tmp <- iw$impwt
    tmp[iw$lambda < x] <- 0.0  # set the weights less than lambda-star to zero
    sd(tmp) / sqrt(length(tmp))  # this is the standard error of the mean
  }) %>% unlist() %>% unname()

  # and also get the number of non-zero importance weights
  nnz <- lapply(cutoffs, function(x) {
    sum(iw$lambda >= x)
  }) %>% unlist() %>% unname()

    tibble(FNR = FNRs, FPR = fpr, se = se, num_nonzero_wts = nnz, Lambda_star = cutoffs) %>%
      dplyr::arrange(FNR, Lambda_star)
}


# this is a quick function to compute the false positive rates using
# vanilla monte carlo.  In this case, lambdas are computed as numerator
# over denominator, and the true sampling dsn is tr.
vanilla <- function(Q, nu, de, tr, FNRs, lambda_stars = NULL) {
  true <- Q[[tr]][[nu]] - Q[[tr]][[de]]  # this is the distribution of Logls under the true relationship
  nume <- Q[[nu]][[nu]] - Q[[nu]][[de]]  # this is the distribution of Logls under the relationship of the numerator

  # get the lambda values those correspond to
  cutoffs <- quantile(nume, probs = FNRs)


  if (!is.null(lambda_stars)) {  # here we need to add stuff on there
    fnrs2 <- colMeans(outer(nume, lambda_stars, "<"))  # this gets the false negative rates corresponding to the lambda_stars
    # then add those values into FNRs and cutoffs
    FNRs <- c(FNRs, fnrs2)
    cutoffs <- c(cutoffs, lambda_stars)
  }


  # then get the FPRs corresponding to each of those
  tmp <- lapply(cutoffs, function(x) {
    mean(true > x)
  }) %>%
    unlist() %>%
    unname()


  tibble(FNR = FNRs, FPR = tmp, Lambda_star = cutoffs) %>%
    dplyr::arrange(FNR)
}



#### EXPORTED FUNCTIONS #####
#' sample Q values to get and analyze a sample of Lambdas with simple (non-mixture) hypotheses
#'
#' Once you have gotten an object of class Qij from \code{\link{simulate_Qij}} you can pass that
#' to this function along with instructions on what quantities to compute.
#' This version assumes that the denominator of Lambda and the true relationship can be specified as a
#' a simple, single
#' relationship (typically, and by default, "U"), rather than a mixture of
#' possible relationships. Code for the latter has not yet been implemented.
#'
#' The output is a long format data frame.
#' @param Q the Qij object that is the output of simulate_Qij.
#' @param nu the name of the relationship that is in the \strong{nu}merator
#' of the likelihood ratio (Lambda) whose distribution you wish to learn about.
#' It is a string, for example "FS", or "PO", or "U".  The Q values for that
#' relationship must be included in parameter Q.  If this is a vector, then
#' all different values are used in combination with all the values of
#' \code{de}, \code{tr}, and, possibly, \code{pstar}. Corresponds to column "numerator" in the output
#' @param de the relationship that appears in the \strong{de}nominator of Lambda.
#' By default it is "U".  Corresponds to column "denominator" in the output. If it
#' is a vector, then all values are done iteratively in combination with other values as
#' described for \code{nu}.
#' @param tr the true relationship of the pairs. Default is "U". (i.e. you are going to
#' get samples of Lambda under their distribution when the true relationship is tr).
#' Operates over all values if a vector. Corresponds to column "true_relat" in the
#' output.
#' @param method the Monte Carlo method to use.  Either "IS" for importance sampling,
#' "vanilla" for vanilla Monte Carlo---regular Monte Carlo without importance sampling---or
#' or "both". The method that was used for any row of the output is reported in the
#' column "mc_method".
#' @param pstar the relationship used for the importance sampling distribution.
#' If set as NA and importance sampling (method == "IS" or "both") is used, then
#' the value of \code{nu} is used as need be.  If not NA, then this can be a vector
#' of relationships.  Each value will be used in all combinations of pstar, nu, de, and tr.
#' This is reported in column "pstar" in the output. For the vanilla method this is
#' actually set to the be denominator for each lambda.
#' @param FNRs the false negative rates at which to evaluate the false positive rates.
#' These are reported in column "fnr" in the output. These should all be between
#' 0 and 1.  By default fnr is c(0.3, 0.2, 0.1, 0.05, 0.01, 0.001).
#' @param lambda_stars Additional values of lambda to consider as cutoffs.  The corresponding
#' false negative rates will be computed for each of these and will be presented in the output.
#' @param Q_for_fnrs The Qij struct to use to compute the Lambda values corresponding to the
#' given FNRs. This is used primarily for the situation where you are importance sampling with
#' truth = Unrelated and doing physically linked markers.
#' @return A long format data frame.  It will have a column of \code{tot_loci} that gives the total
#' number of loci.
#'
#' @export
mc_sample_simple <- function(Q,
                             nu,
                             de = "U",
                             tr = "U",
                             method = c("IS", "vanilla", "both")[1],
                             pstar = NA,
                             FNRs = c(0.3, 0.2, 0.1, 0.05, 0.01),
                             lambda_stars = NULL,
                             Q_for_fnrs = NULL
) {

  #### here test that everything is OK and catch input errors  ####
#  stopifnot(length(nu) == 1, length(de) == 1, length(tr) == 1, length(pstar) == 1)
  stopifnot(is.character(nu) == TRUE,
            is.character(de) == TRUE,
            is.character(tr) == TRUE,
            is.na(pstar) || is.character(pstar) == TRUE)
  tr_lack <- setdiff(c(tr, pstar[!is.na(pstar)]), names(Q))
  if (length(tr_lack) > 0) stop("Asking for relationships in tr or pstar that are not available in Q: ",
                               paste(tr_lack, collapse = ", "))
  nu_lack <- setdiff(c(nu, de), unique(unlist(lapply(Q, names))))
  if (length(nu_lack) > 0) stop("Asking for relationships in nu or de that are not available in Q: ",
                                paste(nu_lack, collapse = ", "))
  stopifnot(all(FNRs > 0  & FNRs < 1) == TRUE)
  stopifnot(length(method) == 1, method %in% c("IS", "vanilla", "both"))
  if (attributes(Q)$simtype == "linked" && method %in% c("IS", "both")) {
    stop("Error! Sorry, you cannot do importance sampling with Q coming from a simulation of linked variables.
          Importance sampling for linked markers can be done when the true relationship is Unrelated by setting
          Q to be unlinked while Q_for_fnrs is the corresponding linked version of the Qs.")
  }

  # deal with Q_for_FNRs
  if (is.null(Q_for_fnrs)) {
    Q_for_fnrs <- Q
    SingleQ <- TRUE
  } else {
    SingleQ <- FALSE
  }


  #### cycle over different relationships and do the calculations ####

  lapply(nu, function(nu_) {
    lapply(de, function(de_) {
      lapply(tr, function(tr_) {
        is <- NULL  # setting these to default NULL for easy row-binding later if they didn't get set
        van <- NULL
        if (method == "IS" || method == "both") {
          if (is.na(pstar)) {  # just taking care of defaulting pstar to nu_ if pstar is NA
            pstar_tmp <- nu_
          } else {
            pstar_tmp <- pstar
          }
          is <- lapply(pstar_tmp, function(pstar_) {
            tmp <- imp_samp(Q = Q, nu = nu_, de = de_, tr = tr_, pstar_, FNRs, lambda_stars, Q_for_fnrs)
            tmp$pstar <- pstar_
            tmp
          }) %>%
            dplyr::bind_rows()

          is$mc_method = "IS"
        }
        if (method == "vanilla" || method == "both") {
          van <- vanilla(Q = Q, nu = nu_, de = de_, tr = tr_, FNRs, lambda_stars)
          van$pstar = NA
          van$mc_method = "vanilla"
        }
        ret <- dplyr::bind_rows(is, van)
        ret$numerator = nu_
        ret$denominator = de_
        ret$true_relat = tr_
        ret
      }) %>%
        dplyr::bind_rows()
    }) %>%
      dplyr::bind_rows()
  }) %>%
    dplyr::bind_rows()
}

