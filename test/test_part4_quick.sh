#!/bin/bash
set -euo pipefail

echo "==========================================="
echo "ASVFlow Part 4: Quick Validation Test"
echo "==========================================="
echo ""

OUTDIR="test_output/part4_quick_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUTDIR"

echo "Running full pipeline with community analysis..."
echo ""

nextflow run main.nf \
    --sample_sheet test/samplesheet_synthetic.csv \
    --outdir "$OUTDIR" \
    --primer_mode paired \
    --primer_fwd GTGYCAGCMGCCGCGGTAA \
    --primer_rev GGACTACNVGGGTWTCTAAT \
    --run_dada2 true \
    --run_taxonomy true \
    --silva_version 144 \
    --run_community_analysis true \
    --sample_metadata test/fixtures/community/metadata_synthetic.tsv \
    -resume

echo ""
echo "Validating outputs..."
echo ""

OUT="$OUTDIR/community"

# Check critical files exist
ERRORS=0

for file in phyloseq.rds validation_summary.txt alpha_diversity.tsv \
            beta_diversity_bray_pcoa.tsv beta_diversity_distances_bray.rds \
            sequencing_depth.tsv composition_phylum_counts.tsv; do
    if [ ! -f "$OUT/$file" ]; then
        echo "ERROR: Missing $file"
        ERRORS=$((ERRORS + 1))
    else
        echo "✓ Found $file"
    fi
done

# Check TSV files have content
for file in alpha_diversity.tsv beta_diversity_bray_pcoa.tsv sequencing_depth.tsv; do
    if [ -f "$OUT/$file" ]; then
        lines=$(wc -l < "$OUT/$file")
        if [ "$lines" -lt 2 ]; then
            echo "ERROR: $file has insufficient content ($lines lines)"
            ERRORS=$((ERRORS + 1))
        else
            echo "✓ $file has $lines lines"
        fi
    fi
done

# Check alpha diversity values
if [ -f "$OUT/alpha_diversity.tsv" ]; then
    echo ""
    echo "Alpha diversity sample:"
    head -3 "$OUT/alpha_diversity.tsv"
fi

echo ""
if [ $ERRORS -eq 0 ]; then
    echo "===========================================" 
    echo "✓ QUICK VALIDATION TEST PASSED"
    echo "===========================================" 
    echo ""
    echo "Output directory: $OUTDIR"
    exit 0
else
    echo "===========================================" 
    echo "✗ VALIDATION FAILED: $ERRORS errors"
    echo "===========================================" 
    exit 1
fi
