#!/usr/bin/env Rscript
suppressMessages(library(dplyr))

#####################
## FUNCTIONS
#####################

load_file <- function(file_path, cluster_sim_out = NULL, sim_method = 'lin'){ 
	# sim_matrix <- read.table(file = file.path(file_path), sep = "\t", stringsAsFactors = FALSE, header = FALSE)
	file_name <- file.path(file_path,paste0('similarity_matrix_',sim_method,'.npy'))
	sim_matrix <- RcppCNPy::npyLoad(file_name)
	file_name <- file.path(file_path,paste0('similarity_matrix_',sim_method,'.lst'))
	if(file.exists(file_name)){ # squared matrix

		axis_labels <- read.table(file_name, header=FALSE, stringsAsFactors=FALSE, sep="\t")
	 	colnames(sim_matrix) <- axis_labels$V1
	 	rownames(sim_matrix) <- axis_labels$V1
	 	diag(sim_matrix) <- NA
		file_name <- paste0(sim_method,'_clusters.txt')
		split_mode = "byboth"
		
	}else{ # rectangular matrix
		axis_labels_x <- read.table(file.path(file_path, paste0('similarity_matrix_',sim_method,'_x.lst')), header=FALSE, stringsAsFactors=FALSE, sep="\t")
		axis_labels_y <- read.table(file.path(file_path, paste0('similarity_matrix_',sim_method,'_y.lst')), header=FALSE, stringsAsFactors=FALSE, sep="\t")
	 	colnames(sim_matrix) <- axis_labels_x$V1
	 	rownames(sim_matrix) <- axis_labels_y$V1
		file_name <- paste0(sim_method,'_clusters_rows.txt')
		split_mode = "byrows"
	}
	
 	groups <- read.table(file.path(file_path, file_name), header=FALSE, sep="\t")
 	groups_vec <- groups[,2]
	names(groups_vec) <- groups[,1]
 	sim_within_groups <- calc_sim_within_groups(sim_matrix, groups_vec, split_mode = split_mode)
 	if (!is.null(cluster_sim_out))
 	write.table(sim_within_groups, cluster_sim_out, quote=FALSE, row.names=TRUE, sep="\t", col.names = FALSE)
	sim_matrix <- sim_matrix %>% as.data.frame %>% tibble::rownames_to_column() %>% 
	    tidyr::pivot_longer(-rowname) %>% dplyr::filter(rowname != name)
	colnames(sim_matrix) <- c("pat_c", "pat_r", "Similarity")

	tagged_data <- rbind(
		data.frame(Similarity = sim_matrix$Similarity, sim_type = "All_patients_pairs"),
		data.frame(Similarity = sim_within_groups, sim_type = "Clustered_patients"))
	return(tagged_data)
}


get_group_submatrix_mean <- function(group, matrix_transf, groups=groups, split_mode = "byboth") {
	submatrix <- matrix_transf
	if (split_mode %in% c("byboth", "bycols")){
		submatrix <- submatrix[,names(groups)[groups %in% group]]
	}

	if (split_mode %in% c("byboth", "byrows")){
		submatrix <- submatrix[names(groups)[groups %in% group],]
	}
  mean(submatrix, na.rm=TRUE)
}

calc_sim_within_groups <- function(matrix_transf, groups, split_mode = "byboth") {
	unique_groups <- unique(groups)
	group_mean_sim <- sapply(unique_groups, get_group_submatrix_mean, matrix_transf=matrix_transf, groups=groups, split_mode = split_mode)
	names(group_mean_sim) <- unique_groups
	group_mean_sim
}

#####################
## OPTPARSE
#####################

option_list <- list(
  optparse::make_option(c("-i", "--input_paths"), type="character", default=NULL,
    help="Path to Npy and names"),
  optparse::make_option(c("-m", "--sim_method"), type="character", default='lin',
    help="Similarity method"),
  optparse::make_option(c("-o", "--output_file"), type="character", default=NULL,
    help="Output graph file name"),
  optparse::make_option(c("-t", "--tags"), type="character", default=NULL,
    help="Comma separate tags in the same order than files")
)
opt <- optparse::parse_args(optparse::OptionParser(option_list=option_list))

#####################
## MAIN
#####################

all_files <- unlist(strsplit(opt$input_paths, ","))
tags <- seq(length(all_files))
if (!is.null(opt$tags)){
	tags <- unlist(strsplit(opt$tags, ","))
}

similarity_dist <- list()
for (file_i in seq(length(all_files))) {
	similarity_dist[[tags[file_i]]] <- load_file(all_files[file_i], cluster_sim_out = paste0(opt$output_file,"_", tags[file_i],"_cluster_sim"), sim_method = opt$sim_method)
}
similarity_dist[["enod"]] <- NULL
for (tag in names(similarity_dist)){
	print(tag)
	sim_df <- similarity_dist[[tag]]
	sim_list <- split(sim_df, sim_df$sim_type)
	for (sim_type in names(sim_list)){
		print(sim_type)
		print(summary(sim_list[[sim_type]]$Similarity))
	}
	invisible(gc())
}

similarity_dist <- data.table::rbindlist(similarity_dist, use.names=TRUE, idcol= "Cohort")

pp <- ggplot2::ggplot(similarity_dist, ggplot2::aes(x = Cohort, y = Similarity, fill = sim_type)) + 
	ggplot2::geom_boxplot(width=0.5) +
	ggplot2::theme(axis.text = ggplot2::element_text(size =14), 
				   axis.title = ggplot2::element_text(size=18, face="bold"),
				   legend.position = "top",
				   legend.title = ggplot2::element_text(size = 14),
  					legend.text = ggplot2::element_text(size = 14)) +
	ggplot2::labs(fill = paste0(opt$sim_method, " similarity"))

ggplot2::ggsave(filename = paste0(opt$output_file,".png"),pp,width = 20, height = 18, dpi = 200, units = "cm", device='png')
