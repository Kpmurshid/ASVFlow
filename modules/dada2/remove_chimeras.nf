nextflow.enable.dsl = 2

process REMOVE_CHIMERAS {

    tag { "chimera_removal" }

    publishDir "${params.outdir}/dada2/final", mode: 'copy'

    input:
        path(seqtab_rds)

    output:
        path("seqtab_nochim.rds"), emit: seqtab_nochim_rds
        path("seqtab_nochim.tsv"), emit: seqtab_nochim_tsv
        path("seqtab_nochim.fasta"), emit: seqtab_nochim_fasta
        path("chimera_stats.tsv"), emit: chimera_stats
        path("track_reads.tsv"), emit: track_reads

    script:
    """
    #!/usr/bin/env Rscript
    library(dada2)

    seqtab <- readRDS("${seqtab_rds}")

    cat("Input sequence table:", nrow(seqtab), "samples x", ncol(seqtab), "ASVs\\n")
    cat("Total sequences before chimera removal:", sum(seqtab), "\\n")

    seqtab_nochim <- removeBimeraDenovo(
        seqtab,
        method = "${params.dada2_chimera_method}",
        multithread = ${task.cpus},
        verbose = TRUE
    )

    saveRDS(seqtab_nochim, "seqtab_nochim.rds")

    cat("Output sequence table:", nrow(seqtab_nochim), "samples x", ncol(seqtab_nochim), "ASVs\\n")
    cat("Total sequences after chimera removal:", sum(seqtab_nochim), "\\n")

    n_chimeric_seqs <- ncol(seqtab) - ncol(seqtab_nochim)
    n_chimeric_reads <- sum(seqtab) - sum(seqtab_nochim)
    pct_chimeric_seqs <- round(100 * n_chimeric_seqs / ncol(seqtab), 1)
    pct_chimeric_reads <- round(100 * n_chimeric_reads / sum(seqtab), 1)

    sink("chimera_stats.tsv")
    cat("metric\tvalue\\n")
    cat("asvs_before\t", ncol(seqtab), "\\n", sep="")
    cat("asvs_after\t", ncol(seqtab_nochim), "\\n", sep="")
    cat("asvs_chimeric\t", n_chimeric_seqs, "\\n", sep="")
    cat("reads_before\t", sum(seqtab), "\\n", sep="")
    cat("reads_after\t", sum(seqtab_nochim), "\\n", sep="")
    cat("reads_chimeric\t", n_chimeric_reads, "\\n", sep="")
    cat("pct_chimeric_asvs\t", pct_chimeric_seqs, "\\n", sep="")
    cat("pct_chimeric_reads\t", pct_chimeric_reads, "\\n", sep="")
    sink()

    seqtab_t <- t(seqtab_nochim)
    asv_ids <- paste0("ASV_", sprintf("%04d", 1:nrow(seqtab_t)))
    rownames(seqtab_t) <- asv_ids
    write.table(seqtab_t, "seqtab_nochim.tsv", sep="\t", quote=FALSE, col.names=NA)

    asv_seqs <- colnames(seqtab_nochim)
    sink("seqtab_nochim.fasta")
    for (i in 1:length(asv_seqs)) {
        cat(">", asv_ids[i], "\\n", asv_seqs[i], "\\n", sep="")
    }
    sink()

    track <- data.frame(
        sample_id = rownames(seqtab_nochim),
        nonchim = rowSums(seqtab_nochim)
    )
    write.table(track, "track_reads.tsv", sep="\t", quote=FALSE, row.names=FALSE)

    cat("Wrote", length(asv_seqs), "ASVs to seqtab_nochim.fasta\\n")
    """

    stub:
    """
    #!/usr/bin/env Rscript
    seqtab <- matrix(c(100, 50, 75, 25), nrow=2, dimnames=list(c("S94", "S95"), c("ACGTACGT", "GCTAGCTA")))
    saveRDS(seqtab, "seqtab_nochim.rds")
    writeLines("ASV_ID\tS94\tS95\\nASV_0001\t100\t75\\nASV_0002\t50\t25", "seqtab_nochim.tsv")
    writeLines(">ASV_0001\\nACGTACGT\\n>ASV_0002\\nGCTAGCTA", "seqtab_nochim.fasta")
    writeLines("metric\tvalue\\nasvs_before\t2\\nasvs_after\t2\\nasvs_chimeric\t0\\nreads_before\t250\\nreads_after\t250\\nreads_chimeric\t0\\npct_chimeric_asvs\t0.0\\npct_chimeric_reads\t0.0", "chimera_stats.tsv")
    writeLines("sample_id\tnonchim\\nS94\t100\\nS95\t75", "track_reads.tsv")
    """
}
