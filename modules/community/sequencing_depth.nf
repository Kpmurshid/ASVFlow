nextflow.enable.dsl = 2

process SEQUENCING_DEPTH {

    tag { "sequencing_depth" }

    publishDir "${params.outdir}/community", mode: 'copy'

    input:
        path(phyloseq_rds)

    output:
        path("sequencing_depth.tsv"), emit: depth
        path("sequencing_depth_stats.tsv"), emit: depth_stats
        path("rarefaction_curves.pdf"), emit: rare_plot, optional: true
        path("rarefaction_curves.tsv"), emit: rare_data, optional: true
        path("rarefaction_summary.txt"), emit: rare_summary

    script:
    """
    #!/usr/bin/env Rscript
    library(phyloseq)
    library(vegan)
    library(ggplot2)

    cat("=== SEQUENCING_DEPTH ===\\n\\n")

    physeq <- readRDS("${phyloseq_rds}")
    otu_matrix <- as(otu_table(physeq), "matrix")
    if (taxa_are_rows(physeq)) otu_matrix <- t(otu_matrix)

    # Get read depths
    depths <- rowSums(otu_matrix)

    # Get metadata if available
    has_group <- FALSE
    if (!is.null(tryCatch(sample_data(physeq), error=function(e) NULL))) {
        sample_data_df <- as(sample_data(physeq), "data.frame")
        if ("group" %in% colnames(sample_data_df)) has_group <- TRUE
    }

    # Create depth dataframe
    depth_df <- data.frame(sample_id=names(depths), reads=depths)
    if (has_group) depth_df\$group <- sample_data_df\$group

    write.table(depth_df, "sequencing_depth.tsv", sep="\\t", quote=FALSE, row.names=FALSE)

    # Calculate statistics
    stats_df <- data.frame(
        statistic=c("min", "max", "mean", "median", "sd", "cv"),
        value=c(min(depths), max(depths), mean(depths), median(depths), 
                sd(depths), 100 * sd(depths) / mean(depths))
    )
    write.table(stats_df, "sequencing_depth_stats.tsv", sep="\\t", quote=FALSE, row.names=FALSE)

    # Rarefaction curves (exclude zero-read samples)
    nonzero_samples <- depths > 0
    n_excluded <- sum(!nonzero_samples)

    if (sum(nonzero_samples) > 0) {
        otu_nonzero <- otu_matrix[nonzero_samples, , drop=FALSE]
        
        rare_step <- max(1, floor(max(rowSums(otu_nonzero)) / 100))
        rare_curves <- rarecurve(otu_nonzero, step=rare_step, label=FALSE)

        # Extract data for TSV
        # names(curve) are the depths; attr(curve,"Subsample") is the actual sample depth
        rare_data_list <- list()
        for (i in seq_along(rare_curves)) {
            curve <- rare_curves[[i]]
            # Depths are stored as names (may be NA if only one point)
            depths_i <- suppressWarnings(as.numeric(names(curve)))
            if (any(is.na(depths_i)) || length(depths_i) == 0) {
                # Fallback: use the Subsample attribute (the actual sample depth)
                depths_i <- attr(curve, "Subsample")
            }
            # sample_id from list names or row names
            sid <- if (!is.null(names(rare_curves)) && !is.na(names(rare_curves)[i])) {
                names(rare_curves)[i]
            } else {
                rownames(otu_nonzero)[i]
            }
            for (j in seq_along(depths_i)) {
                if (!is.na(depths_i[j])) {
                    rare_data_list[[length(rare_data_list) + 1]] <- data.frame(
                        sample_id = sid,
                        depth = depths_i[j],
                        asvs = as.numeric(curve[j])
                    )
                }
            }
        }
        
        if (length(rare_data_list) > 0) {
            rare_data_df <- do.call(rbind, rare_data_list)
            write.table(rare_data_df, "rarefaction_curves.tsv", sep="\\t", quote=FALSE, row.names=FALSE)

            # Plot rarefaction curves
            pdf("rarefaction_curves.pdf", width=10, height=6)
            plot(0, type="n", xlim=c(0, max(rare_data_df\$depth)), ylim=c(0, max(rare_data_df\$asvs)),
                 xlab="Sequencing Depth", ylab="Number of ASVs", main="Rarefaction Curves")
            for (samp in unique(rare_data_df\$sample_id)) {
                samp_data <- rare_data_df[rare_data_df\$sample_id == samp, ]
                lines(samp_data\$depth, samp_data\$asvs, col=rgb(0, 0, 0, 0.3))
            }
            dev.off()
        } else {
            cat("WARNING: rarefaction curve data could not be extracted\\n")
        }
    }

    # Write summary
    sink("rarefaction_summary.txt")
    cat("=== SEQUENCING_DEPTH Summary ===\\n\\n")
    cat("Total samples:", length(depths), "\\n")
    cat("Min depth:", min(depths), "\\n")
    cat("Max depth:", max(depths), "\\n")
    cat("Mean depth:", round(mean(depths), 1), "\\n")
    cat("Median depth:", median(depths), "\\n")
    cat("SD:", round(sd(depths), 1), "\\n")
    cat("CV:", round(100 * sd(depths) / mean(depths), 1), "%\\n")
    cat("\\nRarefaction curves:\\n")
    cat("  Samples included:", sum(nonzero_samples), "\\n")
    cat("  Samples excluded (zero reads):", n_excluded, "\\n")
    if (n_excluded > 0) {
        cat("    IDs:", paste(names(depths)[!nonzero_samples], collapse=", "), "\\n")
    }
    sink()

    cat("\\n=== SEQUENCING_DEPTH complete ===\\n")
    """

    stub:
    """
    #!/usr/bin/env Rscript
    depth_df <- data.frame(sample_id="TEST1", reads=1000)
    write.table(depth_df, "sequencing_depth.tsv", sep="\\t", quote=FALSE, row.names=FALSE)
    stats_df <- data.frame(statistic=c("min", "max", "mean"), value=c(1000, 1000, 1000))
    write.table(stats_df, "sequencing_depth_stats.tsv", sep="\\t", quote=FALSE, row.names=FALSE)
    writeLines("=== SEQUENCING_DEPTH Summary (stub) ===", "rarefaction_summary.txt")
    """
}
