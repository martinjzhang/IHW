#' Stratify hypotheses based on increasing value of the covariate
#'
#'  Hypotheses are stratified into nbins different strata of (approximately) equal size based on
#' increasing value of the covariate
#'
#' @param covariate Numeric vector of ordinal covariates based on which the stratification will be done.
#' @param nbins Integer, number of groups/strata into which p-values will be split based on covariate.
#' @param ties.method Character specifying how ties are treated, see \code{\link{rank}} function.
#' @param seed Integer, specifies random seed to be used when ties.method=="random".
#' @return A factor with nbins different levels, each entry corresponds to the stratum the i-th hypothesis
#'  was assigned to.
#' @examples
#'  covariates <- runif(100)
#'  groups <- groups_by_filter(covariates,10)
#'  table(groups)
#' @export
groups_by_filter <- function(covariate, nbins, ties.method="random", seed=NULL){
  if (!is.null(seed) && ties.method=="random"){
    #http://stackoverflow.com/questions/14324096/setting-seed-locally-not-globally-in-r?rq=1
    tmp <- runif(1)
    old <- .Random.seed
    on.exit( { .Random.seed <<- old } )
    set.seed(as.integer(seed)) 
  }
	rfs <- rank(covariate, ties.method=ties.method)/length(covariate)
	as.factor(ceiling( rfs* nbins))
}

# given list of adjusted p-values and original p-values
# calculate actual threshold! 
padj_to_threshold <- function(padj, pvals, alpha){
	filtered_pvals <- pvals[padj <= alpha]
	ifelse(length(filtered_pvals) == 0, 0, max(filtered_pvals))
}


mydiv <- function(x,y) ifelse(x == 0, 0, 
						 ifelse(y==0, 1, pmin(x/y,1)))

# returns a threshold!
filter_pvals_for_optim <- function(pvals, alpha, ntests=length(pvals)){
	nrjs <- sum(p.adjust(pvals, method="BH", n = ntests) < alpha)
	min(1, 10*nrjs/length(pvals))
}

#'  Data-driven threshold of Benjamini Hochberg Procedure
#'
#'       Given pvalues and a nominal significance level alpha, this function returns the
#'   rejection threshold of the Benjamini-Hochberg procedure, i.e. a value t_BH such that p-values with
#'   P_i <= t_BH get rejected by the procedure.
#'
#' @param pvals Numeric, vector of p-values
#' @param alpha Numeric in [0,1], significance level of the multiple testing procedure
#' @param mtests Integer, total number of hypothesis tests; only set this (to non-default) when you know what you are doing!
#'
#' @return A numeric in [0,1], threshold of the BH procedure
#'
#' @examples
#' pvalues <- c(runif(1000), rbeta(1000,0.5,7)) # generate some p-values
#' adj_pvalues <- p.adjust(pvalues, method="BH") # calculate adjusted p-values
#' t_BH  <- get_bh_threshold(pvalues, 0.1) #get rejection threshold at alpha=0.1
#' all((pvalues <= t_BH) == (adj_pvalues <= 0.1)) #equivalence of two formulations
#'
#' @export
get_bh_threshold <- function(pvals, alpha, mtests = length(pvals)){
  m <- length(pvals)
  pvals <- sort(pvals)
  prejected <- which(pvals <= (1:m)/mtests*alpha)
  ifelse(length(prejected)==0, 0, pvals[prejected[which.max(prejected)]])
}




get_bh_thresholds <- function(unadj_p, filterstat, nbins, alpha){
	t <- get_bh_threshold(unadj_p, alpha)
	grps <- groups_by_filter(filterstat, nbins)
	pv_list <- split(unadj_p, grps)
	sapply(pv_list, function(ps) max(0, ps[ps <=t]))
}

get_wbh_weights<- function(obj){
	weighted_pv <- pvalues(obj)/weights(obj, levels_only=FALSE)
	t <- get_bh_threshold(weighted_pv, alpha(obj))
	m_groups <- table(groups_factor(obj))
	grps <- groups_factor(obj)
	pv_list <- split(pvalues(obj), grps)
	ts <- sapply(pv_list, function(ps) max(0, ps[ps <=t]))
	ts*sum(m_groups)/sum(ts*m_groups)
}


lsl_pi0_est <- function(pvalue){
  n <- length(pvalue)
  ls <- (n:1)/(1-sort(pvalue))
  ls_diff <- ls[-c(1,2)] - ls[-c(1,n)]
  index <- min(which(ls_diff > 0))+2
  if (index == Inf) {
    pi0 <- 1
  } else {
    pi0 <- min(1, (1+floor(ls[index]))/n)
  }
  pi0
}

fill_nas_reorder <- function (reduced_vector, nna, order){
  if (length(nna)==1 && nna){
    full_vector <- reduced_vector[order]
  } else {
    full_vector <- rep(NA, length(nna))
    full_vector[nna] <- reduced_vector[order]
  }
  full_vector
}

rand_cbum <- function(pvals, tau=0.1){
  cbum_fit <- CBUM(pvals, start.pi0=0.5, thresh.censor=tau, 
                   eps=1e-5, niter=Inf, verbose=FALSE)


  alpha <- attr(cbum_fit, "alpha")
  tau <- attr(cbum_fit, "thresh.censor")
  pi0 <- as.numeric(cbum_fit)

  gamma <- (pi0 - alpha)/(1-alpha) #check sign etc?
  n <- sum(pvals <= tau)

  Hs <- 1-rbinom(n, 1, gamma) 
  sim_pvals <- runif(n)

  sim_pvals[Hs==0] <- sim_pvals[Hs==0]*tau
  # inverse transform sampling
  if (sum(Hs) > 0){
    sim_pvals[Hs==1] <- qbeta(sim_pvals[Hs==1]*pbeta(tau, alpha,1) , alpha, 1)
  }

  pvals[pvals <= tau] <- sort(sim_pvals)
  pvals
}
