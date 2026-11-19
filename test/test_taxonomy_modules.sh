#!/bin/bash
# ASVFlow Part 3 Taxonomy Module Tests

set -uo pipefail

CONTAINER_RUNTIME="$(command -v apptainer || command -v singularity || true)"
if [[ -z "$CONTAINER_RUNTIME" ]]; then
    echo "ERROR: Apptainer or Singularity is required"
    exit 1
fi

echo "=== ASVFlow Part 3 Taxonomy Module Tests ==="
echo

# Generate test fixtures
echo "Generating test fixtures..."
"$CONTAINER_RUNTIME" exec tools/asvflow-dada2.sif Rscript test/fixtures/create_taxonomy_fixtures.R > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "FAIL: Failed to generate test fixtures"
    exit 1
fi
echo "PASS: Test fixtures created"
echo

# Test 1: ASSIGN_TAXONOMY with empty input
echo "Test 1: ASSIGN_TAXONOMY with empty input"
rm -rf results/module_test_empty .nextflow* work
nextflow run test/workflows/test_assign_taxonomy.nf \
    \
    --test_seqtab_rds test/fixtures/seqtab_empty.rds \
    --test_seqtab_fasta test/fixtures/seqtab_empty.fasta \
    --silva_genus_ref databases/silva/144/silva_nr99_v144_toGenus_trainset.fa.gz \
    --taxonomy_min_boot 50 \
    --taxonomy_tryrc true \
    --outdir results/module_test_empty \
    > /dev/null 2>&1

module_empty_status=$?
if [ $module_empty_status -ne 0 ]; then
    echo "FAIL: Module execution failed"
    exit 1
fi

# Verify outputs in publishDir
if [ ! -f results/module_test_empty/taxonomy.rds ]; then
    echo "FAIL: taxonomy.rds not created"
    exit 1
fi
if [ ! -f results/module_test_empty/taxonomy.tsv ]; then
    echo "FAIL: taxonomy.tsv not created"
    exit 1
fi
if [ ! -f results/module_test_empty/taxonomy_stats.tsv ]; then
    echo "FAIL: taxonomy_stats.tsv not created"
    exit 1
fi

# Check TSV is header-only (1 line)
lines=$(wc -l < results/module_test_empty/taxonomy.tsv)
if [ $lines -ne 1 ]; then
    echo "FAIL: Expected 1 line (header), got $lines"
    cat results/module_test_empty/taxonomy.tsv
    exit 1
fi

echo "PASS: Empty input handled correctly"
echo

# Test 2: ADD_SPECIES with empty input
echo "Test 2: ADD_SPECIES with empty input"
rm -rf results/module_test_species_empty .nextflow* work
nextflow run test/workflows/test_add_species.nf \
    \
    --test_taxonomy_rds test/fixtures/taxonomy_empty.rds \
    --test_taxonomy_tsv test/fixtures/taxonomy_empty.tsv \
    --silva_species_ref databases/silva/144/silva_v144_assignSpecies.fa.gz \
    --taxonomy_tryrc true \
    --outdir results/module_test_species_empty \
    > /dev/null 2>&1

species_empty_status=$?
if [ $species_empty_status -ne 0 ]; then
    echo "FAIL: ADD_SPECIES failed on empty input"
    exit 1
fi

# Verify outputs
if [ ! -f results/module_test_species_empty/taxonomy_species.tsv ]; then
    echo "FAIL: taxonomy_species.tsv not created"
    exit 1
fi

lines=$(wc -l < results/module_test_species_empty/taxonomy_species.tsv)
if [ $lines -ne 1 ]; then
    echo "FAIL: Expected 1 line (header), got $lines"
    exit 1
fi

echo "PASS: ADD_SPECIES empty input handled correctly"
echo

echo "=== All module tests passed ==="
