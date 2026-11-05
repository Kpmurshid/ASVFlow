#!/bin/bash
set -euo pipefail

echo "==========================================="
echo "ASVFlow Part 4: Test WITHOUT Taxonomy"
echo "==========================================="
echo ""

OUTDIR="test_output/part4_no_tax_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUTDIR"

echo "Running pipeline with community analysis (no taxonomy)..."
echo ""

nextflow run main.nf \
    --sample_sheet test/samplesheet_synthetic.csv \
    --outdir "$OUTDIR" \
    --primer_mode paired \
    --primer_fwd GTGYCAGCMGCCGCGGTAA \
    --primer_rev GGACTACNVGGGTWTCTAAT \
    --run_dada2 true \
    --run_taxonomy false \
    --run_community_analysis true \
    --sample_metadata test/fixtures/community/metadata_synthetic.tsv \
    -resume

echo ""
echo "Validating outputs..."
echo ""

OUT="$OUTDIR/community"
ERRORS=0

# Check required files (no taxonomy)
for file in phyloseq.rds validation_summary.txt alpha_diversity.tsv \
            beta_diversity_bray_pcoa.tsv beta_diversity_jaccard_pcoa.tsv \
            beta_diversity_distances_bray.rds beta_diversity_distances_jaccard.rds \
            beta_diversity_summary.txt sequencing_depth.tsv \
            sequencing_depth_stats.tsv permanova_summary.txt; do
    if [ ! -f "$OUT/$file" ]; then
        echo "ERROR: Missing $file"
        ERRORS=$((ERRORS + 1))
    else
        echo "✓ Found $file"
    fi
done

# Composition should NOT exist
if [ -f "$OUT/composition_phylum_counts.tsv" ]; then
    echo "ERROR: Composition should not exist without taxonomy"
    ERRORS=$((ERRORS + 1))
else
    echo "✓ Composition correctly skipped without taxonomy"
fi

# Check alpha diversity content
if [ -f "$OUT/alpha_diversity.tsv" ]; then
    echo ""
    echo "Alpha diversity content:"
    head -5 "$OUT/alpha_diversity.tsv"
    echo ""
fi

# Check beta diversity stats
if [ -f "$OUT/beta_diversity_stats.tsv" ]; then
    echo "Beta diversity stats:"
    head -5 "$OUT/beta_diversity_stats.tsv"
    echo ""
fi

# Check PERMANOVA ran
if [ -f "$OUT/permanova_bray.tsv" ]; then
    echo "✓ PERMANOVA executed successfully"
    echo "PERMANOVA summary:"
    cat "$OUT/permanova_summary.txt"
    echo ""
elif [ -f "$OUT/permanova_skipped.txt" ]; then
    echo "PERMANOVA skipped:"
    cat "$OUT/permanova_skipped.txt"
    echo ""
fi

echo ""
if [ $ERRORS -eq 0 ]; then
    echo "==========================================="
    echo "✓ TEST PASSED (No Taxonomy)"
    echo "==========================================="
    echo ""
    echo "Output directory: $OUTDIR"
    exit 0
else
    echo "==========================================="
    echo "✗ TEST FAILED: $ERRORS errors"
    echo "==========================================="
    exit 1
fi
