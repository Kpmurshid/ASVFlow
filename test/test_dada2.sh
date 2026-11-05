#!/bin/bash
# ASVFlow Part 2 DADA2 Integration Tests

set -euo pipefail

echo "=== ASVFlow Part 2 DADA2 Tests ==="
echo

# Test 1: Part 1 validation tests still pass
echo "Test 1: Part 1 input validation (regression test)"
bash test/test_validation.sh >/dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "PASS: Part 1 validation tests still passing"
else
    echo "FAIL: Part 1 validation tests broken"
    exit 1
fi
echo

# Test 2: Stub mode execution
echo "Test 2: Nextflow stub mode (workflow structure)"
nextflow run main.nf -stub \
    --sample_sheet test/samplesheet.csv \
    --outdir results/stub_test \
    --primer_mode paired \
    --primer_fwd GTGYCAGCMGCCGCGGTAA \
    --primer_rev GGACTACNVGGGTWTCTAAT \
    >/dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "PASS: Stub mode completed successfully"
else
    echo "FAIL: Stub mode execution failed"
    exit 1
fi
echo

# Test 3: Verify synthetic test outputs
echo "Test 3: Synthetic data DADA2 integration"
if [ -f results/dada2_synthetic/dada2/final/seqtab_nochim.fasta ]; then
    n_asvs=$(grep -c '^>' results/dada2_synthetic/dada2/final/seqtab_nochim.fasta)
    if [ "$n_asvs" -eq 3 ]; then
        echo "PASS: Correct number of ASVs detected ($n_asvs, expected 3)"
    else
        echo "FAIL: Incorrect ASV count ($n_asvs, expected 3)"
        exit 1
    fi
else
    echo "FAIL: seqtab_nochim.fasta not found"
    exit 1
fi

# Test 4: Verify merge success rate
merge_rate=$(awk -F'\t' 'NR==2 {print $4}' results/dada2_synthetic/dada2/merged/TEST1_merge_stats.txt)
if [ "$merge_rate" == "100" ]; then
    echo "PASS: High merge success rate ($merge_rate%)"
else
    echo "WARN: Merge rate lower than expected ($merge_rate%, expected 100%)"
fi

# Test 5: Verify chimera removal
chimeric_asvs=$(awk -F'\t' '/asvs_chimeric/ {print $2}' results/dada2_synthetic/dada2/final/chimera_stats.tsv)
if [ "$chimeric_asvs" -eq 0 ]; then
    echo "PASS: No chimeric ASVs in synthetic data (expected)"
else
    echo "WARN: $chimeric_asvs chimeric ASVs detected"
fi

# Test 6: Verify output file structure
echo
echo "Test 6: Output file structure"
expected_files=(
    "results/dada2_synthetic/dada2/qc/quality_profile_R1.pdf"
    "results/dada2_synthetic/dada2/qc/quality_profile_R2.pdf"
    "results/dada2_synthetic/dada2/filtered/TEST1_R1_filt.fastq.gz"
    "results/dada2_synthetic/dada2/error_models/error_model_F.rds"
    "results/dada2_synthetic/dada2/error_models/error_plot_F.pdf"
    "results/dada2_synthetic/dada2/dereplicated/TEST1_derep_F.rds"
    "results/dada2_synthetic/dada2/inferred/TEST1_dada_F.rds"
    "results/dada2_synthetic/dada2/merged/TEST1_merged.rds"
    "results/dada2_synthetic/dada2/merged/TEST1_merge_stats.txt"
    "results/dada2_synthetic/dada2/seqtab/seqtab_all.rds"
    "results/dada2_synthetic/dada2/final/seqtab_nochim.rds"
    "results/dada2_synthetic/dada2/final/seqtab_nochim.tsv"
    "results/dada2_synthetic/dada2/final/seqtab_nochim.fasta"
    "results/dada2_synthetic/dada2/final/chimera_stats.tsv"
    "results/dada2_synthetic/dada2/final/track_reads.tsv"
)

missing_count=0
for file in "${expected_files[@]}"; do
    if [ ! -f "$file" ]; then
        echo "  MISSING: $file"
        missing_count=$((missing_count + 1))
    fi
done

if [ $missing_count -eq 0 ]; then
    echo "PASS: All expected output files present"
else
    echo "FAIL: $missing_count files missing"
    exit 1
fi

# Test 7: Verify FASTA format
echo
echo "Test 7: FASTA output format"
if grep -q '^>ASV_' results/dada2_synthetic/dada2/final/seqtab_nochim.fasta; then
    echo "PASS: FASTA headers correctly formatted"
else
    echo "FAIL: FASTA header format incorrect"
    exit 1
fi

# Test 8: Verify TSV output format
echo
echo "Test 8: TSV output format"
header=$(head -1 results/dada2_synthetic/dada2/final/seqtab_nochim.tsv)
if [[ "$header" == *"TEST1"* ]] && [[ "$header" == *"TEST2"* ]]; then
    echo "PASS: TSV contains sample column headers"
else
    echo "FAIL: TSV format incorrect"
    exit 1
fi

echo
echo "=== All DADA2 integration tests passed ==="
echo
echo "Summary of synthetic data results:"
cat results/dada2_synthetic/dada2/final/chimera_stats.tsv
echo
echo "Per-sample read tracking:"
cat results/dada2_synthetic/dada2/final/track_reads.tsv
