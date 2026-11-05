nextflow.enable.dsl = 2

process ADD_SPECIES {

    tag { "species_assignment" }

    publishDir "${params.outdir}/taxonomy", mode: 'copy'

    input:
        path(taxonomy_rds)
        path(taxonomy_tsv)
        path(silva_ref)

    output:
        path("taxonomy_species.rds"), emit: taxonomy_species_rds
        path("taxonomy_species.tsv"), emit: taxonomy_species_tsv
        path("species_stats.tsv"), emit: species_stats

    script:
    """
    #!/usr/bin/env Rscript
    library(dada2)

    cat("=== ADD_SPECIES: Species-Level Classification ===\\n\\n")

    tax <- readRDS("${taxonomy_rds}")
    cat("Loaded taxonomy RDS:", nrow(tax), "ASVs\\n")

    if (nrow(tax) == 0) {
        cat("Empty taxonomy - creating empty outputs\\n")
        tax_species_empty <- matrix(character(0), nrow = 0, ncol = 7,
            dimnames = list(NULL, c("Kingdom", "Phylum", "Class", "Order", "Family", "Genus", "Species")))
        saveRDS(tax_species_empty, "taxonomy_species.rds")
        writeLines("ASV_ID\\tsequence\\tKingdom\\tPhylum\\tClass\\tOrder\\tFamily\\tGenus\\tSpecies",
                   "taxonomy_species.tsv")
        stats_lines <- c("metric\\tvalue", "asvs_with_genus\\t0", "asvs_with_species\\t0",
                        "pct_species_of_genus\\t0", "pct_species_of_total\\t0")
        writeLines(stats_lines, "species_stats.tsv")
        quit(save = "no", status = 0)
    }

    tax_tsv_file <- "${taxonomy_tsv}"
    if (!file.exists(tax_tsv_file)) stop("Taxonomy TSV not found")

    tax_genus_df <- read.table(tax_tsv_file, sep="\\t", header=TRUE,
                                stringsAsFactors=FALSE, check.names=FALSE)
    cat("Loaded taxonomy TSV:", nrow(tax_genus_df), "ASVs\\n\\n")

    if (!all(c("ASV_ID", "sequence") %in% colnames(tax_genus_df))) {
        stop("Taxonomy TSV missing required columns")
    }

    asv_map <- tax_genus_df[, c("ASV_ID", "sequence")]

    cat("Validating RDS and TSV...\\n")
    rds_seqs_normalized <- toupper(rownames(tax))
    tsv_seqs_normalized <- toupper(asv_map\$sequence)

    if (length(rds_seqs_normalized) != length(tsv_seqs_normalized)) {
        stop("Count mismatch: RDS=", length(rds_seqs_normalized), " TSV=", length(tsv_seqs_normalized))
    }

    if (!setequal(rds_seqs_normalized, tsv_seqs_normalized)) {
        stop("RDS and TSV sequence sets do not match")
    }

    cat("RDS-TSV validation passed\\n\\n")

    ref_file <- "${silva_ref}"
    if (!file.exists(ref_file)) stop("Species reference not found")

    cat("Running addSpecies...\\n")
    tax_species <- addSpecies(tax, ref_file, allowMultiple = FALSE,
        tryRC = ${params.taxonomy_tryrc ? 'TRUE' : 'FALSE'}, verbose = TRUE)

    cat("\\nSpecies assignment complete\\n\\n")
    saveRDS(tax_species, "taxonomy_species.rds")

    tax_seqs <- rownames(tax_species)
    result <- data.frame(ASV_ID = asv_map\$ASV_ID, sequence = asv_map\$sequence,
        Kingdom = character(nrow(asv_map)), Phylum = character(nrow(asv_map)),
        Class = character(nrow(asv_map)), Order = character(nrow(asv_map)),
        Family = character(nrow(asv_map)), Genus = character(nrow(asv_map)),
        Species = character(nrow(asv_map)), stringsAsFactors = FALSE)

    for (i in seq_len(nrow(result))) {
        seq <- toupper(result\$sequence[i])
        tax_idx <- match(seq, toupper(tax_seqs))
        if (is.na(tax_idx)) stop("Sequence not found")

        result\$Kingdom[i] <- if(is.na(tax_species[tax_idx, "Kingdom"])) NA_character_ else tax_species[tax_idx, "Kingdom"]
        result\$Phylum[i] <- if(is.na(tax_species[tax_idx, "Phylum"])) NA_character_ else tax_species[tax_idx, "Phylum"]
        result\$Class[i] <- if(is.na(tax_species[tax_idx, "Class"])) NA_character_ else tax_species[tax_idx, "Class"]
        result\$Order[i] <- if(is.na(tax_species[tax_idx, "Order"])) NA_character_ else tax_species[tax_idx, "Order"]
        result\$Family[i] <- if(is.na(tax_species[tax_idx, "Family"])) NA_character_ else tax_species[tax_idx, "Family"]
        result\$Genus[i] <- if(is.na(tax_species[tax_idx, "Genus"])) NA_character_ else tax_species[tax_idx, "Genus"]
        result\$Species[i] <- if(is.na(tax_species[tax_idx, "Species"])) NA_character_ else tax_species[tax_idx, "Species"]
    }

    write.table(result, "taxonomy_species.tsv", sep="\\t", quote=FALSE, row.names=FALSE)

    total_asvs <- nrow(result)
    asvs_with_genus <- sum(!is.na(result\$Genus))
    asvs_with_species <- sum(!is.na(result\$Species))
    pct_species_of_genus <- if(asvs_with_genus > 0) round(100 * asvs_with_species / asvs_with_genus, 1) else 0
    pct_species_of_total <- round(100 * asvs_with_species / total_asvs, 1)

    stats <- data.frame(
        metric = c("asvs_with_genus", "asvs_with_species", "pct_species_of_genus", "pct_species_of_total"),
        value = c(asvs_with_genus, asvs_with_species, pct_species_of_genus, pct_species_of_total))
    write.table(stats, "species_stats.tsv", sep="\\t", quote=FALSE, row.names=FALSE)

    cat("=== Summary ===\\n")
    cat("Total:", total_asvs, "\\nGenus:", asvs_with_genus, "\\nSpecies:", asvs_with_species,
        sprintf("(%.1f%%)\\n", pct_species_of_total))
    """

    stub:
    """
    #!/usr/bin/env Rscript
    tax <- matrix(c("Bacteria", "Proteobacteria", "Gammaproteobacteria", "Enterobacterales",
        "Enterobacteriaceae", "Escherichia", "Escherichia_coli"), nrow = 1, byrow = TRUE,
        dimnames = list("ACGTACGTACGT", c("Kingdom", "Phylum", "Class", "Order", "Family", "Genus", "Species")))
    saveRDS(tax, "taxonomy_species.rds")
    tax_df <- data.frame(ASV_ID = "ASV_0001", sequence = "ACGTACGTACGT", Kingdom = "Bacteria",
        Phylum = "Proteobacteria", Class = "Gammaproteobacteria", Order = "Enterobacterales",
        Family = "Enterobacteriaceae", Genus = "Escherichia", Species = "Escherichia_coli",
        stringsAsFactors = FALSE)
    write.table(tax_df, "taxonomy_species.tsv", sep="\\t", quote=FALSE, row.names=FALSE)
    stats <- data.frame(metric = c("asvs_with_genus", "asvs_with_species",
        "pct_species_of_genus", "pct_species_of_total"), value = c(1, 1, 100.0, 100.0))
    write.table(stats, "species_stats.tsv", sep="\\t", quote=FALSE, row.names=FALSE)
    """
}
