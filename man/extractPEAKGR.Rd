% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/functions-validPEAKS_helpers.R
\name{extractPEAKGR}
\alias{extractPEAKGR}
\title{Extract peak-group data from every sample}
\usage{
extractPEAKGR(pkg, object, samples)
}
\arguments{
\item{pkg}{\code{numeric} specifying a peak-group-of-interest.}

\item{object}{\code{massFlowTemplate} class object.}

\item{samples}{\code{data.frame} with experiment's metadata.}
}
\value{
Function returns a \code{data.frame} with centWave values for the peak-group-of-interest in every sample.
}
\description{
Extract peak-group data from every sample
}
