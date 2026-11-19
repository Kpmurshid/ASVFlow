# ASVFlow

A Nextflow pipeline for amplicon sequencing analysis using DADA2, from raw paired-end reads to amplicon sequence variants (ASVs), taxonomy assignment, and community analysis.

## Features

- **Quality Control**: FastQC and MultiQC reporting for raw and trimmed reads
- **Primer Trimming**: Cutadapt-based adapter and primer removal
- **DADA2 ASV Inference**: Complete DADA2 workflow with error modeling, denoising, merging, and chimera removal
- **Taxonomy Assignment**: SILVA-based taxonomic classification using DADA2's naive Bayesian classifier
- **Community Analysis**: Alpha diversity, beta diversity, taxonomic composition, and PERMANOVA (optional)
- **ASVFlow Live Dashboard**: Streamlit-based web interface for run monitoring and interactive result visualization
- **Containerized**: All dependencies packaged in Singularity/Apptainer containers
- **Reproducible**: Fully parameterized workflow with version-controlled container definitions

## Pipeline Overview

```
Raw FASTQ reads (paired-end)
    ↓
Quality Control (FastQC/MultiQC)
    ↓
Primer Trimming (Cutadapt) [optional]
    ↓
Quality Filtering (DADA2 filterAndTrim)
    ↓
Error Model Learning (DADA2 learnErrors)
    ↓
Dereplication (DADA2 derepFastq)
    ↓
ASV Inference (DADA2 dada)
    ↓
Merge Paired Reads (DADA2 mergePairs)
    ↓
Sequence Table Construction (DADA2 makeSequenceTable)
    ↓
Chimera Removal (DADA2 removeBimeraDenovo)
    ↓
Taxonomy Assignment (DADA2 assignTaxonomy) [optional]
    ↓
Species Addition (DADA2 addSpecies) [optional]
    ↓
Community Analysis (phyloseq/vegan) [optional]
    ↓
ASVFlow Live Dashboard [optional]
```

## System Requirements

### Prerequisites

- **Java** ≥ 11
- **Nextflow** ≥ 21.04.0
- **Singularity** ≥ 3.7 or **Apptainer** ≥ 1.0
- **curl** (for downloading reference databases)
- **Bash** ≥ 4.0

### Computational Resources

Minimum recommended:
- 8 CPU cores
- 16 GB RAM
- 50 GB disk space (for containers and databases)

For large datasets (>100 samples):
- 16+ CPU cores
- 32+ GB RAM

## Installation

### 1. Clone the Repository

```bash
git clone https://github.com/Kpmurshid/ASVFlow.git
cd ASVFlow
```

### 2. Install Nextflow

ASVFlow supports **Nextflow 21.04.0 or newer**. Install Java 11 or newer, then install Nextflow:

```bash
curl -s https://get.nextflow.io | bash
sudo install nextflow /usr/local/bin/nextflow
nextflow -version
```

If you install Nextflow elsewhere, ensure its location is on `PATH` before running ASVFlow.

### 3. Download Container Images and Reference Databases

Run the setup script to download all required Apptainer/Singularity container images and SILVA reference files:

```bash
./bin/download_tools.sh
```

This script will:
- Pull 10 Apptainer/Singularity container images from public registries (Biocontainers, Docker Hub)
- Download SILVA v144 reference databases from arb-silva.de
- Verify MD5 checksums and gzip integrity for downloaded SILVA database files
- Pull container images from their configured registry references
- Skip already-downloaded files

**Container sources:**
- `asvflow-dada2.sif` → `docker://quay.io/biocontainers/bioconductor-dada2:1.38.0--r45ha27e39d_0`
- `asvflow-trim.sif` → `docker://quay.io/biocontainers/cutadapt:5.2--py312hfabe715_2`
- `asvflow-qc.sif` → `docker://quay.io/biocontainers/fastqc:0.13.0--hdfd78af_0`
- `asvflow-multiqc.sif` → `docker://multiqc/multiqc:v1.35`
- `asvflow-stats.sif` → `oras://registry-1.docker.io/kpmurshid/asvflow-stats:bioc-3.22-r4.5.2`
- `asvflow-report.sif` → `oras://registry-1.docker.io/kpmurshid/asvflow-report:python-3.12`
- `asvflow-dashboard.sif` → `oras://registry-1.docker.io/kpmurshid/asvflow-dashboard:streamlit-1.35.0-numpy-1.26.4-pyarrow-16.1.0`
- Additional tools: seqkit, mafft, fasttree from Biocontainers

**Database downloads:**
- SILVA v144 training sets (genus and species-level)
- SILVA v144 species assignment database

**Total download size:** ~3.7 GB (containers: ~3.2 GB, databases: ~526 MB)

### 4. Verify Installation

```bash
./bin/validate_environment.sh
```

This checks that expected container images are present and their tools can run. It also checks available FASTQ files under `data/`; reference databases are required when taxonomy is enabled.

## Offline Usage

Once containers and databases are downloaded, the pipeline can run offline. All dependencies are self-contained in the Apptainer/Singularity images, and reference databases are stored locally in `databases/silva/144/`.

## Input Data

### Samplesheet Format

Create a CSV file with the following columns:

```csv
sample_id,fastq_1,fastq_2
Sample1,/path/to/Sample1_R1.fastq.gz,/path/to/Sample1_R2.fastq.gz
Sample2,/path/to/Sample2_R1.fastq.gz,/path/to/Sample2_R2.fastq.gz
Sample3,/path/to/Sample3_R1.fastq.gz,/path/to/Sample3_R2.fastq.gz
```

**Requirements:**
- Header line required: `sample_id,fastq_1,fastq_2`
- `sample_id`: Unique sample identifier (no spaces or special characters except underscore/hyphen)
- `fastq_1`: Absolute or relative path to forward read file
- `fastq_2`: Absolute or relative path to reverse read file
- Files must be gzipped FASTQ format (`.fastq.gz` or `.fq.gz`)

### Validate Samplesheet

```bash
./bin/validate_samplesheet.py samplesheet.csv
```

## Pipeline Configuration

### Essential Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `--sample_sheet` | *required* | Path to samplesheet CSV |
| `--outdir` | `results` | Output directory |
| `--primer_fwd` | *required if primer_mode='paired'* | Forward primer sequence (5'→3') |
| `--primer_rev` | *required if primer_mode='paired'* | Reverse primer sequence (5'→3') |

### Quality Filtering (DADA2)

| Parameter | Default | Description |
|-----------|---------|-------------|
| `--dada2_trunc_len_f` | `0` | Truncate R1 reads to this length (0 = no truncation) |
| `--dada2_trunc_len_r` | `0` | Truncate R2 reads to this length (0 = no truncation) |
| `--dada2_max_ee_f` | `2.0` | Maximum expected errors for R1 |
| `--dada2_max_ee_r` | `2.0` | Maximum expected errors for R2 |
| `--dada2_trunc_q` | `2` | Truncate reads at first base with quality ≤ Q |
| `--dada2_min_len` | `50` | Minimum read length after filtering |
| `--dada2_rm_phix` | `true` | Remove PhiX spike-in sequences |

### ASV Inference (DADA2)

| Parameter | Default | Description |
|-----------|---------|-------------|
| `--dada2_pool` | `false` | Pooling mode: `false`, `true`, or `'pseudo'` |
| `--dada2_min_overlap` | `12` | Minimum overlap for merging paired reads |
| `--dada2_max_mismatch` | `0` | Maximum mismatches in overlap region |
| `--dada2_chimera_method` | `'consensus'` | Chimera detection: `'consensus'`, `'pooled'`, `'per-sample'` |

### Taxonomy Assignment

| Parameter | Default | Description |
|-----------|---------|-------------|
| `--run_taxonomy` | `false` | Enable taxonomy assignment |
| `--taxonomy_add_species` | `false` | Add species-level classification |
| `--taxonomy_min_boot` | `50` | Minimum bootstrap confidence (0-100) |
| `--silva_version` | `144` | SILVA database version |

### Community Analysis

| Parameter | Default | Description |
|-----------|---------|-------------|
| `--run_community_analysis` | `false` | Enable community analysis |
| `--sample_metadata` | `null` | Path to sample metadata CSV (optional) |
| `--composition_top_n` | `10` | Number of top taxa to display |
| `--permanova_nperm` | `999` | Number of PERMANOVA permutations |

### Dashboard

| Parameter | Default | Description |
|-----------|---------|-------------|
| `--enable_dashboard` | `false` | Launch ASVFlow Live dashboard during pipeline execution |
| `--dashboard_port` | `8501` | Dashboard port (auto-increments if in use) |

## Running the Pipeline

### Basic Run (QC + DADA2 only)

```bash
nextflow run main.nf \
  --sample_sheet samplesheet.csv \
  --primer_fwd GTGCCAGCMGCCGCGGTAA \
  --primer_rev GGACTACHVGGGTWTCTAAT \
  --outdir results/my_run
```

### Run with Taxonomy Assignment

```bash
nextflow run main.nf \
  --sample_sheet samplesheet.csv \
  --primer_fwd GTGCCAGCMGCCGCGGTAA \
  --primer_rev GGACTACHVGGGTWTCTAAT \
  --run_taxonomy true \
  --taxonomy_add_species true \
  --outdir results/my_run
```

### Run with Community Analysis

```bash
nextflow run main.nf \
  --sample_sheet samplesheet.csv \
  --primer_fwd GTGCCAGCMGCCGCGGTAA \
  --primer_rev GGACTACHVGGGTWTCTAAT \
  --run_taxonomy true \
  --run_community_analysis true \
  --sample_metadata metadata.csv \
  --outdir results/my_run
```

**Sample metadata format:**
```csv
sample_id,group,timepoint,replicate
Sample1,Control,T0,1
Sample2,Treatment,T0,1
Sample3,Control,T1,1
```

### Run with Live Dashboard

```bash
nextflow run main.nf \
  --sample_sheet samplesheet.csv \
  --primer_fwd GTGCCAGCMGCCGCGGTAA \
  --primer_rev GGACTACHVGGGTWTCTAAT \
  --run_taxonomy true \
  --enable_dashboard true \
  --outdir results/my_run
```

The dashboard will launch automatically and display the URL in the terminal.

### Resume Failed Runs

```bash
nextflow run main.nf -resume --sample_sheet samplesheet.csv [other options]
```

## ASVFlow Live Dashboard

The ASVFlow Live dashboard provides run monitoring and interactive visualization of completed pipeline outputs.

### Dashboard Host Requirements

- Linux with `/proc` mounted and a kernel that supports pidfds (Linux 5.1 or newer)
- Bash 4 or newer, Python 3.9 or newer, `setsid`, GNU `stat`, and `curl`
- Apptainer 1.0 or newer or Singularity 3.7 or newer; the launcher uses Apptainer when both runtimes are installed
- `ss` or `lsof` is recommended for reliable port-conflict detection

Dashboard process ownership checks use Python's `os.pidfd_open` and `signal.pidfd_send_signal` APIs. Dashboard launch and stop rely on Linux process metadata and are not supported on non-Linux systems.

When `tailscale` is available, the launcher binds to its IPv4 address; otherwise it binds to `127.0.0.1`. Set `DASHBOARD_BIND_ADDRESS=127.0.0.1` to force loopback, or use `--dashboard_bind_address` when starting through Nextflow.

### Features

- **Run Overview**: Pipeline execution status and task summary
- **QC Results**: Interactive FastQC and MultiQC reports
- **DADA2 Results**: ASV table statistics, read tracking, chimera removal metrics
- **Taxonomy**: Taxonomic classification statistics and interactive tables
- **Community Analysis**: Alpha/beta diversity plots, taxonomic composition, PERMANOVA results
- **Sample Explorer**: Per-sample quality profiles and detailed metrics

### Launching the Dashboard

**During pipeline execution:**
```bash
nextflow run main.nf --enable_dashboard true --sample_sheet samplesheet.csv [...]
```

**After pipeline completion:**
```bash
./bin/launch_dashboard.sh results/my_run 8501
```

The dashboard URL will be displayed in the terminal (typically `http://localhost:8501`).

### Dashboard Management


**Stop the dashboard:**
```bash
./bin/stop_dashboard.sh results/my_run
```

**Multiple concurrent dashboards:**
Each output directory can have its own dashboard instance. Ports auto-increment if conflicts occur (8501 → 8502 → 8503...).

### Dashboard Limitations

- The dashboard provides **run monitoring** and displays completed task outputs, not live task-level execution tracking
- Task status reflects tasks that have completed, failed, or been cached
- Community analysis visualizations require `--run_community_analysis true` during pipeline execution
- PDF reports must be downloaded; inline viewing is not supported

## Output Directory Structure

```
results/
├── qc/
│   ├── raw/                      # FastQC reports for raw reads
│   └── trimmed/                  # FastQC reports for trimmed reads
├── trimmed/                      # Trimmed FASTQ files
├── trimming_reports/             # Cutadapt trimming logs
├── dada2/
│   ├── qc/
│   │   └── quality_profiles.pdf  # Quality score profiles
│   ├── filtered/                 # Quality-filtered reads
│   ├── dereplicated/             # Dereplicated sequences
│   ├── error_models/             # Error rate plots
│   ├── inferred/                 # Denoised ASVs per sample
│   ├── merged/                   # Merged paired reads
│   ├── seqtab/                   # Sample-specific sequence tables
│   └── final/
│       ├── seqtab_nochim.tsv     # Final ASV table (samples × ASVs)
│       ├── seqtab_nochim.fasta   # ASV representative sequences
│       ├── track_reads.tsv       # Read counts through pipeline
│       └── chimera_stats.tsv     # Chimera removal statistics
├── taxonomy/
│   ├── taxonomy.tsv              # Taxonomic assignments (ASV_ID → Kingdom...Genus/Species)
│   └── taxonomy_stats.tsv        # Classification statistics
└── community/
    ├── alpha_diversity.tsv       # Shannon, Simpson, Chao1 per sample
    ├── alpha_diversity.pdf       # Alpha diversity boxplots
    ├── beta_diversity_pcoa.pdf   # PCoA ordination plots
    ├── composition_*.pdf         # Taxonomic composition bar charts
    ├── sequencing_depth.pdf      # Rarefaction curves
    └── permanova_results.txt     # PERMANOVA test results
```

## Testing and Validation

From the repository root, generate the synthetic FASTQ files and sample sheets, then run the retained validation tests:

```bash
python3 test/generate_synthetic_data.py
./test/test_validation.sh
./test/dashboard/run_all_tests.sh
```

`test/test_validation.sh` also runs the synthetic data generator, so it can be run directly after cloning. The generator recreates the ignored FASTQ files referenced by the two retained sample sheets. The dashboard runner executes lifecycle, process identity, and incremental output availability tests; it requires Python 3, a C compiler, Apptainer or Singularity, and `tools/asvflow-dashboard.sif`.

### Validation Status

The pipeline has been validated using:
- ✅ Stub execution across all modules
- ✅ Synthetic test datasets
- ✅ Edge case fixtures for error handling
- ⚠️ Full end-to-end validation with real sequencing data pending

## Troubleshooting

### Container Issues

**Problem:** Apptainer/Singularity not found
```bash
# Install Apptainer (newer alternative to Singularity)
# On Ubuntu/Debian:
sudo apt install apptainer

# Or install Singularity from source:
# https://github.com/sylabs/singularity
```

**Problem:** Container pull fails
```bash
# Re-run download script (resumes partial downloads)
./bin/download_tools.sh

# Check network connectivity and registry availability
apptainer pull fastqc.sif docker://quay.io/biocontainers/fastqc:0.13.0--hdfd78af_0
```

### Pipeline Errors

**Problem:** `Empty sample_id in samplesheet`
- Check samplesheet formatting (CSV with header line)
- Ensure no blank lines or empty sample_id values

**Problem:** `primer_mode='paired' requires --primer_fwd and --primer_rev`
- Provide both primer sequences or set `--primer_mode none`

**Problem:** Memory errors during DADA2 error learning
- Reduce `--dada2_learn_nbases` (default: 1,000,000)
- Increase memory allocation in `nextflow.config`

**Problem:** Low ASV recovery
- Adjust quality filtering thresholds (`--dada2_max_ee_f`, `--dada2_max_ee_r`)
- Check quality profiles: `results/dada2/qc/quality_profiles.pdf`
- Consider using pseudo-pooling: `--dada2_pool pseudo`

### Dashboard Issues

**Problem:** Dashboard won't start
```bash
# Check if port is in use
netstat -tuln | grep 8501

# Use a different port
./bin/launch_dashboard.sh results/my_run 8502

# Check dashboard logs
cat results/my_run/.asvflow_dashboard/dashboard.log
```

**Problem:** "Community analysis not available"
- Rerun pipeline with `--run_community_analysis true`
- Ensure taxonomy was enabled (`--run_taxonomy true`)

**Problem:** Multiple dashboard instances conflict
- Each output directory has independent dashboard state
- Use `./bin/stop_dashboard.sh <output_dir>` to stop specific instances

## Known Limitations

### Pipeline

- **Paired-end only**: Single-end reads are not supported
- **Illumina-specific**: Optimized for Illumina sequencing data
- **SILVA-only**: Other taxonomy databases (Greengenes, UNITE) not supported without modification
- **No ITS support**: Pipeline designed for 16S/18S rRNA gene amplicons; ITS region requires different merging strategy

### Community Analysis

- **Optional module**: Must be explicitly enabled with `--run_community_analysis true`
- **Requires taxonomy**: Community analysis depends on taxonomic classifications
- **No phylogenetic diversity**: Tree-based metrics (UniFrac) not implemented
- **PERMANOVA**: Requires sample metadata with categorical grouping variable

### Dashboard

- **Post-execution visualization**: Dashboard displays completed pipeline outputs, not live task-level monitoring
- **No edit capabilities**: Read-only interface; cannot modify parameters or rerun analyses
- **Container-based**: Requires Singularity/Apptainer runtime

### Validation

- **Limited real data testing**: Primary validation used synthetic and stub datasets
- **No benchmark datasets**: Performance not validated against established mock communities

## Citation

If you use ASVFlow in your research, please cite:

**DADA2:**
Callahan BJ, McMurdie PJ, Rosen MJ, et al. (2016) DADA2: High-resolution sample inference from Illumina amplicon data. *Nature Methods* 13:581–583. doi:10.1038/nmeth.3869

**SILVA:**
Quast C, Pruesse E, Yilmaz P, et al. (2013) The SILVA ribosomal RNA gene database project: improved data processing and web-based tools. *Nucleic Acids Research* 41:D590–D596. doi:10.1093/nar/gks1219

**Nextflow:**
Di Tommaso P, Chatzou M, Floden EW, et al. (2017) Nextflow enables reproducible computational workflows. *Nature Biotechnology* 35:316–319. doi:10.1038/nbt.3820

## License

This project does not currently specify a license. Container images and reference databases are subject to their respective licenses:
- DADA2: LGPL-2.1
- SILVA: Academic use only (commercial use requires license)
- Cutadapt: MIT
- FastQC: GPL v3
- MultiQC: GPL v3

## Contact and Support

For issues, questions, or contributions, please open an issue on the GitHub repository.

## Acknowledgments

ASVFlow integrates best-practice bioinformatics tools:
- DADA2 (Callahan et al.)
- Cutadapt (Martin, 2011)
- FastQC (Andrews, 2010)
- MultiQC (Ewels et al., 2016)
- phyloseq (McMurdie & Holmes, 2013)
- vegan (Oksanen et al.)
- Streamlit (Streamlit Inc.)
