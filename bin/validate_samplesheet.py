#!/usr/bin/env python3
"""
Validate paired-end FASTQ samplesheet for ASVFlow.
Expected CSV format: sample_id,fastq_1,fastq_2
"""
import sys
import csv
import gzip
import argparse
from pathlib import Path


def validate_gzip_integrity(file_path):
    """
    Validate gzip file by streaming read to EOF.
    Returns (is_valid, error_message).
    """
    try:
        with gzip.open(file_path, 'rb') as fh:
            while True:
                chunk = fh.read(8192)
                if not chunk:
                    break
        return True, None
    except Exception as e:
        return False, str(e)


def validate_samplesheet(csv_path):
    """Validate samplesheet structure and file existence."""
    errors = []
    seen_ids = set()
    valid_samples = []

    csv_file = Path(csv_path)
    if not csv_file.exists():
        sys.stderr.write(f"ERROR: Samplesheet not found: {csv_path}\n")
        sys.exit(1)

    with open(csv_file, 'r') as f:
        reader = csv.DictReader(f)

        if reader.fieldnames != ['sample_id', 'fastq_1', 'fastq_2']:
            sys.stderr.write("ERROR: Invalid header. Expected: sample_id,fastq_1,fastq_2\n")
            sys.stderr.write(f"       Got: {','.join(reader.fieldnames or [])}\n")
            sys.exit(1)

        for line_num, row in enumerate(reader, start=2):
            if not any(row.values()):
                continue

            sample_id = row.get('sample_id', '').strip()
            fastq_1 = row.get('fastq_1', '').strip()
            fastq_2 = row.get('fastq_2', '').strip()

            if not sample_id:
                errors.append(f"Line {line_num}: Empty sample_id")
                continue

            if not fastq_1:
                errors.append(f"Line {line_num}: Empty fastq_1")
                continue

            if not fastq_2:
                errors.append(f"Line {line_num}: Empty fastq_2")
                continue

            if sample_id in seen_ids:
                errors.append(f"Line {line_num}: Duplicate sample_id '{sample_id}'")
                continue

            seen_ids.add(sample_id)

            r1_path = Path(fastq_1)
            r2_path = Path(fastq_2)

            r1_exists = r1_path.exists()
            r2_exists = r2_path.exists()

            if not r1_exists:
                errors.append(f"Line {line_num}: R1 file not found: {fastq_1}")

            if not r2_exists:
                errors.append(f"Line {line_num}: R2 file not found: {fastq_2}")

            if r1_exists and r2_exists:
                r1_valid, r1_error = validate_gzip_integrity(r1_path)
                if not r1_valid:
                    errors.append(f"Line {line_num}: R1 gzip invalid: {r1_error}")

                r2_valid, r2_error = validate_gzip_integrity(r2_path)
                if not r2_valid:
                    errors.append(f"Line {line_num}: R2 gzip invalid: {r2_error}")

                if r1_valid and r2_valid:
                    valid_samples.append((sample_id, str(r1_path.absolute()), str(r2_path.absolute())))

    if not valid_samples and not errors:
        errors.append("No samples found in samplesheet")

    if errors:
        sys.stderr.write("VALIDATION FAILED:\n")
        for err in errors:
            sys.stderr.write(f"  {err}\n")
        sys.exit(1)

    sys.stderr.write(f"Validated {len(valid_samples)} samples\n")

    for sample_id, r1, r2 in valid_samples:
        print(f"{sample_id},{r1},{r2}")


def main():
    parser = argparse.ArgumentParser(
        description='Validate paired-end FASTQ samplesheet for ASVFlow',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog='''
Expected CSV format:
  sample_id,fastq_1,fastq_2
  S1,/path/to/S1_R1.fastq.gz,/path/to/S1_R2.fastq.gz
  S2,/path/to/S2_R1.fastq.gz,/path/to/S2_R2.fastq.gz

Validation checks:
  - CSV header matches expected format
  - All files exist and are readable
  - All gzip files are valid (complete read to EOF)
  - No duplicate sample IDs
  - No empty required fields
        '''
    )
    parser.add_argument('samplesheet', help='Path to CSV samplesheet')

    args = parser.parse_args()
    validate_samplesheet(args.samplesheet)


if __name__ == '__main__':
    main()
