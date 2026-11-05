#!/bin/bash
# ASVFlow Part 3 Taxonomy Integration Tests

set -uo pipefail

echo "=== ASVFlow Part 3 Taxonomy Integration Tests ==="
echo

# Test 1: Regression - Part 1 and Part 2 still work
echo "Test 1: Regression - Parts 1 and 2 validation"
bash test/test_validation.sh > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "FAIL: Part 1 validation tests broken"
    exit 1
fi
echo "PASS: Part 1 validation tests still passing"
echo

# Test 2: Stub mode with taxonomy enabled
echo "Test 2: Stub mode with taxonomy"
rm -rf results/stub_taxonomy .nextflow* work
nextflow run main.nf -stub \
    --sample_sheet test/samplesheet.csv \
    --outdir results/stub_taxonomy \
    --primer_mode paired \
    --primer_fwd GTGYCAGCMGCCGCGGTAA \
    --primer_rev GGACTACNVGGGTWTCTAAT \
    --run_taxonomy true \
    --taxonomy_add_species true \
    > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "FAIL: Stub mode with taxonomy failed"
    exit 1
fi

if [ ! -f results/stub_taxonomy/taxonomy/taxonomy.tsv ]; then
    echo "FAIL: taxonomy.tsv not created in stub mode"
    exit 1
fi
if [ ! -f results/stub_taxonomy/taxonomy/taxonomy_species.tsv ]; then
    echo "FAIL: taxonomy_species.tsv not created in stub mode"
    exit 1
fi

echo "PASS: Stub mode with taxonomy completed"
echo

# Test 3: Real taxonomy on synthetic data
echo "Test 3: Real taxonomy assignment on synthetic data"
echo "  (Using actual SILVA v144 references)"
rm -rf results/taxonomy_synthetic .nextflow* work
nextflow run main.nf \
    --sample_sheet test/samplesheet_synthetic.csv \
    --outdir results/taxonomy_synthetic \
    --primer_mode none \
    --run_taxonomy true \
    --taxonomy_add_species true \
    --taxonomy_min_boot 50 \
    > taxonomy_test.log 2>&1

taxonomy_status=$?
if [ $taxonomy_status -ne 0 ]; then
    echo "FAIL: Taxonomy pipeline execution failed"
    tail -50 taxonomy_test.log
    exit 1
fi

# Validate outputs
outdir="results/taxonomy_synthetic/taxonomy"

if [ ! -f "${outdir}/taxonomy.tsv" ]; then
    echo "FAIL: taxonomy.tsv not created"
    ls -la "${outdir}/" 2>&1 || echo "taxonomy directory missing"
    exit 1
fi

if [ ! -f "${outdir}/taxonomy_species.tsv" ]; then
    echo "FAIL: taxonomy_species.tsv not created"
    ls -la "${outdir}/"
    exit 1
fi

if [ ! -f "${outdir}/taxonomy_stats.tsv" ]; then
    echo "FAIL: taxonomy_stats.tsv not created"
    exit 1
fi

if [ ! -f "${outdir}/species_stats.tsv" ]; then
    echo "FAIL: species_stats.tsv not created"
    exit 1
fi

echo "PASS: All taxonomy output files present"

# Check TSV structure
n_cols=$(head -1 "${outdir}/taxonomy.tsv" | awk -F'\t' '{print NF}')
if [ $n_cols -ne 8 ]; then
    echo "FAIL: Taxonomy TSV has $n_cols columns, expected 8"
    head -1 "${outdir}/taxonomy.tsv"
    exit 1
fi
echo "PASS: Taxonomy TSV structure correct (8 columns)"

n_cols_sp=$(head -1 "${outdir}/taxonomy_species.tsv" | awk -F'\t' '{print NF}')
if [ $n_cols_sp -ne 9 ]; then
    echo "FAIL: Species TSV has $n_cols_sp columns, expected 9"
    head -1 "${outdir}/taxonomy_species.tsv"
    exit 1
fi
echo "PASS: Species TSV structure correct (9 columns)"

# Verify ASV ID consistency with Part 2
part2_asvs=$(tail -n +2 results/taxonomy_synthetic/dada2/final/seqtab_nochim.tsv | cut -f1)
tax_asvs=$(tail -n +2 "${outdir}/taxonomy.tsv" | cut -f1)

if [ "$(echo "$part2_asvs" | wc -l)" != "$(echo "$tax_asvs" | wc -l)" ]; then
    echo "FAIL: ASV count mismatch between Part 2 and taxonomy"
    exit 1
fi

if [ "$part2_asvs" != "$tax_asvs" ]; then
    echo "FAIL: ASV IDs or order changed in taxonomy output"
    exit 1
fi

echo "PASS: ASV IDs consistent with Part 2 output"

# Check that taxonomy was actually assigned (at least some classifications)
total_asvs=$(tail -n +2 "${outdir}/taxonomy.tsv" | wc -l)
classified_asvs=$(tail -n +2 "${outdir}/taxonomy.tsv" | awk -F'\t' '$3 != ""' | wc -l)

if [ $classified_asvs -eq 0 ]; then
    echo "WARN: No ASVs were classified (0 out of $total_asvs)"
    echo "      This may indicate a problem with the reference database"
else
    pct_classified=$((100 * classified_asvs / total_asvs))
    echo "PASS: $classified_asvs out of $total_asvs ASVs classified ($pct_classified%)"
fi

echo
echo "Taxonomy statistics:"
cat "${outdir}/taxonomy_stats.tsv"
echo
echo "Species statistics:"
cat "${outdir}/species_stats.tsv"
echo

# Test 4: Taxonomy disabled mode
echo "Test 4: Taxonomy disabled (regression test)"
rm -rf results/no_taxonomy .nextflow* work
nextflow run main.nf \
    --sample_sheet test/samplesheet_synthetic.csv \
    --outdir results/no_taxonomy \
    --primer_mode none \
    --run_taxonomy false \
    > /dev/null 2>&1

if [ $? -ne 0 ]; then
    echo "FAIL: Pipeline failed with taxonomy disabled"
    exit 1
fi

if [ -d results/no_taxonomy/taxonomy ]; then
    echo "FAIL: Taxonomy directory created when taxonomy disabled"
    exit 1
fi

echo "PASS: Pipeline works with taxonomy disabled"
echo

# Test 5: Genus-only mode (species disabled)
echo "Test 5: Genus-only taxonomy (species disabled)"
rm -rf results/genus_only .nextflow* work
nextflow run main.nf \
    --sample_sheet test/samplesheet_synthetic.csv \
    --outdir results/genus_only \
    --primer_mode none \
    --run_taxonomy true \
    --taxonomy_add_species false \
    > /dev/null 2>&1

if [ $? -ne 0 ]; then
    echo "FAIL: Genus-only mode failed"
    exit 1
fi

if [ ! -f results/genus_only/taxonomy/taxonomy.tsv ]; then
    echo "FAIL: taxonomy.tsv not created in genus-only mode"
    exit 1
fi

if [ -f results/genus_only/taxonomy/taxonomy_species.tsv ]; then
    echo "FAIL: Species file created when species disabled"
    exit 1
fi

echo "PASS: Genus-only mode works correctly"
echo

echo "=== All Part 3 integration tests passed ==="
echo
