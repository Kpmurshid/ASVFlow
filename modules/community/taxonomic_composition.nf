
nextflow.enable.dsl = 2

process TAXONOMIC_COMPOSITION {

    tag { "taxonomic_composition" }

    publishDir "${params.outdir}/community", mode: 'copy'

    input:
        path(phyloseq_rds)

    output:
        path("composition_phylum_counts.tsv"), emit: comp_phylum_counts
        path("composition_phylum_relabund.tsv"), emit: comp_phylum_relabund
        path("composition_phylum.pdf"), emit: comp_phylum_plot, optional: true
        path("composition_genus_counts.tsv"), emit: comp_genus_counts
        path("composition_genus_relabund.tsv"), emit: comp_genus_relabund
        path("composition_genus.pdf"), emit: comp_genus_plot, optional: true
        path("composition_summary.tsv"), emit: comp_summary

    script:
    """
    #!/usr/bin/env Rscript
    library(phyloseq)
    library(ggplot2)

    cat("=== TAXONOMIC_COMPOSITION ===\\n\\n")

    physeq <- readRDS("${phyloseq_rds}")

    if (is.null(tryCatch(tax_table(physeq), error=function(e) NULL))) {
        stop("Taxonomy not found. Run with --run_taxonomy true")
    }

    tax_df <- as(tax_table(physeq), "matrix")
    otu_mat <- as(otu_table(physeq), "matrix")
    if (taxa_are_rows(physeq)) otu_mat <- t(otu_mat)

    # Process phylum level
    phylum_labels <- tax_df[, "Phylum"]
    phylum_labels[is.na(phylum_labels)] <- "Unclassified_Phylum"
    
    phylum_counts <- aggregate(t(otu_mat), by=list(phylum=phylum_labels), FUN=sum)
    rownames(phylum_counts) <- phylum_counts\$phylum
    phylum_counts\$phylum <- NULL
    phylum_counts <- t(phylum_counts)

    # Relative abundance
    nonzero <- rowSums(phylum_counts) > 0
    phylum_rel <- matrix(0, nrow=nrow(phylum_counts), ncol=ncol(phylum_counts))
    rownames(phylum_rel) <- rownames(phylum_counts)
    colnames(phylum_rel) <- colnames(phylum_counts)
    if (any(nonzero)) {
        phylum_rel[nonzero, ] <- sweep(phylum_counts[nonzero, , drop=FALSE], 1, 
                                       rowSums(phylum_counts[nonzero, , drop=FALSE]), "/") * 100
    }

    write.table(phylum_counts, "composition_phylum_counts.tsv", sep="\\t", quote=FALSE, col.names=NA)
    write.table(phylum_rel, "composition_phylum_relabund.tsv", sep="\\t", quote=FALSE, col.names=NA)

    # Process genus level
    genus_labels <- tax_df[, "Genus"]
    unclass_genus <- is.na(genus_labels)
    if (any(unclass_genus)) {
        family_labels <- tax_df[unclass_genus, "Family"]
        for (i in which(unclass_genus)) {
            if (!is.na(family_labels[sum(unclass_genus[1:i])])) {
                genus_labels[i] <- paste0("Unclassified_Genus (", 
                                         family_labels[sum(unclass_genus[1:i])], ")")
            } else {
                genus_labels[i] <- "Unclassified_Genus"
            }
        }
    }

    genus_counts <- aggregate(t(otu_mat), by=list(genus=genus_labels), FUN=sum)
    rownames(genus_counts) <- genus_counts\$genus
    genus_counts\$genus <- NULL
    genus_counts <- t(genus_counts)

    genus_rel <- matrix(0, nrow=nrow(genus_counts), ncol=ncol(genus_counts))
    rownames(genus_rel) <- rownames(genus_counts)
    colnames(genus_rel) <- colnames(genus_counts)
    if (any(nonzero)) {
        genus_rel[nonzero, ] <- sweep(genus_counts[nonzero, , drop=FALSE], 1, 
                                      rowSums(genus_counts[nonzero, , drop=FALSE]), "/") * 100
    }

    write.table(genus_counts, "composition_genus_counts.tsv", sep="\\t", quote=FALSE, col.names=NA)
    write.table(genus_rel, "composition_genus_relabund.tsv", sep="\\t", quote=FALSE, col.names=NA)

    # Summary
    summary_df <- data.frame(
        rank = c("Phylum", "Genus"),
        n_taxa = c(ncol(phylum_counts), ncol(genus_counts)),
        n_unclassified = c(sum(is.na(tax_df[, "Phylum"])), sum(unclass_genus))
    )
    write.table(summary_df, "composition_summary.tsv", sep="\\t", quote=FALSE, row.names=FALSE)

    cat("\\n=== TAXONOMIC_COMPOSITION complete ===\\n")
    """

    stub:
    """
    #!/usr/bin/env Rscript
    counts <- matrix(c(100, 50), nrow=1, dimnames=list("TEST1", c("Taxa1", "Taxa2")))
    write.table(counts, "composition_phylum_counts.tsv", sep="\\t", quote=FALSE, col.names=NA)
    write.table(counts, "composition_phylum_relabund.tsv", sep="\\t", quote=FALSE, col.names=NA)
    write.table(counts, "composition_genus_counts.tsv", sep="\\t", quote=FALSE, col.names=NA)
    write.table(counts, "composition_genus_relabund.tsv", sep="\\t", quote=FALSE, col.names=NA)
    summary <- data.frame(rank="Phylum", n_taxa=2, n_unclassified=0)
    write.table(summary, "composition_summary.tsv", sep="\\t", quote=FALSE, row.names=FALSE)
    """
}
