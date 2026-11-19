#!/bin/bash
# Test script for ASVFlow Part 1 input validation
set -euo pipefail

BASEDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$BASEDIR"

# Generate the ignored synthetic FASTQ fixtures and their portable sheets.
python3 test/generate_synthetic_data.py >/dev/null

echo "=== ASVFlow Part 1 Input Validation Tests ==="
echo ""

# Test 1: Input validation - invalid samplesheet
echo "Test 1: Invalid samplesheet (missing header)"
echo "sample,r1,r2" > test/invalid_header.csv
echo "S1,file1.fq.gz,file2.fq.gz" >> test/invalid_header.csv
python3 bin/validate_samplesheet.py test/invalid_header.csv 2>&1 && {
    echo "FAIL: Should have rejected invalid header"
    exit 1
} || echo "PASS: Rejected invalid header"
echo ""

# Test 2: Input validation - missing file
echo "Test 2: Missing FASTQ file"
echo "sample_id,fastq_1,fastq_2" > test/missing_file.csv
echo "S1,/nonexistent/file1.fq.gz,/nonexistent/file2.fq.gz" >> test/missing_file.csv
python3 bin/validate_samplesheet.py test/missing_file.csv 2>&1 && {
    echo "FAIL: Should have rejected missing files"
    exit 1
} || echo "PASS: Rejected missing files"
echo ""

# Test 3: Input validation - duplicate sample_id
echo "Test 3: Duplicate sample_id"
echo "sample_id,fastq_1,fastq_2" > test/duplicate_id.csv
echo "TEST1,test/TEST1_R1.fastq.gz,test/TEST1_R2.fastq.gz" >> test/duplicate_id.csv
echo "TEST1,test/TEST2_R1.fastq.gz,test/TEST2_R2.fastq.gz" >> test/duplicate_id.csv
python3 bin/validate_samplesheet.py test/duplicate_id.csv 2>&1 && {
    echo "FAIL: Should have rejected duplicate IDs"
    exit 1
} || echo "PASS: Rejected duplicate IDs"
echo ""

# Test 4: Valid samplesheet
echo "Test 4: Valid samplesheet"
OUTPUT=$(python3 bin/validate_samplesheet.py test/samplesheet_synthetic.csv 2>&1)
[[ "$OUTPUT" == *"Validated 6 samples"* ]] && {
    echo "PASS: Six-sample synthetic samplesheet accepted"
} || {
    echo "FAIL: Valid samplesheet rejected"
    exit 1
}
echo ""

# Test 5: Command-line help
echo "Test 5: Command-line help"
OUTPUT=$(python3 bin/validate_samplesheet.py --help 2>&1)
[[ "$OUTPUT" == *"Expected CSV format"* ]] && {
    echo "PASS: Help message displayed"
} || {
    echo "FAIL: Help message not displayed"
    exit 1
}
echo ""

# Test 6: No arguments
echo "Test 6: No arguments (should show usage)"
OUTPUT=$(python3 bin/validate_samplesheet.py 2>&1 || true)
echo "$OUTPUT" | grep -q "arguments are required: samplesheet" && {
    echo "PASS: Usage message shown for missing argument"
} || {
    echo "FAIL: No usage message for missing argument"
    exit 1
}
echo ""

# Test 7: Blank rows in CSV
echo "Test 7: Blank rows in CSV"
cat > test/blank_rows.csv <<EOF
sample_id,fastq_1,fastq_2
TEST1,test/TEST1_R1.fastq.gz,test/TEST1_R2.fastq.gz

TEST2,test/TEST2_R1.fastq.gz,test/TEST2_R2.fastq.gz
,,
EOF
OUTPUT=$(python3 bin/validate_samplesheet.py test/blank_rows.csv 2>&1)
[[ "$OUTPUT" == *"Validated 2 samples"* ]] && {
    echo "PASS: Blank rows skipped gracefully"
} || {
    echo "FAIL: Blank rows not handled correctly"
    exit 1
}
echo ""

# Test 8: Empty field values
echo "Test 8: Empty field values"
cat > test/empty_fields.csv <<EOF
sample_id,fastq_1,fastq_2
TEST1,,test/TEST1_R2.fastq.gz
,test/TEST2_R1.fastq.gz,test/TEST2_R2.fastq.gz
EOF
python3 bin/validate_samplesheet.py test/empty_fields.csv 2>&1 && {
    echo "FAIL: Should have rejected empty fields"
    exit 1
} || echo "PASS: Empty fields detected"
echo ""

# Test 9: Truncated gzip file
echo "Test 9: Truncated gzip file"
mkdir -p test/tmp
dd if=test/TEST1_R1.fastq.gz of=test/tmp/truncated_R1.fastq.gz bs=100 count=1 2>/dev/null
cat > test/truncated_gzip.csv <<EOF
sample_id,fastq_1,fastq_2
TEST1,test/tmp/truncated_R1.fastq.gz,test/TEST1_R2.fastq.gz
EOF
python3 bin/validate_samplesheet.py test/truncated_gzip.csv 2>&1 && {
    echo "FAIL: Should have detected truncated gzip"
    exit 1
} || echo "PASS: Truncated gzip file detected"
echo ""

# Test 10: Invalid gzip file (not gzip format)
echo "Test 10: Invalid gzip file (not gzip format)"
echo "This is not a gzip file" > test/tmp/not_gzip.fastq.gz
cat > test/invalid_gzip.csv <<EOF
sample_id,fastq_1,fastq_2
TEST1,test/tmp/not_gzip.fastq.gz,test/TEST1_R2.fastq.gz
EOF
python3 bin/validate_samplesheet.py test/invalid_gzip.csv 2>&1 && {
    echo "FAIL: Should have detected invalid gzip format"
    exit 1
} || echo "PASS: Invalid gzip format detected"
echo ""

# Clean up test files
rm -rf test/tmp
rm -f test/invalid_header.csv test/missing_file.csv test/duplicate_id.csv
rm -f test/blank_rows.csv test/empty_fields.csv test/truncated_gzip.csv test/invalid_gzip.csv

echo "=== All input validation tests passed ==="
