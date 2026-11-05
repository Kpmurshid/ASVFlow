nextflow.enable.dsl = 2

process MERGE_PAIRS {

    tag { sample_id }

    publishDir "${params.outdir}/dada2/merged", mode: 'copy'

    input:
        tuple val(sample_id), path(dada_f), path(dada_r), path(derep_f), path(derep_r)

    output:
        tuple val(sample_id), path("${sample_id}_merged.rds"), emit: merged_reads
        tuple val(sample_id), path("${sample_id}_merge_stats.txt"), emit: merge_stats

    script:
    """
    #!/usr/bin/env Rscript
    library(dada2)

    dada_f <- readRDS("${dada_f}")
    dada_r <- readRDS("${dada_r}")
    derep_f <- readRDS("${derep_f}")
    derep_r <- readRDS("${derep_r}")

    merged <- mergePairs(
        dadaF = dada_f,
        derepF = derep_f,
        dadaR = dada_r,
        derepR = derep_r,
        minOverlap = ${params.dada2_min_overlap},
        maxMismatch = ${params.dada2_max_mismatch},
        verbose = TRUE
    )

    saveRDS(merged, "${sample_id}_merged.rds")

    n_input <- sum(dada_f\$denoised)
    n_merged <- sum(merged\$abundance)
    pct_merged <- round(100 * n_merged / n_input, 1)

    cat("${sample_id}:", n_merged, "/", n_input, "reads merged (", pct_merged, "%)\\n", sep="")

    sink("${sample_id}_merge_stats.txt")
    cat("sample_id\treads_in\treads_merged\tpercent_merged\\n")
    cat("${sample_id}\t", n_input, "\t", n_merged, "\t", pct_merged, "\\n", sep="")
    sink()

    if (n_merged == 0) {
        warning("No reads merged for ${sample_id} - check overlap parameters and read lengths")
    }
    """

    stub:
    """
    #!/usr/bin/env Rscript
    merged <- data.frame(
        sequence = c("ACGTACGTACGT", "GCTAGCTAGCTA"),
        abundance = c(100, 50),
        forward = c(1, 2),
        reverse = c(1, 2),
        nmatch = c(12, 12),
        nmismatch = c(0, 0),
        nindel = c(0, 0),
        prefer = c(1, 1),
        accept = c(TRUE, TRUE)
    )
    saveRDS(merged, "${sample_id}_merged.rds")
    writeLines("sample_id\treads_in\treads_merged\tpercent_merged\\n${sample_id}\t100\t90\t90.0", "${sample_id}_merge_stats.txt")
    """
}
