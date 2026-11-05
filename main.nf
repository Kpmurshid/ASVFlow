nextflow.enable.dsl = 2

include { FASTQC as FASTQC_RAW      } from './modules/qc/fastqc.nf'
include { FASTQC as FASTQC_TRIMMED  } from './modules/qc/fastqc.nf'
include { MULTIQC as MULTIQC_RAW    } from './modules/qc/multiqc.nf'
include { MULTIQC as MULTIQC_TRIMMED} from './modules/qc/multiqc.nf'
include { TRIM_PRIMERS              } from './modules/trimming/trim_primers.nf'
include { PLOT_QUALITY_PROFILE      } from './modules/dada2/plot_quality_profile.nf'
include { FILTER_AND_TRIM           } from './modules/dada2/filter_and_trim.nf'
include { LEARN_ERRORS              } from './modules/dada2/learn_errors.nf'
include { DEREPLICATE               } from './modules/dada2/dereplicate.nf'
include { INFER_ASVS                } from './modules/dada2/infer_asvs.nf'
include { MERGE_PAIRS               } from './modules/dada2/merge_pairs.nf'
include { MAKE_SEQUENCE_TABLE       } from './modules/dada2/make_sequence_table.nf'
include { REMOVE_CHIMERAS           } from './modules/dada2/remove_chimeras.nf'
include { ASSIGN_TAXONOMY           } from './modules/taxonomy/assign_taxonomy.nf'
include { ADD_SPECIES               } from './modules/taxonomy/add_species.nf'

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

    // DADA2 ASV inference pipeline
    if (params.run_dada2) {

        // Quality profile plotting
        ch_trimmed_reads
            .map { sample_id, r1, r2 -> [r1, r2] }
            .flatten()
            .collect()
            .set { ch_all_trimmed_files }

        PLOT_QUALITY_PROFILE(ch_all_trimmed_files)

        // Quality filtering and trimming
        FILTER_AND_TRIM(ch_trimmed_reads)

        // Error learning (pooled across all samples)
        FILTER_AND_TRIM.out.filtered_reads
            .map { sample_id, r1, r2 -> [r1, r2] }
            .flatten()
            .collect()
            .set { ch_all_filtered }

        LEARN_ERRORS(ch_all_filtered)

        // Dereplication (per-sample)
        DEREPLICATE(FILTER_AND_TRIM.out.filtered_reads)

        // ASV inference (per-sample with error models)
        DEREPLICATE.out.derep_reads
            .combine(LEARN_ERRORS.out.error_models)
            .set { ch_dada_input }

        INFER_ASVS(ch_dada_input)

        // Merging (per-sample, requires both dada and derep objects)
        INFER_ASVS.out.dada_results
            .join(DEREPLICATE.out.derep_reads)
            .set { ch_merge_input }

        MERGE_PAIRS(ch_merge_input)

        // Sequence table construction (all samples)
        MERGE_PAIRS.out.merged_reads
            .map { sample_id, merged_rds -> merged_rds }
            .collect()
            .set { ch_all_merged }

        MAKE_SEQUENCE_TABLE(ch_all_merged)

        // Chimera removal
        REMOVE_CHIMERAS(MAKE_SEQUENCE_TABLE.out.seqtab_rds)

        // === PART 3: TAXONOMY ASSIGNMENT ===
        if (params.run_taxonomy) {

            // Resolve reference paths after CLI parameter overrides
            def databases_dir = params.databases
            def silva_ver = params.silva_version

            // Known SILVA versions with verified DADA2 filenames
            def known_silva_versions = [
                '138.1': [
                    genus: 'silva_nr99_v138.1_train_set.fa.gz',
                    species: 'silva_species_assignment_v138.1.fa.gz'
                ],
                '144': [
                    genus: 'silva_nr99_v144_toGenus_trainset.fa.gz',
                    species: 'silva_v144_assignSpecies.fa.gz'
                ]
            ]

            // Resolve genus reference path
            def genus_ref_path
            if (params.silva_genus_ref != null) {
                genus_ref_path = params.silva_genus_ref
            } else if (known_silva_versions.containsKey(silva_ver)) {
                def genus_file = known_silva_versions[silva_ver]['genus']
                genus_ref_path = "${databases_dir}/silva/${silva_ver}/${genus_file}"
            } else {
                error """
                Unknown SILVA version: ${silva_ver}

                Cannot determine reference filenames for SILVA v${silva_ver}.

                Known versions with automatic filename resolution:
                - 138.1
                - 144

                Please provide explicit reference paths:
                  --silva_genus_ref <path/to/genus_reference.fa.gz>
                  --silva_species_ref <path/to/species_reference.fa.gz>

                Or use a known version:
                  --silva_version 138.1
                  --silva_version 144
                """
            }

            // Validate genus reference exists
            def genus_ref_file = file(genus_ref_path)
            if (!genus_ref_file.exists()) {
                def expected_file = genus_ref_path.tokenize('/')[-1]
                error """
                ╔════════════════════════════════════════════════════════════════════════════╗
                ║ SILVA Reference Database Not Found                                         ║
                ╚════════════════════════════════════════════════════════════════════════════╝

                Required file not found:
                ${genus_ref_path}

                Expected filename: ${expected_file}
                Expected location: ${databases_dir}/silva/${silva_ver}/

                ASVFlow requires SILVA DADA2-formatted reference databases.
                These files are not included in this repository.

                To obtain SILVA references:
                1. Visit: https://benjjneb.github.io/dada2/training.html
                2. Download SILVA v${silva_ver} training sets
                3. Place in: ${databases_dir}/silva/${silva_ver}/

                To skip taxonomy assignment:
                  --run_taxonomy false
                """
            }

            log.info "Taxonomy assignment enabled"
            log.info "  SILVA version: ${silva_ver}"
            log.info "  Genus reference: ${genus_ref_path}"

            // Stage 1: Assign genus-level taxonomy
            ASSIGN_TAXONOMY(
                REMOVE_CHIMERAS.out.seqtab_nochim_rds,
                REMOVE_CHIMERAS.out.seqtab_nochim_fasta,
                genus_ref_file
            )

            // Stage 2: Add species-level taxonomy (optional)
            if (params.taxonomy_add_species) {

                // Resolve species reference path
                def species_ref_path
                if (params.silva_species_ref != null) {
                    species_ref_path = params.silva_species_ref
                } else if (known_silva_versions.containsKey(silva_ver)) {
                    def species_file = known_silva_versions[silva_ver]['species']
                    species_ref_path = "${databases_dir}/silva/${silva_ver}/${species_file}"
                } else {
                    error """
                    Unknown SILVA version: ${silva_ver}

                    Species assignment requires explicit reference path for v${silva_ver}:
                      --silva_species_ref <path/to/species_reference.fa.gz>

                    Or use a known version (138.1, 144)
                    """
                }

                // Validate species reference exists
                def species_ref_file = file(species_ref_path)
                if (!species_ref_file.exists()) {
                    error """
                    SILVA species reference not found: ${species_ref_path}

                    To skip species assignment:
                      --taxonomy_add_species false
                    """
                }

                log.info "  Species reference: ${species_ref_path}"

                ADD_SPECIES(
                    ASSIGN_TAXONOMY.out.taxonomy_rds,
                    ASSIGN_TAXONOMY.out.taxonomy_tsv,
                    species_ref_file
                )
            }
        }
    }
}

workflow.onComplete {
    log.info ""
    log.info "Pipeline completed at: ${workflow.complete}"
    log.info "Execution status: ${workflow.success ? 'SUCCESS' : 'FAILED'}"
    log.info "Duration: ${workflow.duration}"
    log.info "Results: ${params.outdir}"
    log.info ""
}
