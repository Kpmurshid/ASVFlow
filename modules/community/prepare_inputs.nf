nextflow.enable.dsl = 2

process PREPARE_INPUTS {

    tag { "prepare_community_inputs" }

    publishDir "${params.outdir}/community", mode: 'copy'

    input:
        path(seqtab_rds)
        path(seqtab_fasta)
        path(taxonomy_tsv)
        path(sample_metadata)

    output:
        path("phyloseq.rds"), emit: phyloseq_rds
        path("sample_data.tsv"), emit: sample_data
        path("validation_summary.txt"), emit: validation_summary
        path("zero_read_samples.txt"), emit: zero_samples, optional: true

    script:
    def has_taxonomy = taxonomy_tsv.name != 'NO_TAXONOMY'
    def has_metadata = sample_metadata.name != 'NO_METADATA'
    """
    #!/usr/bin/env Rscript
    library(phyloseq)
    library(Biostrings)

    cat("=== PREPARE_INPUTS: Validating and Merging Data ===\\n\\n")

    # Load ASV table
    seqtab <- readRDS("${seqtab_rds}")
    cat("ASV table:", nrow(seqtab), "samples x", ncol(seqtab), "ASVs\\n")

    # Check for zero-read samples
    zero_samples <- rowSums(seqtab) == 0
    if (any(zero_samples)) {
        cat("WARNING:", sum(zero_samples), "zero-read samples\\n")
        writeLines(rownames(seqtab)[zero_samples], "zero_read_samples.txt")
    }

    # Load FASTA and create OTU table with ASV_IDs
    fasta <- readDNAStringSet("${seqtab_fasta}")
    asv_ids <- names(fasta)
    asv_seqs <- as.character(fasta)
    
    if (length(asv_seqs) != ncol(seqtab)) stop("FASTA/RDS count mismatch")
    if (!setequal(toupper(asv_seqs), toupper(colnames(seqtab)))) stop("Sequence mismatch")
    
    otu_matrix <- seqtab
    colnames(otu_matrix) <- asv_ids[match(toupper(colnames(seqtab)), toupper(asv_seqs))]

    # Load taxonomy if provided
    has_taxonomy <- ${has_taxonomy ? 'TRUE' : 'FALSE'}
    taxonomy_matrix <- NULL
    if (has_taxonomy) {
        tax_df <- read.table("${taxonomy_tsv}", sep="\\t", header=TRUE, 
                            stringsAsFactors=FALSE, quote="", comment.char="")
        cat("Taxonomy:", nrow(tax_df), "ASVs\\n")
        tax_df <- tax_df[match(colnames(otu_matrix), tax_df\$ASV_ID), ]
        taxonomy_matrix <- as.matrix(tax_df[, -c(1, 2)])
        rownames(taxonomy_matrix) <- tax_df\$ASV_ID
    }

    # Load metadata if provided
    has_metadata <- ${has_metadata ? 'TRUE' : 'FALSE'}
    if (has_metadata) {
        meta_raw <- readLines("${sample_metadata}", n=1)
        sep <- if (grepl("\\t", meta_raw)) "\\t" else ","
        metadata <- read.table("${sample_metadata}", sep=sep, header=TRUE,
                              stringsAsFactors=FALSE, check.names=FALSE)
        sample_col <- grep("^sample_?id\$", colnames(metadata), ignore.case=TRUE)
        if (length(sample_col) == 0) stop("Missing sample_id column")
        colnames(metadata)[sample_col[1]] <- "sample_id"
        
        missing_meta <- setdiff(rownames(otu_matrix), metadata\$sample_id)
        if (length(missing_meta) > 0) {
            stop("Samples missing from metadata: ", paste(missing_meta, collapse=", "))
        }
        
        metadata <- metadata[match(rownames(otu_matrix), metadata\$sample_id), ]
        rownames(metadata) <- metadata\$sample_id
    } else {
        metadata <- data.frame(sample_id=rownames(otu_matrix), row.names=rownames(otu_matrix))
    }

    # Create phyloseq object
    OTU <- otu_table(otu_matrix, taxa_are_rows=FALSE)
    SAMPLE <- sample_data(metadata)
    
    if (!is.null(taxonomy_matrix)) {
        TAX <- tax_table(taxonomy_matrix)
        physeq <- phyloseq(OTU, TAX, SAMPLE)
    } else {
        physeq <- phyloseq(OTU, SAMPLE)
    }

    cat("\\n=== Phyloseq object created ===\\n")
    print(physeq)

    saveRDS(physeq, "phyloseq.rds")
    write.table(metadata, "sample_data.tsv", sep="\\t", quote=FALSE, row.names=FALSE)

    # Write validation summary
    sink("validation_summary.txt")
    cat("=== PREPARE_INPUTS Validation Summary ===\\n\\n")
    cat("ASV Table: ", nrow(seqtab), " samples x ", ncol(seqtab), " ASVs\\n", sep="")
    cat("Zero-read samples: ", sum(zero_samples), "\\n", sep="")
    cat("Taxonomy: ", if(has_taxonomy) "Present" else "Not provided", "\\n", sep="")
    cat("Metadata: ", if(has_metadata) "Present" else "Not provided", "\\n", sep="")
    cat("\\nPhyloseq components: ", paste(names(physeq@.Data), collapse=", "), "\\n", sep="")
    sink()

    cat("\\n=== Validation complete ===\\n")
    """

    stub:
    """
    #!/usr/bin/env Rscript
    library(phyloseq)
    otu <- matrix(c(100, 50), nrow=1, dimnames=list("TEST1", c("ASV_0001", "ASV_0002")))
    OTU <- otu_table(otu, taxa_are_rows=FALSE)
    metadata <- data.frame(sample_id="TEST1", group="GroupA", row.names="TEST1")
    SAMPLE <- sample_data(metadata)
    physeq <- phyloseq(OTU, SAMPLE)
    saveRDS(physeq, "phyloseq.rds")
    write.table(metadata, "sample_data.tsv", sep="\\t", quote=FALSE, row.names=FALSE)
    writeLines("=== PREPARE_INPUTS Validation Summary (stub) ===", "validation_summary.txt")
    """
}
