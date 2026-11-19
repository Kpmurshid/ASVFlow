# ASVFlow

ASVFlow is a DSL2 Nextflow workflow for paired-end amplicon sequencing. It runs read quality control, optional Cutadapt primer removal, DADA2 ASV inference, and optional SILVA taxonomy and community analyses. The workflow and synthetic fixtures are oriented to bacterial 16S rRNA amplicons. ITS support is not established by the current implementation.

## Workflow and options

FastQC and MultiQC run on raw reads and again after the primer-trimming stage. Primer removal defaults to paired Cutadapt primers; set `--primer_mode none` to skip it. DADA2 runs by default and performs quality profiling, filtering, error learning, dereplication, inference, paired-read merging, sequence-table construction, and chimera removal.

Taxonomy is off by default. `--run_taxonomy true` assigns taxonomy with DADA2's classifier and a SILVA reference. Species-level addition is a separate opt-in (`--taxonomy_add_species true`) and requires its SILVA species reference. SILVA versions `144` and `138.1` have automatic filenames; other versions require explicit reference paths.

Community analysis is off by default and requires DADA2. When enabled, alpha diversity, beta diversity (Bray-Curtis and Jaccard), and sequencing-depth outputs are generated. Taxonomic composition is generated only when an internal or external taxonomy table is available. PERMANOVA is generated only when sample metadata is supplied. An external taxonomy table can be supplied using `--taxonomy_table`.

Phylogenetic analysis is also optional (`--run_phylogenetic_analysis true`) and requires DADA2. It extracts representative sequences from the nonchimeric sequence table, aligns them with the bundled MAFFT image, and infers an unrooted Newick tree with the bundled FastTree image. It does not calculate Faith's PD or UniFrac.

| Stage | Control | Default |
|---|---|---|
| Primer removal | `--primer_mode paired\|none`, `--primer_fwd`, `--primer_rev` | Paired; primer sequences required |
| DADA2 | `--run_dada2` | `true` |
| Taxonomy | `--run_taxonomy`, `--taxonomy_add_species` | `false`, `false` |
| Community analysis | `--run_community_analysis` | `false` |
| Phylogenetic analysis | `--run_phylogenetic_analysis` | `false` |
| Dashboard | `--enable_dashboard` | `false` |

## Requirements and setup

- Java 11 or newer and Nextflow. The repository does not enforce a minimum Nextflow version in its configuration; use a current DSL2-capable Nextflow release.
- Apptainer or Singularity is required by the configured container execution and by the setup and dashboard scripts. Container paths default to `tools/`.
- `curl` is needed by `bin/download_tools.sh`. Downloading containers and the reference files requires network access; after setup, pipeline analysis uses local containers and references.
- Dashboard launch requires Linux, Bash, Python 3.9 or newer, `setsid`, GNU `stat`, and `curl`; Linux pidfd support (kernel 5.1+) is used for process ownership checks. `ss` or `lsof` is recommended for port checks. Dashboard Python dependencies are packaged in the dashboard container, not installed on the host.

Install Nextflow using its official installation instructions, then from the repository root run:

```bash
./bin/download_tools.sh
```

The script pulls ten images into `tools/`: DADA2 (`bioconductor-dada2:1.38.0`), Cutadapt (`cutadapt:5.2`), FastQC (`fastqc:0.13.0`), MultiQC (`multiqc:v1.35`), ASVFlow stats, dashboard and report images, and SeqKit, MAFFT and FastTree. Stats and dashboard images are the published ASVFlow images named in `bin/download_tools.sh`; MAFFT and FastTree are used by optional phylogenetic analysis. The report and SeqKit images are not called by the workflow. The setup script downloads SILVA v144 DADA2-formatted genus, species-training, and species-assignment files under `databases/silva/144/`. Taxonomy can instead use SILVA v138.1 references obtained separately or user-supplied references. Reference files are not committed to the repository.

The dashboard image contains Python 3.12 with Streamlit 1.35.0, NumPy 1.26.4, pandas 2.2.2, PyArrow 16.1.0, Plotly 5.22.0, and watchdog 4.0.1. Community analysis runs in the stats image, which supplies R, phyloseq and vegan.

## Inputs

The required sample sheet is CSV with exactly these header fields. Paths are resolved from the Nextflow launch directory. Both FASTQ inputs must exist; the included validator additionally checks gzip integrity and duplicate sample identifiers.

```csv
sample_id,fastq_1,fastq_2
SAMPLE01,data/SAMPLE01_R1.fastq.gz,data/SAMPLE01_R2.fastq.gz
SAMPLE02,data/SAMPLE02_R1.fastq.gz,data/SAMPLE02_R2.fastq.gz
```

The validator accepts this CSV structure and validates gzip streams; it does not enforce a filename suffix. Reads are paired-end. To validate a sheet:

```bash
python3 bin/validate_samplesheet.py samplesheet.csv
```

With default `--primer_mode paired`, provide both primer sequences in 5′ to 3′ orientation. Primer trimming can be skipped with `--primer_mode none`.

Optional sample metadata for community analysis may be comma- or tab-delimited. It must have a `sample_id` or `sampleid` column and a row for every sample; remaining columns are sample variables. For example, the repository fixture is TSV:

```tsv
sample_id	group	treatment	replicate
SAMPLE01	Control	Control	1
SAMPLE03	Treatment_A	Treatment_A	1
```

PERMANOVA is attempted when metadata is provided and uses available grouping variables; alpha and beta diversity do not require metadata.

## Running ASVFlow

Minimal run (QC, primer removal and DADA2; no taxonomy/community analysis):

```bash
nextflow run main.nf \
  --sample_sheet samplesheet.csv \
  --primer_fwd GTGCCAGCMGCCGCGGTAA \
  --primer_rev GGACTACHVGGGTWTCTAAT \
  --outdir results/my_run
```

Taxonomy, species addition and community analysis:

```bash
nextflow run main.nf \
  --sample_sheet samplesheet.csv \
  --primer_fwd GTGCCAGCMGCCGCGGTAA \
  --primer_rev GGACTACHVGGGTWTCTAAT \
  --run_taxonomy true \
  --taxonomy_add_species true \
  --run_community_analysis true \
  --run_phylogenetic_analysis true \
  --sample_metadata metadata.tsv \
  --outdir results/my_run
```

Species addition and taxonomy both require the relevant reference files. For community alpha/beta/depth without taxonomy, omit the taxonomy options; composition is then unavailable. PERMANOVA runs only if `--sample_metadata` is supplied. Resume a Nextflow run with `-resume`:

```bash
nextflow run main.nf -resume --sample_sheet samplesheet.csv --primer_mode none --outdir results/my_run
```

### Parameters

| Parameter | Default | Purpose |
|---|---|---|
| `--sample_sheet` | Required | Paired-read CSV |
| `--outdir` | `results` | Published results directory |
| `--primer_mode` | `paired` | `paired` or `none` |
| `--primer_fwd`, `--primer_rev` | unset | Required in paired mode |
| `--trim_error_rate`, `--trim_min_overlap`, `--trim_min_length`, `--discard_untrimmed` | `0.1`, `3`, `50`, `true` | Cutadapt controls |
| `--run_dada2` | `true` | Enable DADA2 inference |
| `--dada2_trunc_len_f`, `--dada2_trunc_len_r` | `0`, `0` | Fixed truncation lengths; zero disables fixed-length truncation |
| `--dada2_max_ee_f`, `--dada2_max_ee_r` | `2.0`, `2.0` | Maximum expected errors |
| `--dada2_trunc_q`, `--dada2_max_n`, `--dada2_min_len`, `--dada2_rm_phix` | `2`, `0`, `50`, `true` | DADA2 filter settings |
| `--dada2_learn_nbases`, `--dada2_pool` | `1000000`, `false` | Error learning and pooling (`false`, `true`, or `pseudo`) |
| `--dada2_min_overlap`, `--dada2_max_mismatch` | `12`, `0` | Paired-read merge settings |
| `--dada2_chimera_method` | `consensus` | Chimera method (`consensus`, `pooled`, `per-sample`) |
| `--run_taxonomy`, `--taxonomy_add_species` | `false`, `false` | Taxonomy and optional species addition |
| `--silva_version`, `--silva_genus_ref`, `--silva_species_ref` | `144`, unset, unset | Reference version and optional explicit paths |
| `--taxonomy_min_boot`, `--taxonomy_tryrc` | `50`, `true` | DADA2 classifier settings |
| `--run_community_analysis` | `false` | Enable community analyses |
| `--run_phylogenetic_analysis` | `false` | Align nonchimeric ASV sequences and infer an unrooted Newick tree |
| `--sample_metadata`, `--taxonomy_table` | unset, unset | Optional metadata and external taxonomy TSV |
| `--composition_top_n`, `--permanova_nperm`, `--permanova_seed` | `10`, `999`, `123` | Composition and PERMANOVA settings |
| `--enable_dashboard`, `--dashboard_port`, `--dashboard_bind_address` | `false`, `8501`, unset | Launch dashboard; bind address defaults to Tailscale IPv4 if available, otherwise loopback |

The Nextflow configuration enables Singularity-compatible container execution with auto mounts and sets per-process CPU, memory, retry and time limits. Trace, report and timeline artifacts are enabled under `<outdir>/.asvflow_dashboard/artifacts/<invocation-id>/`.

## ASVFlow Live dashboard

The Streamlit dashboard selects from runs recorded by ASVFlow and follows newly written outputs for the selected run. It supports multiple recorded runs, with one run selected at a time. Pages are Home/overview, QC Results, DADA2 Results, Taxonomy, Community Analysis, and Sample Explorer. Available views include task summaries and traces, FastQC/MultiQC results, read tracking, chimera metrics, ASV tables, taxonomy tables, diversity, composition, sequencing depth, and PERMANOVA results when those outputs exist. It is an output viewer and does not change parameters or launch analysis.

Launch it with the pipeline:

```bash
nextflow run main.nf --sample_sheet samplesheet.csv --primer_mode none \
  --enable_dashboard true --dashboard_port 8501 --outdir results/my_run
```

Or start it after a run:

```bash
bin/launch_dashboard.sh results/my_run 8501
```

The launcher uses `tools/asvflow-dashboard.sif` by default. Its optional third argument overrides the image path. If Tailscale is available, the launcher binds its IPv4 address; otherwise it binds loopback. Set `DASHBOARD_BIND_ADDRESS` or use `--dashboard_bind_address` to choose an address. A port conflict is reported; the launcher does not automatically increment the requested port. Stop an instance with:

```bash
bin/stop_dashboard.sh results/my_run
```

Dashboard ownership and runtime state are tracked under `${XDG_STATE_HOME:-~/.local/state}/asvflow/dashboard` (or `ASVFLOW_STATE_DIR` when set), with compatibility state in the selected output directory. The Nextflow startup panel reports the selected analysis configuration and dashboard status. The completion panel reports final workflow status and output location. The ANSI ASVFlow terminal branding currently displays `v1.0.0`; that display string is not evidence of a separately managed software release version.

## Outputs

Directories below are published under the selected `--outdir`; individual files depend on enabled stages and whether a plot can be produced.

```text
<outdir>/
├── qc/raw/                         # FastQC reports and MultiQC report/data
├── qc/trimmed/                     # Post-primer-stage FastQC and MultiQC
├── trimmed/                        # Cutadapt reads (when primer mode is paired)
├── trimming_reports/               # Cutadapt JSON and text reports
├── dada2/
│   ├── qc/                          # R1/R2 quality profiles
│   ├── filtered/                    # Filtered reads
│   ├── error_models/                # Error models and plots
│   ├── dereplicated/                # Per-sample dereplication objects
│   ├── inferred/                    # Per-sample inferred objects
│   ├── merged/                      # Merged objects and merge statistics
│   ├── seqtab/                      # Combined sequence table
│   └── final/                       # Non-chimeric table, FASTA, read tracking, chimera stats
├── taxonomy/                        # Taxonomy table/statistics; species outputs if enabled
├── community/                       # Prepared inputs, diversity, composition, depth, PERMANOVA
├── phylogeny/                       # Representative FASTA, ID map, alignment, Newick tree and status
└── .asvflow_dashboard/
    ├── artifacts/<invocation-id>/   # Nextflow trace, report and timeline
    └── runs/                        # Run metadata used by dashboard selection
```

Community outputs include `alpha_diversity.tsv` and PDF, Bray-Curtis/Jaccard PCoA TSV/PDF and statistics, `sequencing_depth.tsv` and related statistics/rarefaction files, composition tables/plots when taxonomy is available, and PERMANOVA results when metadata is provided. The dashboard state location may be in the user's state directory as described above.

When enabled, `phylogeny/` contains `asv_sequences.fasta`, `asv_sequence_ids.tsv`, `asv_alignment.fasta`, and `phylogeny_status.txt`. `asv_tree.nwk` is also produced when there is at least one sequence: one ASV gets a valid single-leaf Newick string, while two or more get a FastTree result. Empty input is reported in the status file and produces no tree. The dashboard displays these states instead of drawing them as an inferred multi-ASV tree.

## Tests and synthetic data

The synthetic generator writes deterministic paired-end 16S-like FASTQ data, refreshes both sample sheets, and creates the community metadata fixture. Generate the fixtures from the repository root:

```bash
python3 test/generate_synthetic_data.py
```

Run the retained validation and dashboard tests:

```bash
./test/test_validation.sh
./test/dashboard/run_all_tests.sh
```

The validation script also regenerates synthetic data. Dashboard tests require Python 3, a C compiler, Apptainer or Singularity, and `tools/asvflow-dashboard.sif`. These scripts validate input handling and dashboard lifecycle/output behavior; they do not run or validate the complete Nextflow workflow.

## Scope

- The workflow accepts paired-end reads and provides a 16S-oriented DADA2 analysis. ITS support is not verified and should not be assumed.
- Taxonomy uses DADA2-compatible SILVA references; other taxonomy databases are not configured by the workflow.
- Faith's PD and UniFrac are not generated.
- Taxonomy, species addition, community analysis, and the dashboard are optional stages/features as described above.

## References

- Callahan BJ, McMurdie PJ, Rosen MJ, et al. (2016). DADA2: High-resolution sample inference from Illumina amplicon data. *Nature Methods* 13:581–583. doi:10.1038/nmeth.3869.
- Quast C, Pruesse E, Yilmaz P, et al. (2013). The SILVA ribosomal RNA gene database project. *Nucleic Acids Research* 41:D590–D596. doi:10.1093/nar/gks1219.
- Di Tommaso P, Chatzou M, Floden EW, et al. (2017). Nextflow enables reproducible computational workflows. *Nature Biotechnology* 35:316–319. doi:10.1038/nbt.3820.
