nextflow.enable.dsl = 2

process FILTER_AND_TRIM {

    tag { sample_id }

    publishDir "${params.outdir}/dada2/filtered", mode: 'copy', pattern: '*.fastq.gz'

    input:
        tuple val(sample_id), path(r1), path(r2)

    output:
        tuple val(sample_id), path("${sample_id}_R1_filt.fastq.gz"), path("${sample_id}_R2_filt.fastq.gz"), emit: filtered_reads

    script:
    def truncLen_f = params.dada2_trunc_len_f ?: 0
    def truncLen_r = params.dada2_trunc_len_r ?: 0
    def rm_phix = params.dada2_rm_phix ? 'TRUE' : 'FALSE'
    """
    #!/usr/bin/env Rscript
    library(dada2)

    out <- filterAndTrim(
        fwd = "${r1}",
        filt = "${sample_id}_R1_filt.fastq.gz",
        rev = "${r2}",
        filt.rev = "${sample_id}_R2_filt.fastq.gz",
        truncLen = c(${truncLen_f}, ${truncLen_r}),
        maxEE = c(${params.dada2_max_ee_f}, ${params.dada2_max_ee_r}),
        truncQ = ${params.dada2_trunc_q},
        maxN = ${params.dada2_max_n},
        minLen = ${params.dada2_min_len},
        rm.lowcomplex = ${params.dada2_rm_lowcomplex},
        rm.phix = ${rm_phix},
        compress = TRUE,
        multithread = ${task.cpus}
    )

    cat("${sample_id}: reads.in =", out[1], "reads.out =", out[2], "\\n")

    if (out[2] == 0) {
        stop("No reads passed filtering for ${sample_id}")
    }
    """

    stub:
    """
    touch ${sample_id}_R1_filt.fastq.gz ${sample_id}_R2_filt.fastq.gz
    """
}
