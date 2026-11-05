nextflow.enable.dsl = 2

process DEREPLICATE {

    tag { sample_id }

    publishDir "${params.outdir}/dada2/dereplicated", mode: 'copy'

    input:
        tuple val(sample_id), path(r1_filt), path(r2_filt)

    output:
        tuple val(sample_id), path("${sample_id}_derep_F.rds"), path("${sample_id}_derep_R.rds"), emit: derep_reads

    script:
    """
    #!/usr/bin/env Rscript
    library(dada2)

    derep_f <- derepFastq("${r1_filt}")
    derep_r <- derepFastq("${r2_filt}")

    saveRDS(derep_f, "${sample_id}_derep_F.rds")
    saveRDS(derep_r, "${sample_id}_derep_R.rds")

    cat("${sample_id}: dereplicated", sum(derep_f\$uniques), "forward reads into", length(derep_f\$uniques), "unique sequences\\n")
    cat("${sample_id}: dereplicated", sum(derep_r\$uniques), "reverse reads into", length(derep_r\$uniques), "unique sequences\\n")
    """

    stub:
    """
    #!/usr/bin/env Rscript
    derep <- list(uniques=c(seq1=10, seq2=5), map=1:15, qual=matrix(30, 2, 10))
    class(derep) <- "derep"
    saveRDS(derep, "${sample_id}_derep_F.rds")
    saveRDS(derep, "${sample_id}_derep_R.rds")
    """
}
