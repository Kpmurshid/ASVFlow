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

    # PCoA with correction check
    pcoa_bray <- pcoa(dist_bray)
    correction_bray <- "none"
    if (any(pcoa_bray\$values\$Eigenvalues < 0)) {
        pcoa_bray <- pcoa(dist_bray, correction="cailliez")
        correction_bray <- "cailliez"
    }

    # Check for all-zero Jaccard distance (identical presence/absence profiles)
    jaccard_skip <- FALSE
    if (all(as.matrix(dist_jaccard) == 0)) {
        cat("WARNING: All Jaccard distances are zero (identical presence/absence)\\n")
        cat("         Skipping Jaccard PCoA - no variation to ordinate\\n")
        jaccard_skip <- TRUE
        correction_jaccard <- "skipped"
    } else {
        pcoa_jaccard <- pcoa(dist_jaccard)
        correction_jaccard <- "none"
        if (any(pcoa_jaccard\$values\$Eigenvalues < 0)) {
            pcoa_jaccard <- pcoa(dist_jaccard, correction="cailliez")
            correction_jaccard <- "cailliez"
        }
    }

    variance_bray <- pcoa_bray\$values\$Relative_eig * 100
    
    if (!jaccard_skip) {
        variance_jaccard <- pcoa_jaccard\$values\$Relative_eig * 100
    } else {
        variance_jaccard <- numeric(0)
    }

    # Get metadata
    has_group <- FALSE
    if (!is.null(tryCatch(sample_data(physeq), error=function(e) NULL))) {
        sample_data_df <- as(sample_data(physeq), "data.frame")
        sample_data_df <- sample_data_df[nonzero_samples, , drop=FALSE]
        if ("group" %in% colnames(sample_data_df)) has_group <- TRUE
    }

    # Create output dataframes
    n_axes <- min(3, ncol(pcoa_bray\$vectors))
    
    pcoa_bray_df <- data.frame(
        sample_id = rownames(otu_nonzero),
        pcoa_bray\$vectors[, 1:n_axes, drop=FALSE]
    )
    colnames(pcoa_bray_df) <- c("sample_id", paste0("PC", 1:n_axes))
    
    if (!jaccard_skip) {
        pcoa_jaccard_df <- data.frame(
            sample_id = rownames(otu_nonzero),
            pcoa_jaccard\$vectors[, 1:n_axes, drop=FALSE]
        )
        colnames(pcoa_jaccard_df) <- c("sample_id", paste0("PC", 1:n_axes))
    } else {
        # Create placeholder with NA values
        pcoa_jaccard_df <- data.frame(
            sample_id = rownames(otu_nonzero),
            PC1 = rep(NA_real_, nrow(otu_nonzero))
        )
        if (n_axes >= 2) pcoa_jaccard_df\$PC2 <- NA_real_
        if (n_axes >= 3) pcoa_jaccard_df\$PC3 <- NA_real_
    }

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
    for (i in 1:min(10, length(variance_bray))) {
        stats_list[[length(stats_list) + 1]] <- data.frame(
            metric = "Bray-Curtis", PC = i, variance_explained = variance_bray[i]
        )
    }
    if (!jaccard_skip) {
        for (i in 1:min(10, length(variance_jaccard))) {
            stats_list[[length(stats_list) + 1]] <- data.frame(
                metric = "Jaccard", PC = i, variance_explained = variance_jaccard[i]
            )
        }
    }
    stats_df <- do.call(rbind, stats_list)
    write.table(stats_df, "beta_diversity_stats.tsv", sep="\\t", quote=FALSE, row.names=FALSE)

    # Generate plots
    if (nrow(otu_nonzero) >= 2 && n_axes >= 2) {
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
        if (!jaccard_skip) {
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
    cat("  PC1:", round(variance_bray[1], 2), "%\\n")
    cat("\\nJaccard: presence/absence\\n")
    cat("  Correction:", correction_jaccard, "\\n")
    if (!jaccard_skip) {
        cat("  PC1:", round(variance_jaccard[1], 2), "%\\n")
    } else {
        cat("  PC1: N/A (all distances zero - identical presence/absence)\\n")
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
