#    Copyright (C) 2017 Allen Institute
#
#    This program is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 2 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License along
#    with this program; if not, write to the Free Software Foundation, Inc.,
#    51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

#------------------------------------------------------------------------------#
#----------------------------FUNCTION DEFINITIONS------------------------------#
#------------------------------------------------------------------------------#

#' Tidy the human brain atlas data. The data is available for download here:
#' http://human.brain-map.org/static/download. The data comes as 6 zip files,
#' one for each donor. To use this script, put all 6 directories in a base
#' directory like such
#' 
#' dirHBA
#'      |_ Donor1
#'      |_ Donor2
#'      |_ ...
#' 
#' The `path` is then the path to dirHBA.
#' 
#' 
#' 
#' @param path File path to the base directory as depicted above
#' @return Create a new directory in the current working directory `resultFrameCollapse` This directoy contains the tidy version of each donors brain
#' @examples
#' dirHBA <- "/my/very/cool/file/system/dirHBA"
#' # aggregate to max and don't collapse
#' formatterHBA(dirHBA)
formatterFET <- function(path){
    
    # create a list of files to iterate through
    pathFET <- as.list(list.dirs(path, recursive = FALSE))
    
    # format each file and save to a csv labeled 1-n for reading later
    i <- 1
    for (brain in pathFET) {
        print("Begin Formatting")
        print(brain)
        resultFrame <- .formatOneFET(brain)
        print("Saving results")

        # write to csv
        readr::write_csv(resultFrame,
                         paste("./resultFrameFET/resultFrame",
                               as.character(i), ".csv", sep=""))

        print(paste("Done saving", as.character(i)))
        i <- i + 1
    }
}

#------------------------------HELPER FUNCTIONS--------------------------------#

.createFETMatrix <- function(mpath, ppath, apath){

    # load the microexpression data...suppress to hide parse info
    suppressMessages(MicroExp <- readr::read_csv(mpath, col_names = FALSE))
    suppressMessages(AnSamp <- readr::read_csv(apath))
    suppressMessages(Probes <- readr::read_csv(ppath)[c("probeset_id", "probeset_name", "gene_symbol")])

    # Change first column name for joining
    colnames(MicroExp)[1] <- "probeset_id"

    if (all(MicroExp$probeset_id == Probes$probeset_id)) {

        # this is to ensure that the order of the probe ids is the same in both
        # frames. Checking is O(n), while joining is O(n^2)
        rowProbeID <- Probes$probeset_name
        rowGeneGroup <- Probes$gene_symbol
        MicroExp <- MicroExp[c(-1)]

    } else {
        # in the event that they are ordered differently we need to join on the
        # identifier
        warning("probe_id variable from micro-array expression csv and probe csv do not have the same order\n\nThis implies gene order may have changed")
        MicroExp <- dplyr::inner_join(
            Probes, MicroExp, by="probeset_id")

        rowProbeID <- MicroExp$probeset_name
        rowGeneGroup <- MicroExp$gene_symbol
        MicroExp <- MicroExp[c(-1,-2,-3)]
    }

    colnames(MicroExp) <- AnSamp$structure_acronym
    MicroExp <- cbind(probe_name = rowProbeID,
                      gene = rowGeneGroup,
                      MicroExp)

    return(list(dat = MicroExp))
}

    
.formatOneFET <- function(folder){

    # extract the donor ID from the file string
    donorID <- gsub("lmd_matrix_", "",
               tail(strsplit(folder, '/')[[1]], n=1))

    # format the paths appropriately to read the csvs
    micro_path <- paste(folder,"expression_matrix.csv",sep="/")
    probe_path <- paste(folder, "rows_metadata.csv", sep="/")
    annot_path <- paste(folder, "columns_metadata.csv", sep="/")

    # format the dataframe correctly and retun for aggregating
    print("Begin reading in data")
    MicroExp <- .createFETMatrix(micro_path, probe_path, annot_path)
    print("Data loaded")
    gc() # reallocate free memory

    # create unique column ids...for melting later
    n_col <- ncol(MicroExp$dat) - 2
    n_pad <- nchar(as.character(n_col))
    id_pad <- stringr::str_pad(as.character(1:n_col), n_pad, pad="0")
    col_ids <- paste(colnames(MicroExp$dat)[c(-1,-2)], id_pad, sep="")
    colnames(MicroExp$dat)[c(-1,-2)] <- col_ids

    # collapse rows -- this is a time intensive step

    # format for use in WGCNA collapseRow
    MicroExp$group <- MicroExp$dat$gene
    MicroExp$id <- MicroExp$dat$probe_name
    MicroExp$struct <- colnames(MicroExp$dat)[c(-1,-2)]
    MicroExp$dat <- as.matrix(MicroExp$dat[c(-1,-2)])
    rownames(MicroExp$dat) <- MicroExp$id

    gc()  # this may make the machine return memory

    # collapse rows to get a single representative of each gene
    print("Collapsing Rows")
    MicroCollapse <- WGCNA::collapseRows(
        MicroExp$dat, rowGroup = MicroExp$group, rowID = MicroExp$id)
    print("Done collapsing")

    # reformat to a dataframe and create a gene variable before reshaping
    # this is to facilitate joining the gene on the selected probe
    resultFrame <- as.data.frame(MicroCollapse$datETcollapsed)
    resultFrame$gene <- rownames(resultFrame)
    rownames(resultFrame) <- c(1:nrow(resultFrame))
    resultFrame <- reshape2::melt(resultFrame, id.vars=c("gene"))

    # reformate the group2row matrix as a data frame and add names for join
    group2row <- unique(as.data.frame(MicroCollapse$group2row))
    colnames(group2row) <- c("gene", "probe_name")

    # inner join to match genes with probes
    resultFrame <- dplyr::inner_join(resultFrame, group2row, by="gene")
    resultFrame <- cbind(probe_name = resultFrame$probe_name, 
                         resultFrame[c(-4)])
    resultFrame <- cbind(donorID, resultFrame)
    resultFrame$gene <- factor(resultFrame$gene)

    # Finish final formatting details and return
    structs <- as.character(resultFrame$variable)
    resultFrame$variable <- factor(substr(structs, 1, nchar(structs) - n_pad))
    resultFrame <- resultFrame[-2]
    print(paste("dataframe dimensions:", dim(resultFrame)))
    print("Formatting complete")
    return(resultFrame)
}


#------------------------------------------------------------------------------#
#---------------------------------MAIN SCRIPT----------------------------------#
#------------------------------------------------------------------------------#

# This script is meant to reformat the data found on the allen institutes human
# brain atlas form into tidy (http://vita.had.co.nz/papers/tidy-data.html) data.
# It accomplishes this goal by first collapsing data on gene using collapseRows
# in the WGCNA package. Data is then transformed into long format so that each
# row is an ID and an observation.

# folder <- "C:/Users/cygwin/home/charlese/dir_FET/lmd_matrix_12566/"

# reset dirHBA to point to base directory
dirFET <- "C:/Users/cygwin/home/charlese/dir_FET"
formatterFET(dirFET)
