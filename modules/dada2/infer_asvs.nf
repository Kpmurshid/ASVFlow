nextflow.enable.dsl = 2

process INFER_ASVS {

    tag { sample_id }

    publishDir "${params.outdir}/dada2/inferred", mode: 'copy'

    input:
        tuple val(sample_id), path(derep_f), path(derep_r), path(err_f), path(err_r)

    output:
        tuple val(sample_id), path("${sample_id}_dada_F.rds"), path("${sample_id}_dada_R.rds"), emit: dada_results

    script:
    def pool_arg = params.dada2_pool == 'pseudo' ? "'pseudo'" : (params.dada2_pool ? "TRUE" : "FALSE")
    """
    #!/usr/bin/env Rscript
    library(dada2)

    derep_f <- readRDS("${derep_f}")
    derep_r <- readRDS("${derep_r}")
    err_f <- readRDS("${err_f}")
    err_r <- readRDS("${err_r}")

    dada_f <- dada(derep_f, err=err_f, pool=${pool_arg}, multithread=${task.cpus})
    dada_r <- dada(derep_r, err=err_r, pool=${pool_arg}, multithread=${task.cpus})

    saveRDS(dada_f, "${sample_id}_dada_F.rds")
    saveRDS(dada_r, "${sample_id}_dada_R.rds")

    cat("${sample_id}: inferred", length(dada_f\$sequence), "forward ASVs\\n")
    cat("${sample_id}: inferred", length(dada_r\$sequence), "reverse ASVs\\n")
    """

    stub:
    """
    #!/usr/bin/env Rscript
    dada_obj <- list(
        denoised=matrix(c(10, 5, 3), nrow=1),
        sequence=c("ACGT", "GCTA", "TGCA"),
        quality=matrix(30, 3, 4),
        clustering=list(birth_ham=c(1,1,1), birth_fold=c(2,2,2))
    )
    class(dada_obj) <- "dada"
    saveRDS(dada_obj, "${sample_id}_dada_F.rds")
    saveRDS(dada_obj, "${sample_id}_dada_R.rds")
    """
}
