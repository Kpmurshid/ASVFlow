#!/bin/bash
# ASVFlow Part 3 Edge Case Tests

set -uo pipefail

echo "=== ASVFlow Part 3 Edge Case Tests ==="
echo

# Test 1: Missing genus reference
echo "Test 1: Missing genus reference (validation error)"
mkdir -p test/fake_db/silva/144

nextflow run main.nf \
    --sample_sheet test/samplesheet_synthetic.csv \
    --outdir results/missing_genus_ref \
    --primer_mode none \
    --run_taxonomy true \
    --databases test/fake_db \
    --silva_version 144 \
    > missing_ref.log 2>&1

missing_ref_status=$?

if [ $missing_ref_status -eq 0 ]; then
    echo "FAIL: Should have failed with missing reference"
    rm -rf test/fake_db
    exit 1
fi

if grep -q "SILVA Reference Database Not Found" missing_ref.log; then
    echo "PASS: Clear error for missing genus reference"
else
    echo "FAIL: Error message unclear"
    tail -20 missing_ref.log
    rm -rf test/fake_db
    exit 1
fi

rm -rf test/fake_db
echo

# Test 2: Unknown SILVA version
echo "Test 2: Unknown SILVA version (requires explicit paths)"

nextflow run main.nf \
    --sample_sheet test/samplesheet_synthetic.csv \
    --outdir results/unknown_version \
    --primer_mode none \
    --run_taxonomy true \
    --silva_version 132 \
    > unknown_version.log 2>&1

unknown_version_status=$?

if [ $unknown_version_status -eq 0 ]; then
    echo "FAIL: Should have failed with unknown version"
    exit 1
fi

if grep -q "Unknown SILVA version: 132" unknown_version.log; then
    echo "PASS: Clear error for unknown SILVA version"
else
    echo "FAIL: Error message unclear"
    tail -20 unknown_version.log
    exit 1
fi

echo

# Test 3: FASTA/RDS mismatch (validation should catch)
echo "Test 3: FASTA/RDS mismatch detection"

rm -rf results/module_mismatch .nextflow* work
nextflow run test/workflows/test_assign_taxonomy.nf \
    \
    --test_seqtab_rds test/fixtures/seqtab_small.rds \
    --test_seqtab_fasta test/fixtures/seqtab_mismatch.fasta \
    --silva_genus_ref databases/silva/144/silva_nr99_v144_toGenus_trainset.fa.gz \
    --taxonomy_min_boot 50 \
    --taxonomy_tryrc true \
    --outdir results/module_mismatch \
    > mismatch.log 2>&1

mismatch_status=$?

if [ $mismatch_status -eq 0 ]; then
    echo "FAIL: Should have failed with FASTA/RDS mismatch"
    exit 1
fi

if grep -q "FASTA and RDS sequence sets do not match" mismatch.log; then
    echo "PASS: FASTA/RDS mismatch detected"
else
    echo "FAIL: Mismatch not properly detected"
    tail -20 mismatch.log
    exit 1
fi

echo

# Test 4: Duplicate ASV IDs in FASTA
echo "Test 4: Duplicate ASV ID detection"

rm -rf results/module_dup_id .nextflow* work
nextflow run test/workflows/test_assign_taxonomy.nf \
    \
    --test_seqtab_rds test/fixtures/seqtab_small.rds \
    --test_seqtab_fasta test/fixtures/seqtab_duplicate_id.fasta \
    --silva_genus_ref databases/silva/144/silva_nr99_v144_toGenus_trainset.fa.gz \
    --taxonomy_min_boot 50 \
    --taxonomy_tryrc true \
    --outdir results/module_dup_id \
    > dup_id.log 2>&1

dup_id_status=$?

if [ $dup_id_status -eq 0 ]; then
    echo "FAIL: Should have failed with duplicate IDs"
    exit 1
fi

if grep -q "Duplicate ASV IDs" dup_id.log; then
    echo "PASS: Duplicate ASV IDs detected"
else
    echo "FAIL: Duplicate IDs not properly detected"
    tail -20 dup_id.log
    exit 1
fi

echo

# Test 5: Invalid DNA characters
echo "Test 5: Invalid DNA character detection"

rm -rf results/module_invalid_dna .nextflow* work
nextflow run test/workflows/test_assign_taxonomy.nf \
    \
    --test_seqtab_rds test/fixtures/seqtab_small.rds \
    --test_seqtab_fasta test/fixtures/seqtab_invalid_dna.fasta \
    --silva_genus_ref databases/silva/144/silva_nr99_v144_toGenus_trainset.fa.gz \
    --taxonomy_min_boot 50 \
    --taxonomy_tryrc true \
    --outdir results/module_invalid_dna \
    > invalid_dna.log 2>&1

invalid_dna_status=$?

if [ $invalid_dna_status -eq 0 ]; then
    echo "FAIL: Should have failed with invalid DNA characters"
    exit 1
fi

if grep -q "Invalid DNA" invalid_dna.log; then
    echo "PASS: Invalid DNA characters detected"
else
    echo "FAIL: Invalid DNA not properly detected"
    tail -20 invalid_dna.log
    exit 1
fi

echo

echo "=== All edge case tests passed ==="
