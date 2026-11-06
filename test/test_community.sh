#!/bin/bash

set -euo pipefail

echo "========================================"
echo "Testing ASVFlow Part 4: Community Analysis"
echo "========================================"
echo ""

OUTDIR="test_output/community_test_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUTDIR"

echo "Test 1: Full pipeline with taxonomy and metadata"
echo "------------------------------------------------"

nextflow run main.nf \
    --sample_sheet test/samplesheet_synthetic.csv \
    --outdir "$OUTDIR/full" \
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

OUT="$OUTDIR/full/community"

# Check required files
for file in phyloseq.rds validation_summary.txt alpha_diversity.tsv \
            beta_diversity_bray_pcoa.tsv beta_diversity_summary.txt \
            beta_diversity_distances_bray.rds sequencing_depth.tsv \
            composition_phylum_counts.tsv composition_summary.tsv; do
    if [ ! -f "$OUT/$file" ]; then
        echo "ERROR: Missing $file"
        exit 1
    fi
done

echo "✓ All required files present"

# Validate TSV files are not empty and have headers
for file in alpha_diversity.tsv beta_diversity_bray_pcoa.tsv \
            sequencing_depth.tsv composition_phylum_counts.tsv; do
    lines=$(wc -l < "$OUT/$file")
    if [ "$lines" -lt 2 ]; then
        echo "ERROR: $file has < 2 lines"
        exit 1
    fi
done

echo "✓ TSV files have content"

# Check PERMANOVA ran
if [ -f "$OUT/permanova_bray.tsv" ]; then
    echo "✓ PERMANOVA executed"
else
    echo "WARNING: PERMANOVA not found (may be skipped)"
fi

echo ""
echo "Test 2: Community analysis without taxonomy"
echo "--------------------------------------------"

nextflow run main.nf \
    --sample_sheet test/samplesheet_synthetic.csv \
    --outdir "$OUTDIR/no_taxonomy" \
    --primer_mode paired \
    --primer_fwd GTGYCAGCMGCCGCGGTAA \
    --primer_rev GGACTACNVGGGTWTCTAAT \
    --run_dada2 true \
    --run_taxonomy false \
    --run_community_analysis true \
    --sample_metadata test/fixtures/community/metadata_synthetic.tsv \
    -resume

OUT2="$OUTDIR/no_taxonomy/community"

# Alpha and beta should work, composition should not
if [ -f "$OUT2/alpha_diversity.tsv" ] && [ -f "$OUT2/beta_diversity_bray_pcoa.tsv" ]; then
    echo "✓ Alpha and beta diversity ran without taxonomy"
else
    echo "ERROR: Alpha or beta diversity failed"
    exit 1
fi

if [ -f "$OUT2/composition_phylum_counts.tsv" ]; then
    echo "ERROR: Composition should not run without taxonomy"
    exit 1
else
    echo "✓ Composition correctly skipped without taxonomy"
fi

echo ""
echo "Test 3: Community analysis without metadata"
echo "--------------------------------------------"

nextflow run main.nf \
    --sample_sheet test/samplesheet_synthetic.csv \
    --outdir "$OUTDIR/no_metadata" \
    --primer_mode paired \
    --primer_fwd GTGYCAGCMGCCGCGGTAA \
    --primer_rev GGACTACNVGGGTWTCTAAT \
    --run_dada2 true \
    --run_taxonomy true \
    --silva_version 144 \
    --run_community_analysis true \
    -resume

OUT3="$OUTDIR/no_metadata/community"

# All should work except PERMANOVA
if [ -f "$OUT3/alpha_diversity.tsv" ] && [ -f "$OUT3/beta_diversity_bray_pcoa.tsv" ] && \
   [ -f "$OUT3/composition_phylum_counts.tsv" ]; then
    echo "✓ All analyses ran without metadata"
else
    echo "ERROR: Some analyses failed without metadata"
    exit 1
fi

if [ -f "$OUT3/permanova_bray.tsv" ]; then
    echo "ERROR: PERMANOVA should not run without metadata"
    exit 1
else
    echo "✓ PERMANOVA correctly skipped without metadata"
fi

echo ""
echo "========================================"
echo "All community analysis tests PASSED"
echo "========================================"
echo ""
echo "Output directory: $OUTDIR"

