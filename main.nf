nextflow.enable.dsl = 2

include { FASTQC as FASTQC_RAW      } from './modules/qc/fastqc.nf'
include { FASTQC as FASTQC_TRIMMED  } from './modules/qc/fastqc.nf'
include { MULTIQC as MULTIQC_RAW    } from './modules/qc/multiqc.nf'
include { MULTIQC as MULTIQC_TRIMMED} from './modules/qc/multiqc.nf'
include { TRIM_PRIMERS              } from './modules/trimming/trim_primers.nf'

workflow {

    // Input validation
    if (!params.sample_sheet) {
        error "Missing required parameter: --sample_sheet"
    }

    // Validate and parse samplesheet
    Channel
        .fromPath(params.sample_sheet, checkIfExists: true)
        .splitCsv(header: true)
        .map { row ->
            def sample_id = row.sample_id
            def r1 = file(row.fastq_1, checkIfExists: true)
            def r2 = file(row.fastq_2, checkIfExists: true)

            if (!sample_id) {
                error "Empty sample_id in samplesheet"
            }

            tuple(sample_id, r1, r2)
        }
        .set { ch_reads }

    // Raw QC: FastQC on each file
    ch_reads
        .flatMap { sample_id, r1, r2 ->
            [tuple(sample_id, r1), tuple(sample_id, r2)]
        }
        .set { ch_raw_fastq_files }

    FASTQC_RAW(ch_raw_fastq_files, 'raw')

    // Raw QC: MultiQC aggregation
    FASTQC_RAW.out.qc_zips
        .map { sample_id, zip -> zip }
        .collect()
        .set { ch_raw_qc_zips }

    MULTIQC_RAW('raw', ch_raw_qc_zips)

    // Primer trimming (configurable mode)
    if (params.primer_mode == 'paired') {
        if (!params.primer_fwd || !params.primer_rev) {
            error "primer_mode='paired' requires --primer_fwd and --primer_rev"
        }

        TRIM_PRIMERS(ch_reads)

        ch_trimmed_reads = TRIM_PRIMERS.out.trimmed_reads
        ch_trim_reports = TRIM_PRIMERS.out.trim_json

    } else if (params.primer_mode == 'none') {
        log.info "Skipping primer trimming (primer_mode='none')"
        ch_trimmed_reads = ch_reads
        ch_trim_reports = Channel.empty()

    } else {
        error "Invalid primer_mode: ${params.primer_mode}. Must be 'paired' or 'none'"
    }

    // Post-trimming QC: FastQC
    ch_trimmed_reads
        .flatMap { sample_id, r1, r2 ->
            [tuple(sample_id, r1), tuple(sample_id, r2)]
        }
        .set { ch_trimmed_fastq_files }

    FASTQC_TRIMMED(ch_trimmed_fastq_files, 'trimmed')

    // Post-trimming QC: MultiQC aggregation
    FASTQC_TRIMMED.out.qc_zips
        .map { sample_id, zip -> zip }
        .collect()
        .mix(ch_trim_reports.collect().ifEmpty([]))
        .collect()
        .set { ch_trimmed_qc_inputs }

    MULTIQC_TRIMMED('trimmed', ch_trimmed_qc_inputs)
}

workflow.onComplete {
    log.info ""
    log.info "Pipeline completed at: ${workflow.complete}"
    log.info "Execution status: ${workflow.success ? 'SUCCESS' : 'FAILED'}"
    log.info "Duration: ${workflow.duration}"
    log.info "Results: ${params.outdir}"
    log.info ""
}
