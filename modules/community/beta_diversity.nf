nextflow.enable.dsl = 2

process BETA_DIVERSITY {

    tag { "beta_diversity" }

    publishDir "${params.outdir}/community", mode: 'copy'

    input:
        path(phyloseq_rds)

    output:
        path("beta_diversity_bray_pcoa.tsv"), emit: beta_bray
        path("beta_diversity_jaccard_pcoa.tsv"), emit: beta_jaccard
        path("beta_diversity_bray_pcoa.pdf"), emit: beta_bray_plot, optional: true
        path("beta_diversity_jaccard_pcoa.pdf"), emit: beta_jaccard_plot, optional: true
        path("beta_diversity_stats.tsv"), emit: beta_stats
        path("beta_diversity_summary.txt"), emit: beta_summary
        path("beta_diversity_distances_bray.rds"), emit: dist_bray
        path("beta_diversity_distances_jaccard.rds"), emit: dist_jaccard

    script:
    """
    #!/usr/bin/env Rscript
    library(phyloseq)
    library(vegan)
    library(ape)
    library(ggplot2)

    cat("=== BETA_DIVERSITY ===\\n\\n")

    physeq <- readRDS("${phyloseq_rds}")
    otu_matrix <- as(otu_table(physeq), "matrix")
    if (taxa_are_rows(physeq)) otu_matrix <- t(otu_matrix)

    # Exclude zero-read samples
    nonzero_samples <- rowSums(otu_matrix) > 0
    n_excluded <- sum(!nonzero_samples)
    
    if (n_excluded > 0) {
        cat("Excluding", n_excluded, "zero-read samples\\n")
    }
    
    otu_nonzero <- otu_matrix[nonzero_samples, , drop=FALSE]
    
    if (nrow(otu_nonzero) < 2) {
        stop("Beta diversity requires at least 2 samples with non-zero reads")
    }

    if (nrow(otu_nonzero) == 2) {
        cat("WARNING: Only 2 samples - PCoA produces 1 axis\\n")
    }

    # Bray-Curtis on relative abundances
    otu_rel <- sweep(otu_nonzero, 1, rowSums(otu_nonzero), "/")
    dist_bray <- vegdist(otu_rel, method="bray")
    
    # Jaccard on presence/absence
    dist_jaccard <- vegdist(otu_nonzero, method="jaccard", binary=TRUE)

    # Save distance matrices
    saveRDS(dist_bray, "beta_diversity_distances_bray.rds")
    saveRDS(dist_jaccard, "beta_diversity_distances_jaccard.rds")

    # PCoA can have no axes when all pairwise distances are zero. Keep the
    # distance matrices above, and report coordinates/variance as unavailable.
    has_distance_variation <- function(distance) {
        values <- as.vector(as.matrix(distance))
        any(is.finite(values) & values > sqrt(.Machine\$double.eps))
    }
    run_pcoa <- function(distance, metric) {
        if (!has_distance_variation(distance)) {
            cat("WARNING:", metric, "distances have no variation; ordination unavailable\\n")
            return(list(result=NULL, correction="unavailable", variance=numeric(0)))
        }
        result <- pcoa(distance)
        correction <- "none"
        if (any(result\$values\$Eigenvalues < 0, na.rm=TRUE)) {
            result <- pcoa(distance, correction="cailliez")
            correction <- "cailliez"
        }
        # ape omits Relative_eig after Cailliez correction; Rel_corr_eig is
        # the corrected eigenvalue proportion in that case.
        proportions <- result\$values\$Relative_eig
        if (is.null(proportions) || length(proportions) == 0) {
            proportions <- result\$values\$Rel_corr_eig
        }
        if (is.null(proportions)) proportions <- numeric(0)
        list(result=result, correction=correction, variance=proportions * 100)
    }

    bray_ordination <- run_pcoa(dist_bray, "Bray-Curtis")
    jaccard_ordination <- run_pcoa(dist_jaccard, "Jaccard")
    pcoa_bray <- bray_ordination\$result
    pcoa_jaccard <- jaccard_ordination\$result
    correction_bray <- bray_ordination\$correction
    correction_jaccard <- jaccard_ordination\$correction
    variance_bray <- bray_ordination\$variance
    variance_jaccard <- jaccard_ordination\$variance
    bray_skip <- is.null(pcoa_bray) || length(variance_bray) == 0 ||
        is.null(pcoa_bray\$vectors) || ncol(pcoa_bray\$vectors) == 0
    jaccard_skip <- is.null(pcoa_jaccard) || length(variance_jaccard) == 0 ||
        is.null(pcoa_jaccard\$vectors) || ncol(pcoa_jaccard\$vectors) == 0

    # Get metadata
    has_group <- FALSE
    if (!is.null(tryCatch(sample_data(physeq), error=function(e) NULL))) {
        sample_data_df <- as(sample_data(physeq), "data.frame")
        sample_data_df <- sample_data_df[nonzero_samples, , drop=FALSE]
        if ("group" %in% colnames(sample_data_df)) has_group <- TRUE
    }

    # Create output dataframes
    make_pcoa_table <- function(ordination, unavailable, sample_ids) {
        if (unavailable) {
            return(data.frame(sample_id=sample_ids, PC1=rep(NA_real_, length(sample_ids))))
        }
        n_axes <- min(3, ncol(ordination\$vectors))
        result <- data.frame(sample_id=sample_ids,
                             ordination\$vectors[, seq_len(n_axes), drop=FALSE])
        colnames(result) <- c("sample_id", paste0("PC", seq_len(n_axes)))
        result
    }
    pcoa_bray_df <- make_pcoa_table(pcoa_bray, bray_skip, rownames(otu_nonzero))
    pcoa_jaccard_df <- make_pcoa_table(pcoa_jaccard, jaccard_skip, rownames(otu_nonzero))

    if (has_group) {
        pcoa_bray_df\$group <- sample_data_df\$group
        if (!jaccard_skip) {
            pcoa_jaccard_df\$group <- sample_data_df\$group
        }
    }

    write.table(pcoa_bray_df, "beta_diversity_bray_pcoa.tsv", sep="\\t", quote=FALSE, row.names=FALSE)
    write.table(pcoa_jaccard_df, "beta_diversity_jaccard_pcoa.tsv", sep="\\t", quote=FALSE, row.names=FALSE)

    # Stats table
    stats_list <- list()
    n_stats_bray <- if (bray_skip) 0 else min(10, length(variance_bray), ncol(pcoa_bray\$vectors))
    for (i in seq_len(n_stats_bray)) {
        stats_list[[length(stats_list) + 1]] <- data.frame(
            metric = "Bray-Curtis", PC = i, variance_explained = variance_bray[i]
        )
    }
    if (!jaccard_skip) {
        n_stats_jaccard <- min(10, length(variance_jaccard), ncol(pcoa_jaccard\$vectors))
        for (i in seq_len(n_stats_jaccard)) {
            stats_list[[length(stats_list) + 1]] <- data.frame(
                metric = "Jaccard", PC = i, variance_explained = variance_jaccard[i]
            )
        }
    }
    stats_df <- if (length(stats_list)) do.call(rbind, stats_list) else
        data.frame(metric=character(), PC=integer(), variance_explained=numeric())
    write.table(stats_df, "beta_diversity_stats.tsv", sep="\\t", quote=FALSE, row.names=FALSE)

    # Generate plots
    n_axes_bray <- if (bray_skip) 0 else min(3, ncol(pcoa_bray\$vectors))
    n_axes_jaccard <- if (jaccard_skip) 0 else min(3, ncol(pcoa_jaccard\$vectors))
    if (nrow(otu_nonzero) >= 2 && n_axes_bray >= 2) {
        pdf("beta_diversity_bray_pcoa.pdf", width=8, height=6)
        if (has_group) {
            p <- ggplot(pcoa_bray_df, aes(x=PC1, y=PC2, color=group)) +
                geom_point(size=3) +
                theme_bw() +
                xlab(paste0("PC1 (", round(variance_bray[1], 1), "%)")) +
                ylab(paste0("PC2 (", round(variance_bray[2], 1), "%)")) +
                ggtitle("PCoA - Bray-Curtis")
        } else {
            p <- ggplot(pcoa_bray_df, aes(x=PC1, y=PC2)) +
                geom_point(size=3, color="steelblue") +
                theme_bw() +
                xlab(paste0("PC1 (", round(variance_bray[1], 1), "%)")) +
                ylab(paste0("PC2 (", round(variance_bray[2], 1), "%)")) +
                ggtitle("PCoA - Bray-Curtis")
        }
        print(p)
        dev.off()

        # Only plot Jaccard if not skipped
        if (n_axes_jaccard >= 2) {
            pdf("beta_diversity_jaccard_pcoa.pdf", width=8, height=6)
            if (has_group) {
                p <- ggplot(pcoa_jaccard_df, aes(x=PC1, y=PC2, color=group)) +
                    geom_point(size=3) +
                    theme_bw() +
                    xlab(paste0("PC1 (", round(variance_jaccard[1], 1), "%)")) +
                    ylab(paste0("PC2 (", round(variance_jaccard[2], 1), "%)")) +
                    ggtitle("PCoA - Jaccard")
            } else {
                p <- ggplot(pcoa_jaccard_df, aes(x=PC1, y=PC2)) +
                    geom_point(size=3, color="steelblue") +
                    theme_bw() +
                    xlab(paste0("PC1 (", round(variance_jaccard[1], 1), "%)")) +
                    ylab(paste0("PC2 (", round(variance_jaccard[2], 1), "%)")) +
                    ggtitle("PCoA - Jaccard")
            }
            print(p)
            dev.off()
        }
    }

    # Write summary
    sink("beta_diversity_summary.txt")
    cat("=== BETA_DIVERSITY Summary ===\\n\\n")
    cat("Samples analyzed:", nrow(otu_nonzero), "\\n")
    cat("Samples excluded:", n_excluded, "\\n")
    cat("\\nBray-Curtis: per-sample relative abundance\\n")
    cat("  Correction:", correction_bray, "\\n")
    if (!bray_skip) {
        cat("  PC1:", round(variance_bray[1], 2), "%\\n")
    } else {
        cat("  PC1: N/A (no distance variation or positive axes)\\n")
    }
    cat("\\nJaccard: presence/absence\\n")
    cat("  Correction:", correction_jaccard, "\\n")
    if (!jaccard_skip) {
        cat("  PC1:", round(variance_jaccard[1], 2), "%\\n")
    } else {
        cat("  PC1: N/A (no distance variation or positive axes)\\n")
    }
    sink()

    cat("\\n=== BETA_DIVERSITY complete ===\\n")
    """

    stub:
    """
    #!/usr/bin/env Rscript
    df <- data.frame(sample_id=c("TEST1", "TEST2"), PC1=c(0.1, -0.1), PC2=c(0.05, -0.05))
    write.table(df, "beta_diversity_bray_pcoa.tsv", sep="\\t", quote=FALSE, row.names=FALSE)
    write.table(df, "beta_diversity_jaccard_pcoa.tsv", sep="\\t", quote=FALSE, row.names=FALSE)
    stats <- data.frame(metric="Bray-Curtis", PC=1, variance_explained=50.0)
    write.table(stats, "beta_diversity_stats.tsv", sep="\\t", quote=FALSE, row.names=FALSE)
    writeLines("=== BETA_DIVERSITY Summary (stub) ===", "beta_diversity_summary.txt")
    dist <- as.dist(matrix(c(0, 0.5, 0.5, 0), nrow=2))
    saveRDS(dist, "beta_diversity_distances_bray.rds")
    saveRDS(dist, "beta_diversity_distances_jaccard.rds")
    """
}
