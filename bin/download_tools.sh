#!/usr/bin/env bash

set -uo pipefail

# Resolve project root independently of the current working directory.
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLS_DIR="${PROJECT_DIR}/tools"

# Prefer Singularity if available; otherwise use Apptainer.
if command -v singularity >/dev/null 2>&1; then
    RUNTIME="singularity"
elif command -v apptainer >/dev/null 2>&1; then
    RUNTIME="apptainer"
else
    echo "ERROR: Singularity or Apptainer is required."
    exit 1
fi

mkdir -p "$TOOLS_DIR"

# SIF filename -> OCI image reference
declare -a IMAGES=(
    "asvflow-dada2.sif|quay.io/biocontainers/bioconductor-dada2:1.38.0--r45ha27e39d_0"
    "asvflow-trim.sif|quay.io/biocontainers/cutadapt:5.2--py312hfabe715_2"
    "asvflow-qc.sif|quay.io/biocontainers/fastqc:0.13.0--hdfd78af_0"
    "asvflow-report.sif|multiqc/multiqc"
    "asvflow-seqkit.sif|quay.io/biocontainers/seqkit:2.14.0--hb192632_0"
    "asvflow-mafft.sif|quay.io/biocontainers/mafft:7.221--0"
    "asvflow-fasttree.sif|quay.io/biocontainers/fasttree:2.2.0--h7b50bb2_1"
)

downloaded=()
skipped=()
failed=()

echo "ASVFlow container setup"
echo "Runtime: $RUNTIME"
echo "Destination: $TOOLS_DIR"
echo

for entry in "${IMAGES[@]}"; do
    filename="${entry%%|*}"
    image="${entry#*|}"
    destination="${TOOLS_DIR}/${filename}"
    temporary="${destination}.partial.$$"

    if [[ -s "$destination" ]]; then
        echo "[SKIP] $filename already exists"
        skipped+=("$filename")
        continue
    fi

    echo "[PULL] $image"
    rm -f "$temporary"

    if "$RUNTIME" pull "$temporary" "docker://${image}" &&
       [[ -s "$temporary" ]]; then
        mv "$temporary" "$destination"
        echo "[OK]   $filename"
        downloaded+=("$filename")
    else
        rm -f "$temporary"
        echo "[FAIL] $filename"
        failed+=("$filename")
    fi

    echo
done

echo "========== ASVFlow setup summary =========="
echo "Downloaded: ${#downloaded[@]}"
echo "Skipped:    ${#skipped[@]}"
echo "Failed:     ${#failed[@]}"

if ((${#failed[@]} > 0)); then
    echo
    printf 'Failed images: %s\n' "${failed[*]}"
    exit 1
fi

echo
echo "All requested containers are available in: $TOOLS_DIR"
