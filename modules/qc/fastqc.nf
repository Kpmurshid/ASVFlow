nextflow.enable.dsl = 2

process FASTQC {

    tag { "${sample_id} — ${fastq.getName()}" }

    publishDir "${params.outdir}/qc/${stage}", mode: 'copy', pattern: '*.{html,zip}'

    input:
        tuple val(sample_id), path(fastq)
        val(stage)

    output:
        tuple val(sample_id), path("*.zip"),  emit: qc_zips
        tuple val(sample_id), path("*.html"), emit: qc_htmls

    script:
    """
    set -euo pipefail
    fastqc --threads ${task.cpus} --outdir . ${fastq}
    """

    stub:
    def prefix = fastq.getSimpleName()
    """
    touch ${prefix}_fastqc.zip ${prefix}_fastqc.html
    """
}
