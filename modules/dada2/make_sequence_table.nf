nextflow.enable.dsl = 2

process MAKE_SEQUENCE_TABLE {

    tag { "sequence_table" }

    publishDir "${params.outdir}/dada2/seqtab", mode: 'copy'

    input:
        path(merged_files)

    output:
        path("seqtab_all.rds"), emit: seqtab_rds
        path("seqtab_all.tsv"), emit: seqtab_tsv

    script:
    """
    #!/usr/bin/env Rscript
    library(dada2)

    merged_files <- list.files(".", pattern="_merged\\\\.rds\$", full.names=TRUE)
    sample_ids <- sub("_merged\\\\.rds\$", "", basename(merged_files))

    cat("Building sequence table from", length(merged_files), "samples\\n")

    merged_list <- lapply(merged_files, readRDS)
    names(merged_list) <- sample_ids

    seqtab <- makeSequenceTable(merged_list)

    saveRDS(seqtab, "seqtab_all.rds")

    cat("Sequence table dimensions:", nrow(seqtab), "samples x", ncol(seqtab), "ASVs\\n")
    cat("Total sequences:", sum(seqtab), "\\n")

    seqtab_t <- t(seqtab)
    rownames(seqtab_t) <- paste0("ASV_", sprintf("%04d", 1:nrow(seqtab_t)))
    write.table(seqtab_t, "seqtab_all.tsv", sep="\t", quote=FALSE, col.names=NA)
    """

    stub:
    """
    #!/usr/bin/env Rscript
    seqtab <- matrix(c(100, 50, 75, 25), nrow=2, dimnames=list(c("S94", "S95"), c("ACGTACGT", "GCTAGCTA")))
    class(seqtab) <- "matrix"
    saveRDS(seqtab, "seqtab_all.rds")
    writeLines("ASV_ID\tS94\tS95\\nASV_0001\t100\t75\\nASV_0002\t50\t25", "seqtab_all.tsv")
    """
}
