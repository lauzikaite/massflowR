# checkFILE -------------------------------------------------------------------------------------------------------
#' @title Check and load file for peak alignment
#' 
#' @description Internal function used within method \code{\link{alignPEAKS}}.
#' Function checks if file contains all neccessary columns and returns loaded \code{data.frame} if it is correct.
#'
#' @param file \code{character} with absolute path to peak-group table.
#'
#' @return Function returns a \code{data.frame} of the corresponding file, if table was written correctly.
#' 
checkFILE <- function(file = NULL) {
  if (!file.exists(file)) {
    stop("incorrect filepath for: ", file)
  }
  dt <- read.csv(file, stringsAsFactors = F)
  required_colnames <-
    c("peakid",
      "mz",
      "mzmin",
      "mzmax",
      "rt",
      "rtmin",
      "rtmax",
      "into",
      "peakgr")
  if (any(!required_colnames %in% colnames(dt))) {
    stop(
      "incorrect file: ",
      file,
      " \n ",
      "missing columns: ",
      paste0(required_colnames[which(!required_colnames %in% colnames(dt))], collapse = ", ")
    )
  }
  return(dt)
}

# do_alignPEAKS -------------------------------------------------------------------------------------------------------
#' @title Align dataset's and template peaks using dot-product estimation
#' 
#' @description Internal function used within method \code{\link{alignPEAKS}} and function \code{\link{annotatePEAKS}}.
#' Function aligns all dataset's peaks to the template using dot-product estimation.
#' 
#' @param ds \code{data.frame} containing peaks which have to be compared and aligned with the template.
#' @param tmp \code{data.frame} representing a template with which the dataset is compared to.
#' @param ds_var_name \code{character} indicating the column name for peak grouping information in the dataset.
#' Default is set to 'peakgr', which is the output of \code{groupPEAKS} method. 
#' @param tmp_var_name \code{character} indicating the column name for peak grouping information in the template.
#' If function is used within \code{alignPEAKS}, then 'peakgr' should be selected.
#' If function is used within \code{annotatePEAKS}, then 'chemid' should be selected.
#' @param mz_err \code{numeric} specifying the window for peak matching in the MZ dimension.
#' @param rt_err \code{numeric} specifying the window for peak matching in the RT dimension.
#' @param bins \code{numeric} defying step size used in peak-group spectra binning and vector generation. Step size represents MZ dimension.
#' @param ncores \code{numeric} for number of parallel workers to be used.
#'
#' @seealso For details on cosine estimation, refer to \code{\link{alignPEAKS}} method.
#'
#'@return Function returns a list of lenght of the number of peak-groups in the dataset.
#'Each list entry specifies the template's peak-group to which dataset's peak-group was aligned to, as well as matching peaks and obtained cosine.
#'
do_alignPEAKS <- function(ds,
                          tmp,
                          ds_var_name,
                          tmp_var_name,
                          mz_err,
                          rt_err,
                          bins,
                          ncores) {
  
  ####---- split dataset and template into rt regions for parallelisation
  rt_bins <- getRTbins(ds = ds,
                       tmp = tmp,
                       ds_var_name = ds_var_name,
                       tmp_var_name = tmp_var_name,
                       mz_err = mz_err,
                       rt_err = rt_err,
                       ncores = ncores)
  ds_bins <- rt_bins$ds
  tmp_bins <- rt_bins$tmp
  
  ds_vars_by_bins <- lapply(ds_bins, function(x) {
    unique(x[[match(ds_var_name, colnames(x))]])
  })
  ds_vars <- unique(unlist(lapply(ds_bins, "[[", ds_var_name)))
  tmp_vars <- unique(unlist(lapply(tmp_bins, "[[", tmp_var_name)))
  
  ####---- estimate cosines for matching peak-groups between dataset and template
  if (ncores > 1) {
    cos_matches <-
      foreach::foreach(bin = 1:ncores,
                       .inorder = TRUE) %dopar% (
                         massFlowR:::getCOSmat(
                           ds_bin = ds_bins[[bin]],
                           ds_var = ds_var_name,
                           tmp_bin = tmp_bins[[bin]],
                           tmp_var = tmp_var_name,
                           mz_err = mz_err,
                           rt_err = rt_err,
                           bins = bins
                         )
                       )
  } else {
    ## run with lapply to have the same, 2-list-within-a-bin-list, structure as with foreach
    cos_matches <- list(
      massFlowR:::getCOSmat(
        ds_bin = ds_bins[[1]],
        ds_var = ds_var_name,
        tmp_bin = tmp_bins[[1]],
        tmp_var = tmp_var_name,
        mz_err = mz_err,
        rt_err = rt_err,
        bins = bins)
    )
  }
  cos_mat <- matrix(0, nrow = length(tmp_vars), ncol = length(ds_vars))
  rownames(cos_mat) <- tmp_vars
  colnames(cos_mat) <- ds_vars
  
  for (bin in 1:ncores) {
    cos_mat_bin <- cos_matches[[bin]][[1]]
    cos_mat[match(rownames(cos_mat_bin), rownames(cos_mat), nomatch = 0),
            match(colnames(cos_mat_bin), colnames(cos_mat), nomatch = 0)] <-
      cos_mat_bin[match(rownames(cos_mat), rownames(cos_mat_bin), nomatch = 0),
                  match(colnames(cos_mat), colnames(cos_mat_bin), nomatch = 0)]
  }
  
  ####---- assign ds peakgroups to tmp according to cosines
  cos_assigned <- assignCOS(cos = cos_mat)
  ds_true <- apply(cos_assigned, 2, function(x) which(x))
  ds_assigned <- which(sapply(ds_true, length) > 0)
  ds_vars_assigned <- ds_vars[ds_assigned]
  tmp_assigned <- unlist(ds_true[ds_assigned])
  tmp_vars_assigned <- tmp_vars[tmp_assigned]
  
  ####---- extract matches for assigned peakgroups only
  ds_to_tmp <- rep(list(NA), length(ds_vars))

  for (var in 1:length(ds_vars)) {
    ds_var <- ds_vars[var]
    if (ds_var %in% ds_vars_assigned) {
      ## get the corresponding assigned tmp peagroup
      tmp_var <- tmp_vars_assigned[which(ds_vars_assigned == ds_var)]
      ## extract mathes between the assigned peakgroups
      bin <- which(sapply(ds_vars_by_bins, function(x) ds_var %in% x))
      mat <- cos_matches[[bin]][[2]][[which(ds_vars_by_bins[[bin]] == ds_var)]]
      mat <- mat[which(mat$tmp_var == tmp_var), ]
      ## extract cosine between the assigned peakgroups
      cos <- cos_mat[match(tmp_var, rownames(cos_mat)), match(ds_var, colnames(cos_mat))]
    } else {
      tmp_var <- NULL
      mat <- NULL
      cos <- NULL
    }
    ds_to_tmp[[var]] <- list("ds" = ds_var, "tmp" = tmp_var, "mat" = mat, "cos" = cos)
  }
  return(ds_to_tmp)
}

# getRTbins -------------------------------------------------------------------------------------------------------
#' @title Split a dataset-of-interest and template into \emph{rt} regions (bins) for parallelisation
#' 
#' @description Function splits a dataset and a template into \emph{rt} regions, each of which is analysed by an independent parallel worker.
#' 
#' @details Function firstly splits the dataset into as many sub-tables as there are parallel workers (could be 1, if serial implementation is selected).
#' Then template is split into the same number of sub-tables using \emph{rt} regions in the corresponding dataset's sub-tables.
#'
#' @param ds \code{data.frame} containing peaks which have to be compared and aligned with the template.
#' @param tmp \code{data.frame} representing a template with which the dataset is compared to.
#' @param ds_var_name \code{character} indicating the column name for peak grouping information in the dataset.
#' Default is set to 'peakgr', which is the output of \code{groupPEAKS} method. 
#' @param tmp_var_name \code{character} indicating the column name for peak grouping information in the template.
#' If function is used within \code{alignPEAKS}, then 'peakgr' should be selected.
#' If function is used within \code{annotatePEAKS}, then 'chemid' should be selected.
#' @param mz_err \code{numeric} specifying the window for peak matching in the MZ dimension.
#' @param rt_err \code{numeric} specifying the window for peak matching in the RT dimension.
#' @param ncores \code{numeric} for number of parallel workers to be used.
#'
#' @return Function returns a list with dataset and template tables split into \emph{rt} regions.
#'
getRTbins <- function(ds, tmp, ds_var_name, tmp_var_name, mz_err, rt_err, ncores) {
  ## order both peak tables by median rt of the peak-groups
  ds <- orderBYrt(dt = ds, var_name = ds_var_name)
  tmp <- orderBYrt(dt = tmp, var_name = tmp_var_name)
  
  ## get rt/mz error windows
  ds <- addERRS(dt = ds, mz_err = mz_err, rt_err = rt_err)
  tmp <- addERRS(dt = tmp, mz_err = mz_err, rt_err = rt_err)
  
  ## get rt region values using ds peak-groups
  ## assign DS peak-groups to bins
  ds_var_ind <- match(ds_var_name, colnames(ds))
  tmp_var_ind <- match(tmp_var_name, colnames(tmp))
  
  ## assign bin values to ds peak-groups so that each bin has more or less equal number of peak-groups
  ds_vars <- unique(ds[ , ds_var_ind])
  if (ncores > 1) {
    rt_bins <- as.numeric(cut(1:length(ds_vars), breaks = ncores))
  } else {
    rt_bins <- rep(1, length(ds_vars))
  }
  for (var in ds_vars) {
    ds[which(ds[, ds_var_ind] == var), "rt_bin"] <- rt_bins[which(ds_vars == var)]
  }
  ## split ds frame into corresponding bins and save sub-frames to a list
  ds_bins <- list()
  for (bin in 1:ncores) {
    ds_bins[[bin]] <- ds[which(ds$rt_bin == bin), ]
  }
  
  ## split template frame to bins using ds bins rt values
  tmp_bins <- list()
  for (bin in 1:ncores) {
    ## get all peaks that are below current bin max rt value,
    ## and have not been included in the previous bin
    rt_val_max <- max(ds_bins[[bin]]$rt_h)
    peakgrs_previous <- if (bin == 1) {
      0
    } else {
      tmp_bins[[bin - 1]][, tmp_var_ind]
    }
    tmp_by_rt <- tmp[which(tmp$rt_h <= rt_val_max &
                             !tmp[ , tmp_var_ind] %in% peakgrs_previous), ]
    ## also add peaks that belong to the same peak-group as any of the peaks matched by rt
    tmp_by_group <- tmp[which(tmp[ , tmp_var_ind] %in% tmp_by_rt[ , tmp_var_ind]), ]
    tmp_bins[[bin]] <- tmp_by_group
  }
  return(list(ds = ds_bins, tmp = tmp_bins))
}      

# orderBYrt -------------------------------------------------------------------------------------------------------
#' @title Order a peak table by variables' \emph{rt}
#'
#' @param dt \code{data.frame} of the peak table of interest.
#' @param var_name \code{character} specifying column name for variables which should be ordered by their \emph{rt}.
#' Depending on the step in the pipeline, variable name will be either 'peakgr', 'chemid' or 'pcs'.
#'
#' @return Function returns ordered \code{data.frame}. 
#' 
orderBYrt <- function(dt, var_name) {
  ## extract unique peak-groups or PCS or chemids
  var_ind <- match(var_name, colnames(dt))
  vars <- unique(dt[, var_ind])
  rt_med <- sapply(vars, function(var) {
    median(dt[which(dt[,var_ind] == var), "rt"])
  })
  var_levels <- factor(dt[, var_ind], levels = vars[order(rt_med)])
  dt_ordered <- dt[order(var_levels),]
  return(dt_ordered)
}

# addERRS ---------------------------------------------------------------------------------------------------------
#' @title Add peak matching error windows using user-defined \emph{m/z} and \emph{rt} values
#'
#' @description Function adds lower and higher values for \emph{m/z} and \emph{rt} values for each peak in the table.
#' @param dt \code{data.frame}
#' @param mz_err \code{numeric} specifying error value for \emph{m/z}.
#' @param rt_err \code{numeric} specifying error value for \emph{rt}.
#'
#' @return Function returns original \code{data.frame} with additional columns 'mz_l', 'mz_h', 'rt_l' and 'rt_h'.
#' 
addERRS <- function(dt, mz_err, rt_err) {
  dt[, c("mz_l",
         "mz_h",
         "rt_l",
         "rt_h")] <- c(dt$"mz"-mz_err,
                       dt$"mz"+mz_err,
                       dt$"rt"-rt_err,
                       dt$"rt"+rt_err)
  return(dt)
}

# getCOSmat ---------------------------------------------------------------------------------------------------------
#' @title Estimate cosine angles between the vectors representing dataset and template peak-groups
#' 
#' @description Function estimates cosine angles between matching dataset and template peak-groups.
#' Function is applied to a single \emph{rt} region(bin) and is used in parallel on multiple \emph{rt} regions.
#' Function is applied to \emph{rt} region within \code{\link{do_alignPEAKS}} function.
#' 
#' @param ds_bin \code{data.frame} for the single \emph{rt} region of the dataset.
#' @param ds_var \code{character} indicating the column name for peak grouping information in the dataset.
#' @param tmp_bin \code{data.frame} for the single \emph{rt} region of the template
#' @param tmp_var \code{character} indicating the column name for peak grouping information in the template.
#' @param mz_err \code{numeric} specifying the window for peak matching in the MZ dimension.
#' @param rt_err \code{numeric} specifying the window for peak matching in the RT dimension. 
#' @param bins \code{numeric} defying step size used in peak-group spectra binning and vector generation.#' 
#'
#' @return Function returns a list with two entries:
#' \itemize{
#'  \item \code{matrix} with obtained cosines between all dataset and template peak-groups.
#'  \item \code{list} with matching template peaks for every peak-group in the dataset.
#'  }
#' 
getCOSmat <- function(ds_bin, ds_var, tmp_bin, tmp_var, mz_err, rt_err, bins = 0.01) {
  
  ## which column indexes correspond to the given variable names in dataset and template
  ds_var_ind <- match(ds_var, colnames(ds_bin))
  ds_vars <- unique(ds_bin[ , ds_var_ind])
  tmp_var_ind <- match(tmp_var, colnames(tmp_bin))
  tmp_vars <- unique(tmp_bin[ , tmp_var_ind])
  
  ## initiate empty matrix to store cosine
  cos_mat <- matrix(0, nrow = length(tmp_vars), ncol = length(ds_vars))
  
  ## initiate empty list to store matching peaks
  mat_list <- vector(mode = "list", length = length(ds_vars))
  
  ## variable is a single DS peak-groups/PCS
  for(var in ds_vars) {
    
    ## get peaks that belong to this variable
    target <- ds_bin[which(ds_bin[, ds_var_ind] == var), ]
    
    ## match template peaks by mz/rt window
    matches <- apply(target, 1, FUN = getMATCHES, tmp = tmp_bin, tmp_var = tmp_var, target_var = ds_var)
    if (is.null(matches)) {
      next
    }
    matches <- do.call("rbind", matches)
    
    ## build mz spectra using all target peaks and all matched peaks
    matches_all <- tmp_bin[which(tmp_bin[, tmp_var_ind] %in% matches$tmp_var), ]
    all_peaks <- c(target$mz, matches_all$mz)
    spec <- data.frame(
      mz = seq(
        from = min(all_peaks),
        to = max(all_peaks),
        by = bins
      ))
    spec$bin <- 1:nrow(spec)
    
    ## convert target's and tmp peak-groups to vectors
    target_vec <- buildVECTOR(spec = spec, peaks = target)
    
    ## calculate cosines between target peak-group and all matched peak-groups
    ## cos length will be equal to l
    cos <- lapply(unique(matches$tmp_var), function(m) {
      ## extract peaks for the single peak-group
      matched_peaks <- matches_all[which(matches_all[, tmp_var_ind] == m),
                                   c("mz", "into")]
      
      ## build vector from matched peaks
      matched_vec <- buildVECTOR(spec = spec, peaks = matched_peaks)
      
      ## find the cosine of the angle between peakgrs
      cos_angle <-
        (sum(target_vec * matched_vec))  / ((sqrt(sum(
          target_vec * target_vec
        )))  * (sqrt(sum(
          matched_vec * matched_vec
        ))))
      return(round(cos_angle, 4))
    })
    
    ## update cosine matrix with cosines
    ## rows are tmp variables
    ## columns are ds variables
    cos_mat[match(unique(matches$tmp_var), tmp_vars), which(ds_vars == var)] <- unlist(cos)
    
    ## update matches list with tmp peaks with which cosine > 0 was obtained
    tmp_vars_pos <- unique(matches$tmp_var)[which(cos > 0)]
    mat_list[[which(ds_vars == var)]] <- matches[which(matches$tmp_var %in% tmp_vars_pos),]
    
  }
  rownames(cos_mat) <- tmp_vars
  colnames(cos_mat) <- ds_vars
  return(list("cos_mat" = cos_mat, "mat_list" = mat_list))
}

# getMATCHES ---------------------------------------------------------------------------------------------------------
#' @title Get template peaks that match the target peak by \emph{m/z} and \emph{rt} values
#' 
#' @description Function find all matching peaks in a template.
#' Broad \emph{m/z} and \emph{rt} values are used in the search.
#' Function is applied to every peak in a peak-group of interest.
#'
#' @param target_peak \code{matrix} with target peak's \emph{m/z} and \emph{rt} lower and higher values.
#' @param tmp \code{data.frame} representing a template in which matching peaks are looked for.
#' @param tmp_var \code{character} indicating the column name for peak grouping information in the template.
#' @param target_var \code{character} indicating the column name for peak grouping information in the target peak's \code{matrix}.
#'
#' @return Function returns a \code{data.frame} with matching template's peaks.
#' 
getMATCHES <- function(target_peak, tmp, tmp_var, target_var) {
  ## find matching template target_peaks using mz/rt windows of both target_peaks
  mat <- tmp[which((tmp$mz_l >= target_peak["mz_l"] &
                      tmp$mz_l <= target_peak["mz_h"]) |
                     (tmp$mz_h >= target_peak["mz_l"] &
                        tmp$mz_h <= target_peak["mz_h"])),]
  mat <- mat[which((mat$rt_l >= target_peak["rt_l"] &
                      mat$rt_l <= target_peak["rt_h"]) |
                     (mat$rt_h >= target_peak["rt_l"] &
                        mat$rt_h <= target_peak["rt_h"])),]
  if (nrow(mat) > 0) {
    mat$tmp_var <- mat[, match(tmp_var, names(mat))]
    mat$target_var <- target_peak[match(target_var, names(target_peak))]
    mat$target_peakid <- target_peak["peakid"]
    mat <- mat[ ,c("peakid", "mz", "rt", "into", "tmp_var", "target_peakid", "target_var")]
    return(mat)
  } else {
    return(NULL)
  }
}

# buildVECTOR ---------------------------------------------------------------------------------------------------------
#' @title Build a vector for a peak-group using peaks \emph{m/z} and intensity values
#' 
#' @description Function builds a vector for a peak-group using peaks \emph{m/z} and intensity values.
#' Function is used to compare multiple peak-groups.
#' A vector is build for each peak-group separately using full \emph{m/z} range, which includes all peaks from all peak-groups being compared.
#'
#' @param spec \code{data.frame} with columns 'mz', 'bin' and 'into'.
#' Contains a full range of \emph{m/z} values of all peak-groups that are being compared.
#' @param peaks \code{data.frame} with columns 'mz', 'bin' and 'into' for peaks in a single peak-group.
#'
#' @return Function returns a \code{numeric} vector representing peaks of a single peak-group.
#' 
buildVECTOR <- function(spec, peaks) {
  peaks$bin <- findInterval(x = peaks$mz, spec$mz)
  ## remove duplicating duplicating bins and any bins that are not representing a peak
  peaks <- peaks[which(!duplicated(peaks$bin)), c("bin", "into")]
  spec$into <- 0
  spec[match(peaks$bin, spec$bin), "into"] <- peaks$into
  vector <- scaleSPEC(spec = spec)
  return(vector)
}

# scaleSPEC ---------------------------------------------------------------------------------------------------------
#' @title Scale a vector representing peaks' intensity values
#' 
#' @description Function scales a vector representing peaks' intensity values before dot-product estimation of two vectors.
#' Currently, scaling to unit length is supported.
#'
#' @param spec \code{data.frame} with columns 'into' and 'mz'.
#'
#' @return Function returns a \code{numeric} vector with scaled intensity values.
#' 
#' @seealso \code{\link{getCOSmat}}
#' 
scaleSPEC <- function(spec) {
  ## Version A - scale to unit length
  spec$into / (sqrt(sum(spec$into * spec$into)))
  
  ## Version B - according to Stein & Scott, 1994
  # m = 0.6
  # n = 3
  ## scale the intensity of every mz ion separately
  ## use m and n weighting factors taken from Stein & Scott, 1994
  # apply(spec, 1, function(x) {
  #   x[["into"]] ^ m * x[["mz"]] ^ n
  # })
}

# assignCOS ---------------------------------------------------------------------------------------------------------
#' @title Assign dataset's peak-groups to template peak-groups based on estimated cosine angles
#'
#' @param cos \code{matrix} with cosine angles.
#' Rows correspond to template variables (i.e. peak-group).
#' Columns correspond to dataset-of-interest variables (i.e. peak-group).
#'
#' @return Function returns a \code{matrix} of the same dimension.
#' Peak-group pairs which should be aligned are marked with TRUE in the output matrix.
#' 
assignCOS <- function(cos) {
  ## rank by row, i.e. the template vars
  tmp_rank <- t(apply(cos, 1, FUN = rankCOS))
  ## rank by column, i.e. the ds vars
  ds_rank <- apply(cos, 2, FUN = rankCOS)
  ## assign peakgroup pairs which have the highest rank both row-wise and column-wise
  assigned <- matrix(FALSE, nrow = nrow(cos), ncol = ncol(cos))
  assigned[which(cos == 0)] <- NA
  assigned[which(ds_rank == tmp_rank & ds_rank == 1)] <- TRUE
  
  while (FALSE %in% assigned) {
    ## add NA to tmp peakgroups that were already assigned with ds peakgroups
    assigned <- apply(assigned, 2, function(x) {
      if (any(na.omit(x))) {
        x[which(x == FALSE)] <- NA
      }
      return(x)
    }
    )
    ## which rows and columns have any un-assigned peakgroups
    tmp_not_assigned <- which(apply(assigned, 1, function(x) {
      if (all(is.na(x))) {
        FALSE
      } else {
        !TRUE %in% x
      }
    }))
    ds_not_assigned <- which(apply(assigned, 2, function(x) {
      if (all(is.na(x))) {
        FALSE
      } else {
        !TRUE %in% x
      }
    }))
    ## for every un-assigned ds peakgroup
    for (var in ds_not_assigned) {
      ## order matches by rank
      current_ds_var <- ds_rank[ , var]
      current_ds_var_ranks <- current_ds_var[order(current_ds_var)]
      for (rank in current_ds_var_ranks) {
        if (rank != 0) {
          current_tmp_var_ind <- which(ds_rank[ , var] == rank)
          ## check if this tmp peak-group is not assigned yet
          ## if this tmp peakgroup is already assigned, assign NA for the pair
          if (current_tmp_var_ind %in% tmp_not_assigned) {
            ## if still free, check if this is the highest rank among remaining ones
            current_tmp_var <- tmp_rank[current_tmp_var_ind, ]
            ## are higher ranks for this tmp var not assigned yet? 
            ## order matches and check every match
            current_tmp_ds_rank <- current_tmp_var[var]
            higher_ranks <- which(current_tmp_var < current_tmp_ds_rank & current_tmp_var != 0)
            higher_ranks <- higher_ranks[order(current_tmp_var[higher_ranks])]
            ## if any of the higher ranking ds are still un-assigned, leave this tmp ds un-assigned now
            if (length(higher_ranks) > 0) {
              if (any(higher_ranks %in% ds_not_assigned)) {
                next
              } else {
                assigned[current_tmp_var_ind, var] <- TRUE
                tmp_not_assigned <- tmp_not_assigned[-c(which(tmp_not_assigned == current_tmp_var_ind))]
                ## finish for this ds peakgroup
                assigned[which(assigned[, var] == FALSE), var] <- NA
                break
              }
            } else {
              ## if this is the highest match for this tmp var
              assigned[current_tmp_var_ind, var] <- TRUE
              tmp_not_assigned <- tmp_not_assigned[-c(which(tmp_not_assigned == current_tmp_var_ind))]
              ## finish for this ds peakgroup
              assigned[which(assigned[, var] == FALSE), var] <- NA
              break
            }
          } else {
            assigned[current_tmp_var_ind, var] <- NA
          }
        }
      }
    }
  }
  return(assigned)
}

# rankCOS ---------------------------------------------------------------------------------------------------------
#' @title Rank cosines, assigning 1 to the highest cosine and 0s to cosine of 0.
#'
#' @param x \code{matrix} with cosine values for a single peak-group of interest and all peak-groups in table being matched to.
#'
#' @return Function returns \code{numeric} vector with ranks for each peak-group.
#' Of the same lenght as original x \code{matrix}.
#' 
rankCOS <- function(x) {
  cos_0 <- length(which(x == 0))
  cos_pos <- length(x) - cos_0
  if (cos_pos > 0) {
    cos_ranks <- rep(0, length(x))
    cos_ranks[order(x, decreasing = T)] <- c(
      seq(from = 1, to = cos_pos, by = 1),
      rep(0, cos_0)
    )
  } else {
    cos_ranks <- rep(0, cos_0)
  }
  return(cos_ranks)
}