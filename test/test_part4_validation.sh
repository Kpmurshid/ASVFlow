#!/bin/bash
set -euo pipefail

echo "========================================================================="
echo "ASVFlow Part 4: Comprehensive Module Validation"
echo "========================================================================="
echo ""

TESTDIR="validation_part4_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$TESTDIR"

# Test 1: Create controlled synthetic data
echo "Creating controlled test data..."
mkdir -p "$TESTDIR/input"

# ASV table: 3 samples, 5 ASVs
cat > "$TESTDIR/input/asv_table.tsv" << 'EOF'
	ASV1	ASV2	ASV3	ASV4	ASV5
Sample1	100	50	25	10	5
Sample2	80	60	30	15	10
Sample3	0	0	0	0	0
EOF

cat > "$TESTDIR/input/asv_seqs.fasta" << 'EOF'
>ASV1
ACGTACGTACGTACGTACGT
>ASV2
TGCATGCATGCATGCATGCA
>ASV3
GCTAGCTAGCTAGCTAGCTA
>ASV4
ATATATATATATATATATAT
>ASV5
CGCGCGCGCGCGCGCGCGCG
EOF

cat > "$TESTDIR/input/taxonomy.tsv" << 'EOF'
asv_id	Kingdom	Phylum	Class	Order	Family	Genus	Species
ASV1	Bacteria	Proteobacteria	Gammaproteobacteria	Enterobacterales	Enterobacteriaceae	Escherichia	coli
ASV2	Bacteria	Firmicutes	Bacilli	Lactobacillales	Lactobacillaceae	Lactobacillus	acidophilus
ASV3	Bacteria	Bacteroidetes	Bacteroidia	Bacteroidales	Bacteroidaceae	Bacteroides	fragilis
ASV4	Bacteria	Actinobacteria	Actinobacteria	Bifidobacteriales	Bifidobacteriaceae	Bifidobacterium	longum
ASV5	Bacteria	Proteobacteria	Gammaproteobacteria	Enterobacterales	Enterobacteriaceae	Escherichia	NA
EOF

cat > "$TESTDIR/input/metadata.tsv" << 'EOF'
sample_id	group	replicate
Sample1	GroupA	1
Sample2	GroupB	1
Sample3	GroupA	2
EOF

# Test 2: Identical presence/absence for Jaccard edge case
cat > "$TESTDIR/input/asv_identical.tsv" << 'EOF'
	ASV1	ASV2	ASV3
SampleX	100	50	25
SampleY	200	100	50
EOF

cat > "$TESTDIR/input/metadata_identical.tsv" << 'EOF'
sample_id	group
SampleX	GroupA
SampleY	GroupB
EOF

echo "✓ Test data created"
echo ""

# Run validation R script
Rscript "$TESTDIR/validate.R"

echo ""
echo "Validation complete. See $TESTDIR for results."
