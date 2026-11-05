nextflow.enable.dsl = 2

process PERMANOVA {

    tag { "permanova" }

    publishDir "${params.outdir}/community", mode: 'copy'

    input:
        path(phyloseq_rds)
        path(dist_bray)
        path(dist_jaccard)

    output:
        path("permanova_bray.tsv"), emit: perm_bray, optional: true
        path("permanova_jaccard.tsv"), emit: perm_jaccard, optional: true
        path("betadisper_bray.tsv"), emit: disp_bray, optional: true
        path("betadisper_jaccard.tsv"), emit: disp_jaccard, optional: true
        path("permanova_summary.txt"), emit: perm_summary
        path("permanova_skipped.txt"), emit: perm_skipped, optional: true

    script:
    """
    #!/usr/bin/env Rscript
    library(phyloseq)
    library(vegan)

    cat("=== PERMANOVA ===\\n\\n")

    physeq <- readRDS("${phyloseq_rds}")
    
    # Check for metadata with group column
    if (is.null(tryCatch(sample_data(physeq), error=function(e) NULL))) {
        writeLines("No metadata provided", "permanova_skipped.txt")
        writeLines("=== PERMANOVA skipped: no metadata ===", "permanova_summary.txt")
        quit(save="no", status=0)
    }

    metadata <- as(sample_data(physeq), "data.frame")
    
    if (!"group" %in% colnames(metadata)) {
        writeLines("No group column in metadata", "permanova_skipped.txt")
        writeLines("=== PERMANOVA skipped: no group column ===", "permanova_summary.txt")
        quit(save="no", status=0)
    }

    # Load distance matrices
    dist_bray_full <- readRDS("${dist_bray}")
    dist_jaccard_full <- readRDS("${dist_jaccard}")

    # Complete cases: non-NA group, present in distance matrix
    complete_cases <- !is.na(metadata\$group) & rownames(metadata) %in% labels(dist_bray_full)
    
    if (sum(complete_cases) < 2) {
        writeLines("Insufficient samples for PERMANOVA", "permanova_skipped.txt")
        writeLines("=== PERMANOVA skipped: < 2 complete-case samples ===", "permanova_summary.txt")
        quit(save="no", status=0)
    }

    metadata_complete <- metadata[complete_cases, , drop=FALSE]
    
    # Check groups
    group_sizes <- table(metadata_complete\$group)
    if (length(group_sizes) < 2) {
        writeLines(paste("Only", length(group_sizes), "group"), "permanova_skipped.txt")
        writeLines("=== PERMANOVA skipped: < 2 groups ===", "permanova_summary.txt")
        quit(save="no", status=0)
    }

    cat("Complete cases:", nrow(metadata_complete), "\\n")
    cat("Groups:", paste(names(group_sizes), "=", group_sizes, collapse=", "), "\\n")

    # Subset distance matrices to complete cases
    sample_ids <- rownames(metadata_complete)
    dist_bray <- as.dist(as.matrix(dist_bray_full)[sample_ids, sample_ids])
    dist_jaccard <- as.dist(as.matrix(dist_jaccard_full)[sample_ids, sample_ids])

    # PERMANOVA
    set.seed(${params.permanova_seed})
    perm_bray <- adonis2(dist_bray ~ group, data=metadata_complete, permutations=${params.permanova_nperm})
    
    set.seed(${params.permanova_seed})
    perm_jaccard <- adonis2(dist_jaccard ~ group, data=metadata_complete, permutations=${params.permanova_nperm})

    write.table(as.data.frame(perm_bray), "permanova_bray.tsv", sep="\\t", quote=FALSE, col.names=NA)
    write.table(as.data.frame(perm_jaccard), "permanova_jaccard.tsv", sep="\\t", quote=FALSE, col.names=NA)

    # Dispersion test (only if all groups have n >= 2)
    if (all(group_sizes >= 2)) {
        disp_bray <- betadisper(dist_bray, metadata_complete\$group)
        set.seed(${params.permanova_seed})
        disp_test_bray <- permutest(disp_bray, permutations=${params.permanova_nperm})
        
        disp_jaccard <- betadisper(dist_jaccard, metadata_complete\$group)
        set.seed(${params.permanova_seed})
        disp_test_jaccard <- permutest(disp_jaccard, permutations=${params.permanova_nperm})

        disp_df_bray <- data.frame(
            metric="Bray-Curtis", 
            F_statistic=disp_test_bray\$tab\$F[1], 
            p_value=disp_test_bray\$tab[1, 6]
        )
        disp_df_jaccard <- data.frame(
            metric="Jaccard", 
            F_statistic=disp_test_jaccard\$tab\$F[1], 
            p_value=disp_test_jaccard\$tab[1, 6]
        )
        
        write.table(disp_df_bray, "betadisper_bray.tsv", sep="\\t", quote=FALSE, row.names=FALSE)
        write.table(disp_df_jaccard, "betadisper_jaccard.tsv", sep="\\t", quote=FALSE, row.names=FALSE)
    } else {
        cat("Dispersion test skipped: some groups have n < 2\\n")
    }

    # Summary
    sink("permanova_summary.txt")
    cat("=== PERMANOVA Summary ===\\n\\n")
    cat("Samples:", nrow(metadata_complete), "\\n")
    cat("Groups:", length(group_sizes), "\\n")
    for (g in names(group_sizes)) {
        cat("  ", g, ": ", group_sizes[g], "\\n", sep="")
    }
    cat("\\nBray-Curtis PERMANOVA:\\n")
    cat("  R2:", round(perm_bray\$R2[1], 4), "\\n")
    cat("  F:", round(perm_bray\$F[1], 3), "\\n")
    cat("  p-value:", perm_bray[1, 5], "\\n")
    cat("\\nJaccard PERMANOVA:\\n")
    cat("  R2:", round(perm_jaccard\$R2[1], 4), "\\n")
    cat("  F:", round(perm_jaccard\$F[1], 3), "\\n")
    cat("  p-value:", perm_jaccard[1, 5], "\\n")
    sink()

    cat("\\n=== PERMANOVA complete ===\\n")
    """

    stub:
    """
    #!/usr/bin/env Rscript
    perm <- data.frame(Df=c(1, 8), SumOfSqs=c(0.5, 2.0), R2=c(0.2, 0.8), F=c(2.0, NA), PrF=c(0.05, NA))
    write.table(perm, "permanova_bray.tsv", sep="\\t", quote=FALSE, col.names=NA)
    write.table(perm, "permanova_jaccard.tsv", sep="\\t", quote=FALSE, col.names=NA)
    writeLines("=== PERMANOVA Summary (stub) ===", "permanova_summary.txt")
    """
}
