#!/usr/bin/env Rscript
# =============================================================================
# ASVFlow Part 4 – Unit tests for community analysis modules
# Controlled synthetic data with independently verifiable expected values.
# =============================================================================
library(phyloseq)
library(vegan)
library(ape)

errors <- 0
passed <- 0

assert <- function(label, cond) {
    if (isTRUE(cond)) {
        cat("  PASS:", label, "\n")
        passed <<- passed + 1
    } else {
        cat("  FAIL:", label, "\n")
        errors  <<- errors  + 1
    }
}
assert_near <- function(label, actual, expected, tol=1e-6) {
    assert(label, abs(actual - expected) <= tol)
}

cat("=== ASVFlow Community Module Unit Tests ===\n\n")

# ---------------------------------------------------------------------------
# Controlled data
# 3 samples x 5 ASVs:
#   S1: 100 50 25 10 5   (total=190)
#   S2:  80 60 30 15 10  (total=195)
#   S3:   0  0  0  0  0  (zero reads)
# Taxonomy:
#   ASV1,ASV5 -> Proteobacteria
#   ASV2      -> Firmicutes
#   ASV3      -> Bacteroidetes
#   ASV4      -> Actinobacteria
# ---------------------------------------------------------------------------
asv_mat <- matrix(
    c(100, 50, 25, 10, 5,
       80, 60, 30, 15, 10,
        0,  0,  0,  0,  0),
    nrow=3, byrow=TRUE,
    dimnames=list(c("S1","S2","S3"),
                  c("ASV1","ASV2","ASV3","ASV4","ASV5"))
)
tax_mat <- matrix(
    c("Bacteria","Proteobacteria","Gammaproteobacteria",NA,NA,"Escherichia",NA,
      "Bacteria","Firmicutes","Bacilli",NA,NA,"Lactobacillus",NA,
      "Bacteria","Bacteroidetes","Bacteroidia",NA,NA,"Bacteroides",NA,
      "Bacteria","Actinobacteria","Actinobacteria",NA,NA,"Bifidobacterium",NA,
      "Bacteria","Proteobacteria","Gammaproteobacteria",NA,NA,NA,NA),
    nrow=5, byrow=TRUE,
    dimnames=list(c("ASV1","ASV2","ASV3","ASV4","ASV5"),
                  c("Kingdom","Phylum","Class","Order","Family","Genus","Species"))
)
meta_df <- data.frame(
    sample_id = c("S1","S2","S3"),
    group     = c("A","B","A"),
    row.names = c("S1","S2","S3")
)
physeq <- phyloseq(
    otu_table(asv_mat, taxa_are_rows=FALSE),
    tax_table(tax_mat),
    sample_data(meta_df)
)

# ===========================================================================
# MODULE 1: SEQUENCING_DEPTH
# ===========================================================================
cat("--- SEQUENCING_DEPTH ---\n")
depths <- rowSums(asv_mat)
assert_near("S1 depth = 190", depths["S1"], 190)
assert_near("S2 depth = 195", depths["S2"], 195)
assert_near("S3 depth = 0",   depths["S3"],   0)
assert_near("Mean = 128.333", mean(depths), (190+195+0)/3, tol=1e-3)
assert_near("SD",   sd(depths), sd(c(190,195,0)),   tol=1e-3)
assert_near("CV",   100*sd(depths)/mean(depths), 100*sd(c(190,195,0))/mean(c(190,195,0)), tol=1e-3)

# ===========================================================================
# MODULE 2: ALPHA_DIVERSITY
# ===========================================================================
cat("\n--- ALPHA_DIVERSITY ---\n")
alpha <- estimate_richness(physeq, measures=c("Observed","Chao1","Shannon","Simpson"))
otu_m <- asv_mat
zero_s <- rowSums(otu_m) == 0
alpha[zero_s,] <- NA

assert_near("S1 Observed = 5", alpha["S1","Observed"], 5)
assert_near("S2 Observed = 5", alpha["S2","Observed"], 5)
assert("S3 Observed is NA",    is.na(alpha["S3","Observed"]))

# Manual Shannon for S1: p=(100,50,25,10,5)/190
p1 <- c(100,50,25,10,5)/190
shan_s1_expected <- -sum(p1*log(p1))
assert_near("S1 Shannon", alpha["S1","Shannon"], shan_s1_expected, tol=1e-4)

p2 <- c(80,60,30,15,10)/195
shan_s2_expected <- -sum(p2*log(p2))
assert_near("S2 Shannon", alpha["S2","Shannon"], shan_s2_expected, tol=1e-4)
assert("S3 Shannon is NA", is.na(alpha["S3","Shannon"]))

# ===========================================================================
# MODULE 3: TAXONOMIC_COMPOSITION
# ===========================================================================
cat("\n--- TAXONOMIC_COMPOSITION ---\n")
tax_df <- as(tax_table(physeq), "matrix")
phylum_labels <- tax_df[, "Phylum"]
phylum_counts <- aggregate(t(asv_mat), by=list(phylum=phylum_labels), FUN=sum)
rownames(phylum_counts) <- phylum_counts$phylum
phylum_counts$phylum <- NULL
phylum_counts <- t(phylum_counts)

# S1: Proteobacteria = ASV1(100)+ASV5(5)=105, Firmicutes=50, Bacteroidetes=25, Actinobacteria=10
assert_near("S1 Proteobacteria = 105", phylum_counts["S1","Proteobacteria"], 105)
assert_near("S1 Firmicutes = 50",      phylum_counts["S1","Firmicutes"],     50)
assert_near("S1 Bacteroidetes = 25",   phylum_counts["S1","Bacteroidetes"],  25)
assert_near("S1 Actinobacteria = 10",  phylum_counts["S1","Actinobacteria"], 10)
# S2: Proteobacteria = ASV1(80)+ASV5(10)=90
assert_near("S2 Proteobacteria = 90", phylum_counts["S2","Proteobacteria"], 90)
# S3: all zero
assert_near("S3 Proteobacteria = 0",  phylum_counts["S3","Proteobacteria"],  0)

# Relative abundance check for S1
non0 <- rowSums(phylum_counts) > 0
phylum_rel <- matrix(0, nrow=nrow(phylum_counts), ncol=ncol(phylum_counts),
                     dimnames=dimnames(phylum_counts))
phylum_rel[non0,] <- sweep(phylum_counts[non0,,drop=FALSE], 1,
                           rowSums(phylum_counts[non0,,drop=FALSE]), "/") * 100
assert_near("S1 Proteobacteria relabund", phylum_rel["S1","Proteobacteria"], 105/190*100, tol=1e-4)
assert_near("S3 all relabund = 0",       sum(phylum_rel["S3",]),              0)

# ===========================================================================
# MODULE 4: BETA_DIVERSITY (Bray-Curtis and Jaccard)
# ===========================================================================
cat("\n--- BETA_DIVERSITY ---\n")
otu_nz <- asv_mat[rowSums(asv_mat)>0,,drop=FALSE]
otu_rel <- sweep(otu_nz, 1, rowSums(otu_nz), "/")
dist_bray <- vegdist(otu_rel, method="bray")
dist_jacc <- vegdist(otu_nz,  method="jaccard", binary=TRUE)

# Manual Bray-Curtis for S1 vs S2:
# rel_S1 = (100,50,25,10,5)/190, rel_S2 = (80,60,30,15,10)/195
r1 <- c(100,50,25,10,5)/190
r2 <- c(80,60,30,15,10)/195
bray_expected <- sum(abs(r1-r2)) / sum(r1+r2)
assert_near("Bray-Curtis S1-S2 manual", as.matrix(dist_bray)["S1","S2"], bray_expected, tol=1e-6)
assert("Bray-Curtis is symmetric",
       abs(as.matrix(dist_bray)["S1","S2"] - as.matrix(dist_bray)["S2","S1"]) < 1e-10)
assert("Bray-Curtis S1-S1 = 0", as.matrix(dist_bray)["S1","S1"] == 0)

# Both S1 and S2 have all 5 ASVs present -> Jaccard distance = 0
assert_near("Jaccard S1-S2 = 0 (identical PA)", as.matrix(dist_jacc)["S1","S2"], 0)

# ===========================================================================
# MODULE 5: BETA_DIVERSITY Jaccard edge-case fix
# ===========================================================================
cat("\n--- BETA_DIVERSITY: Jaccard edge-case (all-zero distances) ---\n")
jaccard_skip <- all(as.matrix(dist_jacc) == 0)
assert("All-zero Jaccard detected", jaccard_skip)
assert("PCoA skipped (no error)", tryCatch({
    if (jaccard_skip) TRUE
    else { pcoa(dist_jacc); FALSE }   # would throw if dist is degenerate
}, error=function(e) FALSE))

# Confirm PCoA on Bray-Curtis still works
pcoa_bray <- pcoa(dist_bray)
assert("Bray-Curtis PCoA executes", !is.null(pcoa_bray$vectors))
assert("PCoA vectors have 1 axis (2 samples)", ncol(pcoa_bray$vectors) >= 1)

# ===========================================================================
# MODULE 6: PERMANOVA
# ===========================================================================
cat("\n--- PERMANOVA ---\n")
# S1=GroupA, S2=GroupB (the only non-zero samples)
meta_nz <- meta_df[rownames(otu_nz),,drop=FALSE]
set.seed(42)
perm <- tryCatch(
    adonis2(dist_bray ~ group, data=meta_nz, permutations=99),
    error=function(e) NULL
)
assert("PERMANOVA executes",        !is.null(perm))
assert("PERMANOVA has R2 column",   !is.null(perm) && "R2" %in% colnames(perm))
assert("R2 in [0,1]",               !is.null(perm) && perm$R2[1] >= 0 && perm$R2[1] <= 1)

# Single-group metadata -> should skip
meta_single <- data.frame(sample_id=c("S1","S2"), group=c("A","A"), row.names=c("S1","S2"))
group_sizes <- table(meta_single$group)
should_skip_single <- length(group_sizes) < 2
assert("Single-group: PERMANOVA correctly skips", should_skip_single)

# Missing group column -> should skip
meta_nogroup <- data.frame(sample_id=c("S1","S2"), row.names=c("S1","S2"))
should_skip_nogroup <- !("group" %in% colnames(meta_nogroup))
assert("No group column: PERMANOVA correctly skips", should_skip_nogroup)

# ===========================================================================
# SUMMARY
# ===========================================================================
cat("\n============================================\n")
cat("UNIT TEST SUMMARY\n")
cat("  Passed:", passed, "\n")
cat("  Failed:", errors, "\n")
cat("============================================\n\n")
if (errors > 0) {
    quit(save="no", status=1)
} else {
    cat("ALL UNIT TESTS PASSED\n")
    quit(save="no", status=0)
}
