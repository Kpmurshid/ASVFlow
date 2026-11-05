nextflow.enable.dsl = 2

process ALPHA_DIVERSITY {

    tag { "alpha_diversity" }

    publishDir "${params.outdir}/community", mode: 'copy'

    input:
        path(phyloseq_rds)

    output:
        path("alpha_diversity.tsv"), emit: alpha_div
        path("alpha_diversity.pdf"), emit: alpha_plot, optional: true
        path("alpha_diversity_stats.tsv"), emit: alpha_stats, optional: true
        path("alpha_diversity_summary.txt"), emit: alpha_summary

    script:
    """
    #!/usr/bin/env Rscript
    library(phyloseq)
    library(ggplot2)

    cat("=== ALPHA_DIVERSITY ===\\n\\n")

    physeq <- readRDS("${phyloseq_rds}")
    cat("Loaded phyloseq:", nsamples(physeq), "samples\\n")

    # Calculate alpha diversity metrics
    alpha_div <- estimate_richness(physeq, measures=c("Observed", "Chao1", "Shannon", "Simpson"))

    # Handle zero-read samples: set metrics to NA (not 0)
    otu_matrix <- as(otu_table(physeq), "matrix")
    if (taxa_are_rows(physeq)) otu_matrix <- t(otu_matrix)
    
    zero_samples <- rowSums(otu_matrix) == 0
    if (any(zero_samples)) {
        cat("Zero-read samples detected:", sum(zero_samples), "\\n")
        alpha_div[zero_samples, ] <- NA
    }

    # Add status column
    alpha_div\$status <- "ok"
    alpha_div\$status[zero_samples] <- "zero_reads"
    
    # Check for Chao1 estimation failures (insufficient data)
    chao1_failed <- is.na(alpha_div\$Chao1) & !zero_samples
    if (any(chao1_failed)) {
        alpha_div\$status[chao1_failed] <- "insufficient_data"
        cat("Chao1 estimation failed:", sum(chao1_failed), "samples\\n")
    }

    # Add sample_id and metadata if available
    alpha_div\$sample_id <- rownames(alpha_div)
    
    if (!is.null(tryCatch(sample_data(physeq), error=function(e) NULL))) {
        sample_data_df <- as(sample_data(physeq), "data.frame")
        if ("group" %in% colnames(sample_data_df)) {
            alpha_div\$group <- sample_data_df\$group[match(alpha_div\$sample_id, rownames(sample_data_df))]
        }
    }

    # Reorder columns
    col_order <- c("sample_id", "Observed", "Chao1", "Shannon", "Simpson", "status")
    if ("group" %in% colnames(alpha_div)) col_order <- c(col_order, "group")
    alpha_div <- alpha_div[, col_order]

    write.table(alpha_div, "alpha_diversity.tsv", sep="\\t", quote=FALSE, row.names=FALSE)

    # Exclude NA samples from plots and stats
    alpha_valid <- alpha_div[alpha_div\$status == "ok", ]

    # Generate plots if we have valid samples
    if (nrow(alpha_valid) > 0) {
        pdf("alpha_diversity.pdf", width=10, height=8)
        
        metrics <- c("Observed", "Chao1", "Shannon", "Simpson")
        for (metric in metrics) {
            if ("group" %in% colnames(alpha_valid) && length(unique(alpha_valid\$group)) > 1) {
                p <- ggplot(alpha_valid, aes_string(x="group", y=metric, fill="group")) +
                    geom_boxplot() +
                    geom_jitter(width=0.2, alpha=0.5) +
                    theme_bw() +
                    ggtitle(paste("Alpha Diversity:", metric)) +
                    theme(axis.text.x=element_text(angle=45, hjust=1))
                print(p)
            } else {
                p <- ggplot(alpha_valid, aes_string(x="'All'", y=metric)) +
                    geom_boxplot(fill="lightblue") +
                    geom_jitter(width=0.1, alpha=0.5) +
                    theme_bw() +
                    ggtitle(paste("Alpha Diversity:", metric)) +
                    xlab("")
                print(p)
            }
        }
        
        dev.off()
    }

    # Calculate summary statistics by group
    if (nrow(alpha_valid) > 0 && "group" %in% colnames(alpha_valid)) {
        stats_list <- list()
        for (grp in unique(alpha_valid\$group)) {
            grp_data <- alpha_valid[alpha_valid\$group == grp, ]
            for (metric in c("Observed", "Chao1", "Shannon", "Simpson")) {
                vals <- grp_data[[metric]]
                vals <- vals[!is.na(vals)]
                if (length(vals) > 0) {
                    stats_list[[length(stats_list) + 1]] <- data.frame(
                        group = grp,
                        metric = metric,
                        n = length(vals),
                        mean = mean(vals),
                        median = median(vals),
                        sd = sd(vals),
                        min = min(vals),
                        max = max(vals)
                    )
                }
            }
        }
        stats_df <- do.call(rbind, stats_list)
        write.table(stats_df, "alpha_diversity_stats.tsv", sep="\\t", quote=FALSE, row.names=FALSE)
    }

    # Write summary
    sink("alpha_diversity_summary.txt")
    cat("=== ALPHA_DIVERSITY Summary ===\\n\\n")
    cat("Total samples:", nrow(alpha_div), "\\n")
    cat("Valid samples:", sum(alpha_div\$status == "ok"), "\\n")
    cat("Zero-read samples:", sum(alpha_div\$status == "zero_reads"), "\\n")
    cat("Insufficient data:", sum(alpha_div\$status == "insufficient_data"), "\\n")
    if (sum(zero_samples) > 0) {
        cat("\\nZero-read sample IDs:\\n")
        cat("  ", paste(alpha_div\$sample_id[zero_samples], collapse=", "), "\\n")
    }
    cat("\\nMetrics calculated: Observed, Chao1, Shannon, Simpson\\n")
    cat("NA values indicate undefined metrics (not zero)\\n")
    sink()

    cat("\\n=== ALPHA_DIVERSITY complete ===\\n")
    """

    stub:
    """
    #!/usr/bin/env Rscript
    df <- data.frame(sample_id="TEST1", Observed=100, Chao1=120, Shannon=3.5, Simpson=0.95, status="ok")
    write.table(df, "alpha_diversity.tsv", sep="\\t", quote=FALSE, row.names=FALSE)
    writeLines("=== ALPHA_DIVERSITY Summary (stub) ===", "alpha_diversity_summary.txt")
    """
}
