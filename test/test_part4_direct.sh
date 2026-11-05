#!/bin/bash
set -euo pipefail

echo "==========================================="
echo "ASVFlow Part 4: Direct Module Test"
echo "Using existing DADA2 + Taxonomy outputs"
echo "==========================================="
echo ""

OUTDIR="test_output/part4_direct_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUTDIR"

# Copy existing outputs to simulate pipeline state
mkdir -p "$OUTDIR/dada2/final"
mkdir -p "$OUTDIR/taxonomy"

cp results/test_final/dada2/final/* "$OUTDIR/dada2/final/"
cp results/test_final/taxonomy/* "$OUTDIR/taxonomy/"

echo "Testing community analysis with existing outputs..."
echo ""

nextflow run main.nf \
    --sample_sheet test/samplesheet_synthetic.csv \
    --outdir "$OUTDIR" \
    --primer_mode paired \
    --primer_fwd GTGYCAGCMGCCGCGGTAA \
    --primer_rev GGACTACNVGGGTWTCTAAT \
    --run_dada2 false \
    --run_taxonomy false \
    --run_community_analysis true \
    --sample_metadata test/fixtures/community/metadata_synthetic.tsv \
    -resume

if [ $? -ne 0 ]; then
    echo "ERROR: Pipeline execution failed"
    exit 1
fi

echo ""
echo "Validating community analysis outputs..."
echo ""

OUT="$OUTDIR/community"
ERRORS=0

# Check required files
for file in phyloseq.rds validation_summary.txt alpha_diversity.tsv \
            beta_diversity_bray_pcoa.tsv beta_diversity_jaccard_pcoa.tsv \
            beta_diversity_distances_bray.rds beta_diversity_summary.txt \
            sequencing_depth.tsv sequencing_depth_stats.tsv; do
    if [ ! -f "$OUT/$file" ]; then
        echo "ERROR: Missing $file"
        ERRORS=$((ERRORS + 1))
    else
        echo "✓ Found $file"
    fi
done

# Check TSV files have content (header + data)
echo ""
echo "Checking TSV file content..."
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

# Display alpha diversity results
if [ -f "$OUT/alpha_diversity.tsv" ]; then
    echo ""
    echo "Alpha Diversity Results:"
    cat "$OUT/alpha_diversity.tsv"
    echo ""
fi

# Display beta diversity stats
if [ -f "$OUT/beta_diversity_stats.tsv" ]; then
    echo "Beta Diversity Statistics:"
    head -10 "$OUT/beta_diversity_stats.tsv"
    echo ""
fi

# Check PERMANOVA
if [ -f "$OUT/permanova_bray.tsv" ]; then
    echo "✓ PERMANOVA executed"
    echo ""
    echo "PERMANOVA Summary:"
    cat "$OUT/permanova_summary.txt"
    echo ""
elif [ -f "$OUT/permanova_skipped.txt" ]; then
    echo "PERMANOVA was skipped:"
    cat "$OUT/permanova_skipped.txt"
    echo ""
fi

# Check taxonomy-dependent outputs
if [ -f "$OUT/composition_phylum_counts.tsv" ]; then
    echo "✓ Taxonomic composition analysis completed"
    echo ""
    echo "Composition Summary:"
    head -5 "$OUT/composition_summary.tsv" 2>/dev/null || echo "(summary file not found)"
    echo ""
fi

echo ""
if [ $ERRORS -eq 0 ]; then
    echo "==========================================="
    echo "✓ ALL TESTS PASSED"
    echo "==========================================="
    echo ""
    echo "Output directory: $OUTDIR"
    echo ""
    echo "Summary of generated files:"
    ls -lh "$OUT" | tail -n +2 | awk '{print $9, "(" $5 ")"}'
    exit 0
else
    echo "==========================================="
    echo "✗ TESTS FAILED: $ERRORS errors"
    echo "==========================================="
    exit 1
fi
