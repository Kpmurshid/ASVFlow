nextflow.enable.dsl = 2

process MULTIQC {

    tag { stage }

    publishDir "${params.outdir}/qc/${stage}", mode: 'copy', pattern: 'multiqc_report.html'

    input:
        val(stage)
        path(input_files)

    output:
        path("multiqc_report.html"),      emit: report
        path("multiqc_report_data"),      emit: data

    script:
    """
    set -euo pipefail
    multiqc --filename multiqc_report.html .
    """

    stub:
    """
    mkdir -p multiqc_report_data
    touch multiqc_report.html
    """
}
