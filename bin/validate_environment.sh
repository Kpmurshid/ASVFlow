#!/usr/bin/env bash

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLS="$ROOT/tools"
DATA="$ROOT/data"

RUNTIME="$(command -v apptainer || command -v singularity || true)"

if [[ -z "$RUNTIME" ]]; then
    echo "ERROR: Singularity/Apptainer not found"
    exit 1
fi

passed=0
failed=0

check() {
    local name="$1"
    shift

    printf "%-18s" "$name"

    if output=$("$@" 2>&1); then
        echo "[PASS] $output"
        ((passed+=1))
    else
        echo "[FAIL]"
        echo "$output"
        ((failed+=1))
    fi
}

echo "======================================"
echo "       ASVFlow Environment Check"
echo "======================================"
echo "Runtime: $("$RUNTIME" --version 2>&1 | head -n 1)"
echo

echo "---- Container validation ----"

check "Statistics / R" "$RUNTIME" exec "$TOOLS/asvflow-stats.sif" \
    Rscript -e '
    packages <- c("vegan", "phyloseq", "ape", "picante", "ggplot2", "stringr")
    for (p in packages) {
        loadNamespace(p)
        cat(p, as.character(packageVersion(p)), "|")
    }
    cat("\n")
    '

check "Cutadapt" "$RUNTIME" exec "$TOOLS/asvflow-trim.sif" cutadapt --version

check "FastQC" "$RUNTIME" exec "$TOOLS/asvflow-qc.sif" fastqc --version

check "MultiQC" "$RUNTIME" exec "$TOOLS/asvflow-multiqc.sif" multiqc --version

check "SeqKit" "$RUNTIME" exec "$TOOLS/asvflow-seqkit.sif" seqkit version

check "MAFFT" "$RUNTIME" exec "$TOOLS/asvflow-mafft.sif" mafft --version

check "FastTree" "$RUNTIME" exec "$TOOLS/asvflow-fasttree.sif" \
    bash -c 'command -v FastTree || command -v fasttree'

check "Python / Report" "$RUNTIME" exec "$TOOLS/asvflow-report.sif" \
    python -c '
import importlib.metadata as m
import numpy, pandas, scipy, matplotlib, seaborn, plotly, jinja2, Bio

for p in ["numpy", "pandas", "scipy", "matplotlib", "seaborn", "plotly", "jinja2", "biopython"]:
    print(f"{p} {m.version(p)}", end=" | ")
print()
'
check "Dashboard" "$RUNTIME" exec "$TOOLS/asvflow-dashboard.sif" \
    python -c '
import importlib.metadata as m
import streamlit, numpy, pandas, pyarrow, plotly, watchdog

for p in ["streamlit", "numpy", "pandas", "pyarrow", "plotly", "watchdog"]:
    print(f"{p} {m.version(p)}", end=" | ")
print()
'

echo
echo "---- FASTQ integrity ----"

for fq in "$DATA"/*.fastq.gz; do
    [[ -e "$fq" ]] || continue

    check "$(basename "$fq")" gzip -t "$fq"
done

echo
echo "---- Paired-end read statistics ----"

R1_FILES=("$DATA"/*_R1_*.fastq.gz)

for r1 in "${R1_FILES[@]}"; do
    [[ -e "$r1" ]] || continue

    r2="${r1/_R1_/_R2_}"

    if [[ ! -f "$r2" ]]; then
        echo "[FAIL] Missing mate for $(basename "$r1"): $(basename "$r2")"
        ((failed+=1))
        continue
    fi

    echo
    echo "Sample: $(basename "$r1" | sed 's/_L[0-9]*_R1_.*//')"

    "$RUNTIME" exec "$TOOLS/asvflow-seqkit.sif" \
        seqkit stats "$r1" "$r2"
done

echo
echo "======================================"
echo "Passed: $passed"
echo "Failed: $failed"
echo "======================================"

if (( failed > 0 )); then
    exit 1
fi
