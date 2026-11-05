#!/usr/bin/env python3
"""
Generate synthetic paired-end FASTQ data for DADA2 testing.
Creates reads with known sequences, sufficient overlap, and controlled quality.
"""

import gzip
import random
import sys

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
    """Generate a paired-end read from template with sufficient overlap"""
    # R1 starts at position 0
    # R2 starts from the end (reverse complement)
    # For 200 bp template with 150 bp reads: 100 bp overlap
    
    r1_seq = template[:read_length]
    r2_template = reverse_complement(template)
    r2_seq = r2_template[:read_length]
    
    # Introduce errors
    r1_seq = introduce_errors(r1_seq, error_rate)
    r2_seq = introduce_errors(r2_seq, error_rate)
    
    # Generate quality strings
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
    
    n_reads_per_sample = 1000
    read_length = 150
    
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
        r1_file = f"test/{sample_id}_R1.fastq.gz"
        r2_file = f"test/{sample_id}_R2.fastq.gz"
        
        write_fastq_gz(r1_file, r1_reads)
        write_fastq_gz(r2_file, r2_reads)
        
        print(f"Generated {sample_id}: {n_reads_per_sample} read pairs")
        print(f"  R1: {r1_file}")
        print(f"  R2: {r2_file}")
    
    # Create samplesheet
    with open('test/samplesheet_synthetic.csv', 'w') as f:
        f.write("sample_id,fastq_1,fastq_2\n")
        f.write(f"TEST1,{sys.path[0]}/test/TEST1_R1.fastq.gz,{sys.path[0]}/test/TEST1_R2.fastq.gz\n")
        f.write(f"TEST2,{sys.path[0]}/test/TEST2_R1.fastq.gz,{sys.path[0]}/test/TEST2_R2.fastq.gz\n")
    
    print("\nCreated test/samplesheet_synthetic.csv")
    print(f"\nExpected results:")
    print(f"  - 3 ASVs (from 3 template sequences)")
    print(f"  - ~100 bp overlap for merging (200 bp amplicon, 150+150 bp reads)")
    print(f"  - High merge success rate (>95%)")
    print(f"  - Low error rate, minimal chimeras")

if __name__ == '__main__':
    main()
