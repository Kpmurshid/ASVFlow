#!/usr/bin/env bash

set -uo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLS_DIR="$PROJECT_DIR/tools"
DB_DIR="$PROJECT_DIR/databases/silva/144"

RUNTIME="$(command -v singularity || command -v apptainer || true)"

if [[ -z "$RUNTIME" ]]; then
    echo "ERROR: Singularity or Apptainer is required."
    exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
    echo "ERROR: curl is required."
    exit 1
fi

mkdir -p "$TOOLS_DIR" "$DB_DIR"

failed=0
downloaded=0
skipped=0

IMAGES=(
    "asvflow-dada2.sif|docker://quay.io/biocontainers/bioconductor-dada2:1.38.0--r45ha27e39d_0"
    "asvflow-trim.sif|docker://quay.io/biocontainers/cutadapt:5.2--py312hfabe715_2"
    "asvflow-qc.sif|docker://quay.io/biocontainers/fastqc:0.13.0--hdfd78af_0"
    "asvflow-multiqc.sif|docker://multiqc/multiqc:v1.35"
    "asvflow-report.sif|oras://registry-1.docker.io/kpmurshid/asvflow-report:python-3.12"
    "asvflow-seqkit.sif|docker://quay.io/biocontainers/seqkit:2.14.0--hb192632_0"
    "asvflow-mafft.sif|docker://quay.io/biocontainers/mafft:7.221--0"
    "asvflow-fasttree.sif|docker://quay.io/biocontainers/fasttree:2.2.0--h7b50bb2_1"
    "asvflow-stats.sif|oras://registry-1.docker.io/kpmurshid/asvflow-stats:bioc-3.22-r4.5.2"
    "asvflow-dashboard.sif|oras://registry-1.docker.io/kpmurshid/asvflow-dashboard:streamlit-1.35.0-numpy-1.26.4-pyarrow-16.1.0"
)

SILVA_BASE="https://www.arb-silva.de/fileadmin/silva_databases/current/DADA2/1.36.0/SSU"

SILVA_FILES=(
    "silva_nr99_v144_toGenus_trainset.fa.gz"
    "silva_nr99_v144_toSpecies_trainset.fa.gz"
    "silva_v144_assignSpecies.fa.gz"
)

echo "======================================"
echo "          ASVFlow Setup"
echo "======================================"
echo "Runtime: $RUNTIME"
echo

echo "---- Container images ----"

for entry in "${IMAGES[@]}"; do
    filename="${entry%%|*}"
    image="${entry#*|}"
    destination="$TOOLS_DIR/$filename"
    temporary="$destination.partial"

    if [[ -s "$destination" ]]; then
        echo "[SKIP] $filename"
        ((skipped+=1))
        continue
    fi

    echo "[PULL] $image"

    rm -f "$temporary"

    if "$RUNTIME" pull "$temporary" "$image" &&
       [[ -s "$temporary" ]]; then
        mv "$temporary" "$destination"
        echo "[OK] $filename"
        ((downloaded+=1))
    else
        rm -f "$temporary"
        echo "[FAIL] $filename"
        ((failed+=1))
    fi
done

echo
echo "---- SILVA v144 reference database ----"

for filename in "${SILVA_FILES[@]}"; do
    destination="$DB_DIR/$filename"
    checksum="$DB_DIR/$filename.md5"
    temporary="$destination.partial"
    checksum_tmp="$checksum.partial"

    echo "[CHECK] $filename"

    # Download checksum first.
    if [[ ! -s "$checksum" ]]; then
        if ! curl -fL --retry 3 --retry-all-errors \
            "$SILVA_BASE/$filename.md5" \
            -o "$checksum_tmp"; then
            rm -f "$checksum_tmp"
            echo "[FAIL] Checksum download: $filename"
            ((failed+=1))
            continue
        fi
        mv "$checksum_tmp" "$checksum"
    fi

    expected="$(awk 'NR==1 {print $1}' "$checksum")"

    if [[ ! "$expected" =~ ^[[:xdigit:]]{32}$ ]]; then
        echo "[FAIL] Invalid checksum: $filename"
        ((failed+=1))
        continue
    fi

    # Validate an existing completed file.
    if [[ -s "$destination" ]]; then
        actual="$(md5sum "$destination" | awk '{print $1}')"

        if [[ "$actual" == "$expected" ]] && gzip -t "$destination"; then
            echo "[SKIP] $filename (verified)"
            ((skipped+=1))
            continue
        fi

        echo "[WARN] Existing file failed verification; downloading again"
        rm -f "$destination"
    fi

    echo "[DOWNLOAD] $filename (resumable)"

    # Keep the same partial file between runs.
    if ! curl -fL --retry 5 --retry-all-errors --retry-delay 2 \
        -C - "$SILVA_BASE/$filename" \
        -o "$temporary"; then
        echo "[FAIL] Download interrupted: $filename (partial retained)"
        ((failed+=1))
        continue
    fi

    actual="$(md5sum "$temporary" | awk '{print $1}')"

    if [[ "$actual" != "$expected" ]]; then
        echo "[FAIL] MD5 verification: $filename (partial retained)"
        ((failed+=1))
        continue
    fi

    if ! gzip -t "$temporary"; then
        echo "[FAIL] Gzip integrity: $filename"
        ((failed+=1))
        continue
    fi

    mv "$temporary" "$destination"

    echo "[OK] $filename (MD5 and gzip verified)"
    ((downloaded+=1))
done

echo
echo "======================================"
echo "          Setup Summary"
echo "======================================"
echo "Downloaded: $downloaded"
echo "Skipped:    $skipped"
echo "Failed:     $failed"

if (( failed > 0 )); then
    echo "Setup completed with errors."
    exit 1
fi

echo "All requested files are available."
