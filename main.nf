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
include { PREPARE_INPUTS            } from './modules/community/prepare_inputs.nf'
include { ALPHA_DIVERSITY           } from './modules/community/alpha_diversity.nf'
include { BETA_DIVERSITY            } from './modules/community/beta_diversity.nf'
include { TAXONOMIC_COMPOSITION     } from './modules/community/taxonomic_composition.nf'
include { SEQUENCING_DEPTH          } from './modules/community/sequencing_depth.nf'
include { PERMANOVA                 } from './modules/community/permanova.nf'
include { EXTRACT_ASV_SEQUENCES     } from './modules/phylogeny/extract_sequences.nf'
include { ALIGN_ASV_SEQUENCES       } from './modules/phylogeny/align_sequences.nf'
include { BUILD_ASV_PHYLOGENY       } from './modules/phylogeny/build_tree.nf'

def asvflowRunMetadataFile = null
def asvflowRunStartedAtMs = null
def asvflowDashboardStatus = 'DISABLED'
def asvflowDashboardUrl = null

// Keep terminal styling out of redirected and captured Nextflow logs.
def asvflowAnsiEnabled = System.console() != null && !System.getenv().containsKey('NO_COLOR') && System.getenv('TERM') != 'dumb'
def asvflowPalette = [cyan: '\u001B[36m', blue: '\u001B[34m', white: '\u001B[37m', bold: '\u001B[1m', reset: '\u001B[0m', green: '\u001B[32m', red: '\u001B[31m', yellow: '\u001B[33m']
def asvflowPaint = { String value, String color -> asvflowAnsiEnabled ? "${asvflowPalette[color]}${value}${asvflowPalette.reset}" : value }
def asvflowPanel = { String title, List<Map> rows, String statusColor = 'cyan' ->
    int innerWidth = 72
    def fitValue = { String value, int width ->
        if (value.length() <= width) return value
        int left = Math.max(1, width - 2 - 38)
        int right = width - 1 - left
        "${value.substring(0, left)}…${value.substring(value.length() - right)}"
    }
    def line = { String text, String color = 'white' ->
        // Keep panel geometry stable even when a path or URL is unusually long.
        String content = text.length() > innerWidth ? text.substring(0, innerWidth - 1) + '…' : text
        String padded = content.padRight(innerWidth)
        log.info "${asvflowPaint('║', 'cyan')} ${asvflowPaint(padded, color)} ${asvflowPaint('║', 'cyan')}"
    }
    log.info asvflowPaint("╔${'═' * (innerWidth + 2)}╗", 'cyan')
    line(" ${title}", statusColor)
    log.info asvflowPaint("╟${'─' * (innerWidth + 2)}╢", 'blue')
    rows.each { row ->
        if (row.section) {
            line(" ${row.section}", 'blue')
        } else {
            String label = row.label.toString().padRight(20)
            String value = fitValue(row.value?.toString() ?: '—', innerWidth - label.length() - 2)
            line(" ${label} ${value}", row.color ?: 'white')
        }
    }
    log.info asvflowPaint("╚${'═' * (innerWidth + 2)}╝", 'cyan')
}
def asvflowMode = {
    def enabled = []
    if (params.run_dada2) enabled << 'DADA2'
    if (params.run_taxonomy) enabled << 'TAXONOMY'
    if (params.run_community_analysis) enabled << 'COMMUNITY ANALYSIS'
    if (params.run_phylogenetic_analysis) enabled << 'PHYLOGENETIC ANALYSIS'
    enabled ? enabled.join(' + ') : 'QC / PREPROCESSING'
}
def asvflowPrintBrand = {
    // 6-row geometric sans-serif glyphs: ASVF (uppercase), low (lowercase)
    def glyphs = [
        ['01110', '11011', '11011', '11111', '11011', '11011'], // A
        ['01111', '11000', '01110', '00011', '00011', '11110'], // S
        ['11011', '11011', '11011', '01110', '01110', '00100'], // V
        ['11111', '11000', '11110', '11000', '11000', '11000'], // F
        ['1100',  '1100',  '1100',  '1100',  '1100',  '0111' ], // l
        ['00000', '00000', '01110', '11011', '11011', '01110'], // o
        ['0000000', '0000000', '1100011', '1101011', '1111111', '0110110'] // w
    ]

    def bgColors = [
        '\u001B[106m', // A - Bright Cyan
        '\u001B[104m', // S - Bright Blue
        '\u001B[105m', // V - Bright Magenta
        '\u001B[102m', // F - Bright Green
        '\u001B[103m', // l - Bright Yellow
        '\u001B[101m', // o - Bright Red
        '\u001B[106m'  // w - Bright Cyan
    ]
    String reset = '\u001B[0m'

    log.info ''
    (0..5).each { row ->
        String wordmark = (0..<glyphs.size()).collect { idx ->
            String pattern = glyphs[idx][row]
            if (asvflowAnsiEnabled) {
                pattern.collect { bit ->
                    bit == '1' ? "${bgColors[idx]}  ${reset}" : '  '
                }.join('')
            } else {
                pattern.replace('1', '@@').replace('0', '  ')
            }
        }.join(' ') // Tighter 1-space kerning between letters

        log.info " ${wordmark}"
    }
    log.info ''

    if (asvflowAnsiEnabled) {
        log.info " \u001B[1;97mAMPLICON SEQUENCING PIPELINE\u001B[0m"
        log.info " \u001B[1;96mASV\u001B[1;92mFlow\u001B[0m \u001B[1;104;97m v1.0.0 \u001B[0m"
    } else {
        log.info ' AMPLICON SEQUENCING PIPELINE'
        log.info ' ASVFlow v1.0.0'
    }
}

def writeAsvflowRunMetadata = { File target, Map metadata ->
    target.parentFile.mkdirs()
    File temporary = File.createTempFile('.asvflow-run-', '.tmp', target.parentFile)
    try {
        temporary.setText(groovy.json.JsonOutput.toJson(metadata), 'UTF-8')
        java.nio.file.Files.move(
            temporary.toPath(),
            target.toPath(),
            java.nio.file.StandardCopyOption.ATOMIC_MOVE,
            java.nio.file.StandardCopyOption.REPLACE_EXISTING
        )
    } finally {
        if (temporary.exists()) temporary.delete()
    }
}

def resolveAsvflowArtifactPath = { String option, String configuredPath ->
    def commandLine = workflow.commandLine ?: ''
    def pattern = "(?:^|\\s)${java.util.regex.Pattern.quote(option)}(?:=|\\s+)(?:\"([^\"]+)\"|'([^']+)'|([^\\s]+))"
    def matcher = commandLine =~ pattern
    def explicitPath = null
    if (matcher.find()) {
        explicitPath = matcher.group(1) ?: matcher.group(2) ?: matcher.group(3)
    }
    def path = new File(explicitPath ?: configuredPath)
    return (path.isAbsolute() ? path : new File(workflow.launchDir.toFile(), path.path)).canonicalPath
}

workflow {

    if (params.run_phylogenetic_analysis && !params.run_dada2) {
        error "Phylogenetic analysis requires DADA2. Enable it with --run_dada2 true."
    }
    // Nextflow creates workflow.start before it initializes trace/report observers.
    asvflowRunStartedAtMs = workflow.start.toInstant().toEpochMilli()
    def runKey = "${workflow.runName}_${workflow.sessionId}_${params.asvflow_invocation_id}".replaceAll(/[^A-Za-z0-9_.-]/, '_')
    asvflowRunMetadataFile = new File(workflow.projectDir.toString(), ".asvflow_dashboard/runs/${runKey}.json").absoluteFile
    def asvflowArtifactPaths = [
        trace: resolveAsvflowArtifactPath('-with-trace', "${params.asvflow_artifact_dir}/execution_trace.txt"),
        report: resolveAsvflowArtifactPath('-with-report', "${params.asvflow_artifact_dir}/execution_report.html"),
        timeline: resolveAsvflowArtifactPath('-with-timeline', "${params.asvflow_artifact_dir}/execution_timeline.html")
    ]
    writeAsvflowRunMetadata(asvflowRunMetadataFile, [
        version: 2,
        run_name: workflow.runName.toString(),
        session_id: workflow.sessionId.toString(),
        invocation_id: params.asvflow_invocation_id.toString(),
        command_line: workflow.commandLine,
        launch_dir: workflow.launchDir.toString(),
        outdir: new File(params.outdir).absolutePath,
        artifact_paths: asvflowArtifactPaths,
        started_at_ms: asvflowRunStartedAtMs,
        status: 'RUNNING'
    ])

    // Launch dashboard if enabled (before pipeline execution)
    if (params.enable_dashboard) {
        asvflowDashboardStatus = 'STARTING'
        def dashboard_script = "${projectDir}/bin/launch_dashboard.sh"
        def dashboard_cmd = [
            dashboard_script,
            params.outdir,
            params.dashboard_port.toString()
        ].join(' ')

        try {
            // Launch dashboard asynchronously
            def dashboard_env = System.getenv().collect { key, value -> "${key}=${value}" }
            dashboard_env.removeAll { it.startsWith('DASHBOARD_BIND_ADDRESS=') }
            if (params.dashboard_bind_address) {
                dashboard_env << "DASHBOARD_BIND_ADDRESS=${params.dashboard_bind_address}"
            }
            def proc = dashboard_cmd.execute(dashboard_env, null)
            def dashboard_stdout = new StringBuffer()
            def dashboard_stderr = new StringBuffer()
            proc.consumeProcessOutput(dashboard_stdout, dashboard_stderr)

            // Wait for launcher to complete with bounded timeout (max 20 seconds)
            def timeout_ms = 20000
            def start_time = System.currentTimeMillis()
            def launcher_completed = false

            while (System.currentTimeMillis() - start_time < timeout_ms) {
                try {
                    def exit_val = proc.exitValue()

                    if (exit_val == 0) {
                        // Launcher succeeded, read port and bind address files and print URL
                        def dashboard_dir = file("${params.outdir}/.asvflow_dashboard")
                        def port_file = file("${dashboard_dir}/dashboard.port")
                        def bind_address_file = file("${dashboard_dir}/dashboard.bind_address")

                        if (port_file.exists()) {
                            def port = port_file.text.trim()
                            def bind_address = bind_address_file.exists() ? bind_address_file.text.trim() : "127.0.0.1"

                            // Build display URL based on bind address
                            def display_url = "http://localhost:${port}"
                            if (bind_address != "127.0.0.1" && bind_address != "0.0.0.0" && bind_address != "::") {
                                def url_host = bind_address.contains(':') && !bind_address.startsWith('[') ? "[${bind_address}]" : bind_address
                                display_url = "http://${url_host}:${port}"
                            }

                            asvflowDashboardStatus = 'RUNNING'
                            asvflowDashboardUrl = display_url
                        } else {
                            log.warn "Dashboard launcher completed but port file not found"
                            log.warn "Expected: ${port_file}"
                        }
                    } else {
                        asvflowDashboardStatus = 'FAILED TO START'
                        def stdout = dashboard_stdout.toString().trim()
                        def stderr = dashboard_stderr.toString().trim()
                        log.warn "Dashboard launcher exited with code ${exit_val}"
                        if (stdout) {
                            log.warn "Launcher output: ${stdout}"
                        }
                        if (stderr) {
                            log.warn "Error output: ${stderr}"
                        }
                        log.warn "Pipeline will continue. Start manually with: ${dashboard_cmd}"
                    }
                    launcher_completed = true
                    break

                } catch (IllegalThreadStateException e) {
                    // Process still running, wait a bit
                    sleep(500)
                }
            }

            if (!launcher_completed) {
                asvflowDashboardStatus = 'STARTUP TIMEOUT'
                log.warn "Dashboard startup timed out after ${timeout_ms/1000} seconds"
                log.warn "Pipeline will continue. Check dashboard status manually."
            }

        } catch (Exception e) {
            asvflowDashboardStatus = 'FAILED TO START'
            log.warn "Dashboard startup failed (pipeline will continue): ${e.message}"
            log.warn "You can start the dashboard manually with: ${dashboard_cmd}"
        }
    }

    asvflowPrintBrand()
    def startupRows = [[label: 'Dashboard', value: asvflowDashboardStatus, color: asvflowDashboardStatus == 'RUNNING' ? 'green' : 'yellow']]
    if (asvflowDashboardUrl) startupRows << [label: 'Dashboard URL', value: asvflowDashboardUrl]
    startupRows << [label: 'Analysis mode', value: asvflowMode()]
    startupRows << [section: 'TAXONOMY']
    startupRows << [label: 'Enabled', value: params.run_taxonomy ? 'YES' : 'NO']
    startupRows << [label: 'SILVA version', value: params.run_taxonomy ? params.silva_version.toString() : '—']
    def startupSilvaFiles = [
        '138.1': [genus: 'silva_nr99_v138.1_train_set.fa.gz', species: 'silva_species_assignment_v138.1.fa.gz'],
        '144': [genus: 'silva_nr99_v144_toGenus_trainset.fa.gz', species: 'silva_v144_assignSpecies.fa.gz']
    ]
    def startupSilva = params.silva_version.toString()
    def startupGenusRef = params.silva_genus_ref ?: (startupSilvaFiles.containsKey(startupSilva) ? "${params.databases}/silva/${startupSilva}/${startupSilvaFiles[startupSilva].genus}" : 'auto-resolve')
    startupRows << [label: 'Genus reference', value: params.run_taxonomy ? startupGenusRef.toString() : '—']
    startupRows << [label: 'Species reference', value: params.run_taxonomy && params.taxonomy_add_species ? (params.silva_species_ref ?: (startupSilvaFiles.containsKey(startupSilva) ? "${params.databases}/silva/${startupSilva}/${startupSilvaFiles[startupSilva].species}" : 'auto-resolve')).toString() : '—']
    def startupResolution = params.taxonomy_table ? 'EXTERNAL TABLE' : (!params.run_taxonomy ? 'NONE' : (params.taxonomy_add_species ? 'SPECIES' : 'GENUS'))
    startupRows << [label: 'Resolution level', value: startupResolution]
    startupRows << [section: 'COMMUNITY ANALYSIS']
    startupRows << [label: 'Enabled', value: params.run_community_analysis ? 'YES' : 'NO']
    if (params.run_community_analysis && params.sample_metadata) startupRows << [label: 'Sample metadata', value: params.sample_metadata.toString()]
    startupRows << [section: 'PHYLOGENETIC ANALYSIS']
    startupRows << [label: 'Enabled', value: params.run_phylogenetic_analysis ? 'YES' : 'NO']
    asvflowPanel('PIPELINE START', startupRows)

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

        if (params.run_phylogenetic_analysis) {
            EXTRACT_ASV_SEQUENCES(REMOVE_CHIMERAS.out.seqtab_nochim_rds)
            ALIGN_ASV_SEQUENCES(EXTRACT_ASV_SEQUENCES.out.sequences)
            BUILD_ASV_PHYLOGENY(
                ALIGN_ASV_SEQUENCES.out.alignment,
                ALIGN_ASV_SEQUENCES.out.status,
                file("${projectDir}/bin/validate_newick.sh")
            )
        }

        // === PART 3: TAXONOMY ASSIGNMENT ===
        if (params.run_taxonomy) {

            // Resolve reference paths after CLI parameter overrides
            def databases_dir = params.databases
            def silva_ver = params.silva_version.toString()

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

                ADD_SPECIES(
                    ASSIGN_TAXONOMY.out.taxonomy_rds,
                    ASSIGN_TAXONOMY.out.taxonomy_tsv,
                    species_ref_file
                )
            }
        }

        // === PART 4: COMMUNITY ANALYSIS ===
        if (params.run_community_analysis) {

            // Determine taxonomy input (optional for alpha/beta, required for composition)
            def taxonomy_ch
            def has_taxonomy = false
            if (params.taxonomy_table) {
                // External taxonomy table provided
                taxonomy_ch = Channel.fromPath(params.taxonomy_table, checkIfExists: true)
                has_taxonomy = true
            } else if (params.run_taxonomy && params.taxonomy_add_species) {
                taxonomy_ch = ADD_SPECIES.out.taxonomy_species_tsv
                has_taxonomy = true
            } else if (params.run_taxonomy) {
                taxonomy_ch = ASSIGN_TAXONOMY.out.taxonomy_tsv
                has_taxonomy = true
            } else {
                taxonomy_ch = Channel.fromPath("$projectDir/NO_TAXONOMY", checkIfExists: false).ifEmpty(file("$projectDir/NO_TAXONOMY"))
            }

            // Optional metadata
            def metadata_ch
            if (params.sample_metadata) {
                metadata_ch = Channel.fromPath(params.sample_metadata, checkIfExists: true)
            } else {
                metadata_ch = Channel.fromPath("$projectDir/NO_METADATA", checkIfExists: false).ifEmpty(file("$projectDir/NO_METADATA"))
            }

            // Prepare inputs
            PREPARE_INPUTS(
                REMOVE_CHIMERAS.out.seqtab_nochim_rds,
                REMOVE_CHIMERAS.out.seqtab_nochim_fasta,
                taxonomy_ch,
                metadata_ch
            )

            // Alpha diversity (always run)
            ALPHA_DIVERSITY(PREPARE_INPUTS.out.phyloseq_rds)

            // Beta diversity (always run, saves distance matrices)
            BETA_DIVERSITY(PREPARE_INPUTS.out.phyloseq_rds)

            // Taxonomic composition (only if taxonomy available)
            if (has_taxonomy) {
                TAXONOMIC_COMPOSITION(PREPARE_INPUTS.out.phyloseq_rds)
            }

            // Sequencing depth (always run)
            SEQUENCING_DEPTH(PREPARE_INPUTS.out.phyloseq_rds)

            // PERMANOVA (only if metadata provided, reuses distance matrices)
            if (params.sample_metadata) {
                PERMANOVA(
                    PREPARE_INPUTS.out.phyloseq_rds,
                    BETA_DIVERSITY.out.dist_bray,
                    BETA_DIVERSITY.out.dist_jaccard
                )
            }
        }
    }
}

workflow.onComplete {
    if (asvflowRunMetadataFile == null) {
        asvflowRunStartedAtMs = System.currentTimeMillis()
        def runKey = "${workflow.runName}_${workflow.sessionId}_${params.asvflow_invocation_id}".replaceAll(/[^A-Za-z0-9_.-]/, '_')
        asvflowRunMetadataFile = new File(workflow.projectDir.toString(), ".asvflow_dashboard/runs/${runKey}.json").absoluteFile
    }
    writeAsvflowRunMetadata(asvflowRunMetadataFile, [
        version: 2,
        run_name: workflow.runName.toString(),
        session_id: workflow.sessionId.toString(),
        invocation_id: params.asvflow_invocation_id.toString(),
        command_line: workflow.commandLine,
        launch_dir: workflow.launchDir.toString(),
        outdir: new File(params.outdir).absolutePath,
        artifact_paths: [
            trace: resolveAsvflowArtifactPath('-with-trace', "${params.asvflow_artifact_dir}/execution_trace.txt"),
            report: resolveAsvflowArtifactPath('-with-report', "${params.asvflow_artifact_dir}/execution_report.html"),
            timeline: resolveAsvflowArtifactPath('-with-timeline', "${params.asvflow_artifact_dir}/execution_timeline.html")
        ],
        started_at_ms: asvflowRunStartedAtMs,
        completed_at_ms: System.currentTimeMillis(),
        status: workflow.success ? 'OK' : 'ERR'
    ])

    def errorText = workflow.errorMessage?.toString()?.toLowerCase() ?: ''
    def cancelled = !workflow.success && (errorText.contains('cancel') || errorText.contains('abort'))
    def finalStatus = workflow.success ? 'SUCCESS' : (cancelled ? 'CANCELLED' : 'FAILED')
    def finalColor = workflow.success ? 'green' : (cancelled ? 'yellow' : 'red')
    asvflowPanel('PIPELINE COMPLETE', [
        [label: 'Execution status', value: finalStatus, color: finalColor],
        [label: 'Output directory', value: params.outdir.toString()],
        [label: 'Execution duration', value: workflow.duration.toString()],
        [label: 'Completed at', value: workflow.complete.toString()]
    ], finalColor)

    if (params.enable_dashboard) {
        log.info ""
        log.info "Dashboard remains active for result exploration."
        log.info "Stop with: bin/stop_dashboard.sh ${params.outdir}"
    }

}
