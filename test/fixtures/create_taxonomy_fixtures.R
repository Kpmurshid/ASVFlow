#!/usr/bin/env Rscript
# Create test fixtures for taxonomy module testing

library(dada2)

cat("Creating taxonomy test fixtures...\n\n")

# Fixture 1: Empty seqtab (0 ASVs)
cat("1. Creating empty fixtures (0 ASVs)\n")
seqtab_empty <- matrix(
    integer(0),
    nrow = 1,
    ncol = 0,
    dimnames = list("EMPTY_SAMPLE", character(0))
)

saveRDS(seqtab_empty, "test/fixtures/seqtab_empty.rds")
cat("   Created: test/fixtures/seqtab_empty.rds\n")
cat("   Dimensions:", nrow(seqtab_empty), "samples x", ncol(seqtab_empty), "ASVs\n")

# Create matching empty FASTA
writeLines(character(0), "test/fixtures/seqtab_empty.fasta")
cat("   Created: test/fixtures/seqtab_empty.fasta (0 sequences)\n\n")

# Fixture 2: Small valid seqtab (2 ASVs with real sequences)
cat("2. Creating small valid fixtures (2 ASVs)\n")
seqtab_small <- matrix(
    c(100, 200),
    nrow = 1,
    ncol = 2,
    dimnames = list(
        "TEST_SAMPLE",
        c(
            "ACGTACGTACGTACGTACGT",  # 20bp sequence
            "GCTAGCTAGCTAGCTAGCTA"   # 20bp sequence
        )
    )
)

saveRDS(seqtab_small, "test/fixtures/seqtab_small.rds")
cat("   Created: test/fixtures/seqtab_small.rds\n")
cat("   Dimensions:", nrow(seqtab_small), "samples x", ncol(seqtab_small), "ASVs\n")

# Create matching FASTA with ASV IDs
fasta_small <- c(
    ">ASV_0001",
    "ACGTACGTACGTACGTACGT",
    ">ASV_0002",
    "GCTAGCTAGCTAGCTAGCTA"
)
writeLines(fasta_small, "test/fixtures/seqtab_small.fasta")
cat("   Created: test/fixtures/seqtab_small.fasta (2 sequences)\n\n")

# Fixture 3: Multiline FASTA (to test robust parsing)
cat("3. Creating multiline FASTA fixture\n")
fasta_multiline <- c(
    ">ASV_0001",
    "ACGTACGTACGT",
    "ACGTACGT",  # Split across 2 lines
    ">ASV_0002",
    "GCTAGCTA",
    "GCTAGCTA",
    "GCTA"       # Split across 3 lines
)
writeLines(fasta_multiline, "test/fixtures/seqtab_multiline.fasta")
cat("   Created: test/fixtures/seqtab_multiline.fasta (multiline sequences)\n\n")

# Fixture 4: Empty taxonomy for ADD_SPECIES testing
cat("4. Creating empty taxonomy fixtures\n")
tax_empty <- matrix(
    character(0),
    nrow = 0,
    ncol = 6,
    dimnames = list(NULL, c("Kingdom", "Phylum", "Class", "Order", "Family", "Genus"))
)
saveRDS(tax_empty, "test/fixtures/taxonomy_empty.rds")
cat("   Created: test/fixtures/taxonomy_empty.rds\n")

writeLines("ASV_ID\tsequence\tKingdom\tPhylum\tClass\tOrder\tFamily\tGenus",
           "test/fixtures/taxonomy_empty.tsv")
cat("   Created: test/fixtures/taxonomy_empty.tsv (header only)\n\n")

# Fixture 5: Mismatched FASTA/RDS (for validation testing)
cat("5. Creating mismatched FASTA (different sequences than small RDS)\n")
fasta_mismatch <- c(
    ">ASV_0001",
    "TTTTTTTTTTTTTTTTTTT",  # Different sequence
    ">ASV_0002",
    "AAAAAAAAAAAAAAAAAAA"   # Different sequence
)
writeLines(fasta_mismatch, "test/fixtures/seqtab_mismatch.fasta")
cat("   Created: test/fixtures/seqtab_mismatch.fasta\n\n")

# Fixture 6: Duplicate ASV IDs in FASTA
cat("6. Creating duplicate ID FASTA\n")
fasta_dup_id <- c(
    ">ASV_0001",
    "ACGTACGTACGTACGTACGT",
    ">ASV_0001",  # Duplicate ID
    "GCTAGCTAGCTAGCTAGCTA"
)
writeLines(fasta_dup_id, "test/fixtures/seqtab_duplicate_id.fasta")
cat("   Created: test/fixtures/seqtab_duplicate_id.fasta\n\n")

# Fixture 7: Duplicate sequences in FASTA
cat("7. Creating duplicate sequence FASTA\n")
fasta_dup_seq <- c(
    ">ASV_0001",
    "ACGTACGTACGTACGTACGT",
    ">ASV_0002",
    "ACGTACGTACGTACGTACGT"  # Duplicate sequence
)
writeLines(fasta_dup_seq, "test/fixtures/seqtab_duplicate_seq.fasta")
cat("   Created: test/fixtures/seqtab_duplicate_seq.fasta\n\n")

# Fixture 8: Invalid DNA characters
cat("8. Creating invalid DNA character FASTA\n")
fasta_invalid <- c(
    ">ASV_0001",
    "ACGTACGTACGTACGTACGT",
    ">ASV_0002",
    "GCTAGCTAGZXCTAGCTAGC"  # Contains Z and X (invalid)
)
writeLines(fasta_invalid, "test/fixtures/seqtab_invalid_dna.fasta")
cat("   Created: test/fixtures/seqtab_invalid_dna.fasta\n\n")

cat("All fixtures created successfully!\n")
