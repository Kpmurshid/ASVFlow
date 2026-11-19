#!/usr/bin/env python3
"""
Generate synthetic paired-end FASTQ data for DADA2 testing.
Creates reads with known sequences, sufficient overlap, and controlled quality.

Reads include concrete 515F/806R primer sequences so that cutadapt
(--discard-untrimmed) trims them successfully and passes non-empty
FASTQ files to downstream DADA2 steps (plotQualityProfile, filterAndTrim).

Primer sequences (degenerate bases resolved to one concrete base each):
  515F: GTGYCAGCMGCCGCGGTAA  -> GTGCCAGCCGCCGCGGTAA  (Y=C, M=C)
  806R: GGACTACNVGGGTWTCTAAT -> GGACTACAAGGGTTTCTAAT (N=A, V=A, W=T)
"""

import gzip
import random
from pathlib import Path

# 515F primer (concrete, matches degenerate GTGYCAGCMGCCGCGGTAA within 10% error)
PRIMER_FWD = "GTGCCAGCCGCCGCGGTAA"
# 806R primer (concrete, matches degenerate GGACTACNVGGGTWTCTAAT within 10% error)
PRIMER_REV = "GGACTACAAGGGTTTCTAAT"

# Known 16S V4 sequences (simplified, ~200 bp biological sequences)
TEMPLATES = [
    "TACGGAGGGTGCAAGCGTTAATCGGAATTACTGGGCGTAAAGCGCACGCAGGCGGTTTGTTAAGTCAGATGTGAAATCCCCGGGCTCAACCTGGGAACTGCATCTGATACTGGCAAGCTTGAGTCTCGTAGAGGGGGGTAGAATTCCAGGTGTAGCGGTGAAATGCGTAGAGATCTGGAGGAATACCGGTGGCGAAGGCGGCCCCCTGGACGAAGACTGACGCT",
    "TACGTAGGTGGCAAGCGTTGTCCGGATTTACTGGGTGTAAAGGGAGCGTAGACGGCAGGGCAAGTCTGATGTGAAAACCCGGGGCTCAACCCCGGGACTGCATTGGAAACTGTTTTTCTTGAGTGCCGGAGAGGTAAGCGGAATTCCTAGTGTAGCGGTGAAATGCGTAGATATTAGGAGGAACACCAGTGGCGAAGGCGGCTTACTGGACGATTACTGACGCT",
    "TACGTAGGTCCCGAGCGTTGTCCGGATTTATTGGGCGTAAAGGGAGCGCAGGCGGTCTTTTAAGTCTGATGTGAAAGCCCCGGGCTTAACCGGGGAGGGTCATTGGAAACTGGAAAACTTGAGTGCAGAAGAGGAGAGTGGAATTCCACGTGTAGCGGTGAAATGCGTAGAGATGTGGAGGAACACCAGTGGCGAAGGCGACTCTCTGGGCTGTAACTGACGCT"
]

def reverse_complement(seq):
    comp = {'A':'T', 'T':'A', 'C':'G', 'G':'C', 'N':'N'}
    return ''.join(comp.get(b, b) for b in reversed(seq))

def generate_quality_string(length, mean_q=35, noise=5):
    """Generate realistic quality scores (Phred+33)"""
    quals = []
    for i in range(length):
        # Quality degrades slightly toward 3' end
        pos_factor = max(0, 1 - (i / length) * 0.2)
        q = int(random.gauss(mean_q * pos_factor, noise))
        q = max(2, min(40, q))  # Clamp to Q2-Q40
        quals.append(chr(q + 33))
    return ''.join(quals)

def introduce_errors(seq, error_rate=0.001):
    """Introduce sequencing errors at specified rate"""
    bases = list(seq)
    for i in range(len(bases)):
        if random.random() < error_rate:
            bases[i] = random.choice(['A', 'C', 'G', 'T'])
    return ''.join(bases)

def generate_read_pair(template, read_length=150, error_rate=0.001):
    """Generate a paired-end read from template with primers prepended.

    R1 = PRIMER_FWD + amplicon_sequence[:bio_len]
    R2 = PRIMER_REV + RC(amplicon_sequence)[:bio_len]

    The primer prefix ensures cutadapt (--discard-untrimmed) keeps the read
    and trims the primer, leaving the biological sequence for DADA2.
    read_length is the total read length including the primer.
    """
    fwd_len = len(PRIMER_FWD)
    rev_len = len(PRIMER_REV)

    # Biological portion lengths after primer removal
    bio_len_r1 = read_length - fwd_len
    bio_len_r2 = read_length - rev_len

    r1_bio = template[:bio_len_r1]
    r2_template = reverse_complement(template)
    r2_bio = r2_template[:bio_len_r2]

    # Introduce errors in the biological portion only
    r1_bio = introduce_errors(r1_bio, error_rate)
    r2_bio = introduce_errors(r2_bio, error_rate)

    # Prepend concrete primer sequences
    r1_seq = PRIMER_FWD + r1_bio
    r2_seq = PRIMER_REV + r2_bio

    # Generate quality strings (high quality for primer region, realistic for bio)
    r1_qual = generate_quality_string(len(r1_seq), mean_q=37)
    r2_qual = generate_quality_string(len(r2_seq), mean_q=35)  # R2 slightly lower

    return r1_seq, r1_qual, r2_seq, r2_qual

def write_fastq_gz(filename, reads):
    """Write reads to gzipped FASTQ file"""
    with gzip.open(filename, 'wt') as f:
        for i, (seq, qual) in enumerate(reads, 1):
            f.write(f"@SEQ_{i}:1:N:0:TESTDATA\n")
            f.write(f"{seq}\n")
            f.write(f"+\n")
            f.write(f"{qual}\n")

def main():
    random.seed(42)  # Reproducible

    test_dir = Path(__file__).resolve().parent
    test_dir.mkdir(parents=True, exist_ok=True)

    n_reads_per_sample = 1000
    read_length = 150

    print(f"Primer sequences embedded in reads:")
    print(f"  FWD (515F): {PRIMER_FWD}")
    print(f"  REV (806R): {PRIMER_REV}")
    print(f"  -> cutadapt will trim these; non-empty FASTQs passed to DADA2")
    print()

    # Generate two synthetic samples
    for sample_id in ['TEST1', 'TEST2']:
        r1_reads = []
        r2_reads = []

        for _ in range(n_reads_per_sample):
            # Select random template (simulates different taxa)
            template = random.choice(TEMPLATES)

            # Add some abundance variation (some templates more common)
            if random.random() < 0.3:
                template = TEMPLATES[0]  # Dominant taxon

            r1_seq, r1_qual, r2_seq, r2_qual = generate_read_pair(
                template, read_length=read_length
            )

            r1_reads.append((r1_seq, r1_qual))
            r2_reads.append((r2_seq, r2_qual))

        # Write to files
        r1_path = test_dir / f"{sample_id}_R1.fastq.gz"
        r2_path = test_dir / f"{sample_id}_R2.fastq.gz"

        write_fastq_gz(r1_path, r1_reads)
        write_fastq_gz(r2_path, r2_reads)

        print(f"Generated {sample_id}: {n_reads_per_sample} read pairs")
        print(f"  R1: {r1_path}")
        print(f"  R2: {r2_path}")

    # Keep paths repository-relative so the generated sheets work on any clone.
    sheet = (
        "sample_id,fastq_1,fastq_2\n"
        "TEST1,test/TEST1_R1.fastq.gz,test/TEST1_R2.fastq.gz\n"
        "TEST2,test/TEST2_R1.fastq.gz,test/TEST2_R2.fastq.gz\n"
    )
    for sheet_name in ("samplesheet_synthetic.csv", "samplesheet.csv"):
        (test_dir / sheet_name).write_text(sheet, encoding="utf-8")

    print("\nCreated test/samplesheet_synthetic.csv and test/samplesheet.csv")
    print(f"\nExpected results:")
    print(f"  - 3 ASVs (from 3 template sequences)")
    bio_r1 = read_length - len(PRIMER_FWD)
    bio_r2 = read_length - len(PRIMER_REV)
    overlap = bio_r1 + bio_r2 - len(TEMPLATES[0])
    print(f"  - ~{overlap} bp overlap for merging (200 bp amplicon, {bio_r1}+{bio_r2} bp biological reads)")
    print(f"  - High merge success rate (>95%)")
    print(f"  - Low error rate, minimal chimeras")


if __name__ == '__main__':
    main()
