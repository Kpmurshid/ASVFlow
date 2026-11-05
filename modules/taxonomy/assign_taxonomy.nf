nextflow.enable.dsl = 2

process ASSIGN_TAXONOMY {

    tag { "taxonomy_assignment" }

    publishDir "${params.outdir}/taxonomy", mode: 'copy'

    input:
        path(seqtab_rds)
        path(seqtab_fasta)
        path(silva_ref)

    output:
        path("taxonomy.rds"), emit: taxonomy_rds
        path("taxonomy.tsv"), emit: taxonomy_tsv
        path("taxonomy_stats.tsv"), emit: taxonomy_stats

    script:
    """
    #!/usr/bin/env Rscript
    library(dada2)
    library(Biostrings)

    cat("=== ASSIGN_TAXONOMY: SILVA Taxonomic Classification ===\\n\\n")

    fasta_file <- "${seqtab_fasta}"
    cat("Reading FASTA file:", fasta_file, "\\n")

    if (!file.exists(fasta_file)) {
        stop("ASV FASTA file not found: ", fasta_file)
    }

    fasta <- tryCatch({
        readDNAStringSet(fasta_file)
    }, error = function(e) {
        stop("Failed to parse FASTA file: ", fasta_file, "\\nError: ", e\$message)
    })

    if (length(fasta) == 0) {
        cat("Empty FASTA - creating empty outputs\\n")
        tax_empty <- matrix(character(0), nrow = 0, ncol = 6,
            dimnames = list(NULL, c("Kingdom", "Phylum", "Class", "Order", "Family", "Genus")))
        saveRDS(tax_empty, "taxonomy.rds")
        writeLines("ASV_ID\\tsequence\\tKingdom\\tPhylum\\tClass\\tOrder\\tFamily\\tGenus", "taxonomy.tsv")
        stats_lines <- c("metric\\tvalue", "total_asvs\\t0", "classified_kingdom\\t0",
            "classified_phylum\\t0", "classified_class\\t0", "classified_order\\t0",
            "classified_family\\t0", "classified_genus\\t0", "pct_classified_genus\\t0")
        writeLines(stats_lines, "taxonomy_stats.tsv")
        quit(save = "no", status = 0)
    }

    asv_ids <- names(fasta)
    asv_seqs <- as.character(fasta)
    cat("Parsed", length(asv_ids), "sequences\\n\\n")

    if (any(is.na(asv_ids)) || any(asv_ids == "") || any(nchar(asv_ids) == 0)) {
        stop("FASTA contains empty headers")
    }
    if (any(duplicated(asv_ids))) {
        stop("Duplicate ASV IDs: ", paste(unique(asv_ids[duplicated(asv_ids)]), collapse=", "))
    }
    if (any(is.na(asv_seqs)) || any(asv_seqs == "") || any(nchar(asv_seqs) == 0)) {
        stop("Empty sequences in FASTA")
    }

    asv_seqs_normalized <- toupper(asv_seqs)

    for (i in seq_along(asv_seqs_normalized)) {
        if (grepl("[^ACGTN]", asv_seqs_normalized[i])) {
            stop("Invalid DNA in ASV ", asv_ids[i])
        }
    }
    if (any(duplicated(asv_seqs_normalized))) {
        stop("Duplicate sequences: ", paste(asv_ids[duplicated(asv_seqs_normalized)], collapse=", "))
    }

    cat("FASTA validated\\n\\n")

    seqtab <- readRDS("${seqtab_rds}")
    rds_seqs <- colnames(seqtab)
    cat("RDS:", nrow(seqtab), "samples x", ncol(seqtab), "ASVs\\n\\n")

    if (any(is.na(rds_seqs)) || any(rds_seqs == "") || any(nchar(rds_seqs) == 0)) {
        stop("RDS contains empty sequences")
    }
    rds_seqs_normalized <- toupper(rds_seqs)
    if (any(duplicated(rds_seqs_normalized))) {
        stop("RDS contains duplicate sequences")
    }

    cat("Cross-validating FASTA and RDS...\\n")

    if (length(asv_seqs_normalized) != length(rds_seqs_normalized)) {
        stop("Count mismatch: FASTA=", length(asv_seqs_normalized), " RDS=", length(rds_seqs_normalized))
    }

    if (!setequal(asv_seqs_normalized, rds_seqs_normalized)) {
        only_fasta <- setdiff(asv_seqs_normalized, rds_seqs_normalized)
        only_rds <- setdiff(rds_seqs_normalized, asv_seqs_normalized)
        cat("ERROR: Sequence sets do not match\\n")
        if (length(only_fasta) > 0) cat("  In FASTA not RDS:", length(only_fasta), "\\n")
        if (length(only_rds) > 0) cat("  In RDS not FASTA:", length(only_rds), "\\n")
        stop("FASTA and RDS must contain identical sequences")
    }

    cat("Cross-validation passed\\n\\n")

    fasta_map <- data.frame(ASV_ID = asv_ids, sequence = asv_seqs_normalized, stringsAsFactors = FALSE)

    ref_file <- "${silva_ref}"
    if (!file.exists(ref_file)) stop("Reference not found: ", ref_file)

    cat("Running assignTaxonomy...\\n")
    seqs_for_taxonomy <- rds_seqs_normalized
    names(seqs_for_taxonomy) <- seqs_for_taxonomy

    tax <- assignTaxonomy(seqs_for_taxonomy, ref_file, minBoot = ${params.taxonomy_min_boot},
        tryRC = ${params.taxonomy_tryrc ? 'TRUE' : 'FALSE'}, outputBootstraps = FALSE,
        multithread = ${task.cpus}, verbose = TRUE)

    cat("\\nTaxonomy assignment complete\\n\\n")
    saveRDS(tax, "taxonomy.rds")

    tax_seqs <- rownames(tax)
    result <- data.frame(ASV_ID = fasta_map\$ASV_ID, sequence = fasta_map\$sequence,
        Kingdom = character(nrow(fasta_map)), Phylum = character(nrow(fasta_map)),
        Class = character(nrow(fasta_map)), Order = character(nrow(fasta_map)),
        Family = character(nrow(fasta_map)), Genus = character(nrow(fasta_map)),
        stringsAsFactors = FALSE)

    for (i in seq_len(nrow(result))) {
        seq <- result\$sequence[i]
        tax_idx <- match(seq, tax_seqs)
        if (is.na(tax_idx)) stop("Sequence not found in taxonomy")

        result\$Kingdom[i] <- if(is.na(tax[tax_idx, "Kingdom"])) NA_character_ else tax[tax_idx, "Kingdom"]
        result\$Phylum[i] <- if(is.na(tax[tax_idx, "Phylum"])) NA_character_ else tax[tax_idx, "Phylum"]
        result\$Class[i] <- if(is.na(tax[tax_idx, "Class"])) NA_character_ else tax[tax_idx, "Class"]
        result\$Order[i] <- if(is.na(tax[tax_idx, "Order"])) NA_character_ else tax[tax_idx, "Order"]
        result\$Family[i] <- if(is.na(tax[tax_idx, "Family"])) NA_character_ else tax[tax_idx, "Family"]
        result\$Genus[i] <- if(is.na(tax[tax_idx, "Genus"])) NA_character_ else tax[tax_idx, "Genus"]
    }

    write.table(result, "taxonomy.tsv", sep="\\t", quote=FALSE, row.names=FALSE)

    total_asvs <- nrow(result)
    classified_genus <- sum(!is.na(result\$Genus))
    pct_genus <- round(100 * classified_genus / total_asvs, 1)

    stats <- data.frame(metric = c("total_asvs", "classified_kingdom", "classified_phylum",
        "classified_class", "classified_order", "classified_family", "classified_genus", "pct_classified_genus"),
        value = c(total_asvs, sum(!is.na(result\$Kingdom)), sum(!is.na(result\$Phylum)),
        sum(!is.na(result\$Class)), sum(!is.na(result\$Order)), sum(!is.na(result\$Family)),
        classified_genus, pct_genus))
    write.table(stats, "taxonomy_stats.tsv", sep="\\t", quote=FALSE, row.names=FALSE)

    cat("=== Summary ===\\n")
    cat("Total:", total_asvs, "\\nGenus:", classified_genus, sprintf("(%.1f%%)\\n", pct_genus))
    """

    stub:
    """
    #!/usr/bin/env Rscript
    tax <- matrix(c("Bacteria", "Proteobacteria", "Gammaproteobacteria", "Enterobacterales",
        "Enterobacteriaceae", "Escherichia"), nrow = 1, byrow = TRUE,
        dimnames = list("ACGTACGTACGT", c("Kingdom", "Phylum", "Class", "Order", "Family", "Genus")))
    saveRDS(tax, "taxonomy.rds")
    tax_df <- data.frame(ASV_ID = "ASV_0001", sequence = "ACGTACGTACGT", Kingdom = "Bacteria",
        Phylum = "Proteobacteria", Class = "Gammaproteobacteria", Order = "Enterobacterales",
        Family = "Enterobacteriaceae", Genus = "Escherichia", stringsAsFactors = FALSE)
    write.table(tax_df, "taxonomy.tsv", sep="\\t", quote=FALSE, row.names=FALSE)
    stats <- data.frame(metric = c("total_asvs", "classified_kingdom", "classified_phylum",
        "classified_class", "classified_order", "classified_family", "classified_genus",
        "pct_classified_genus"), value = c(1, 1, 1, 1, 1, 1, 1, 100.0))
    write.table(stats, "taxonomy_stats.tsv", sep="\\t", quote=FALSE, row.names=FALSE)
    """
}
