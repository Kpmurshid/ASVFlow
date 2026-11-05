nextflow.enable.dsl = 2

process PLOT_QUALITY_PROFILE {

    tag { "quality_profiles" }

    publishDir "${params.outdir}/dada2/qc", mode: 'copy'

    input:
        path(fastq_files)

    output:
        path("quality_profile_R1.pdf"), emit: profile_r1
        path("quality_profile_R2.pdf"), emit: profile_r2

    script:
    """
    #!/usr/bin/env Rscript
    library(dada2)

    r1_files <- sort(list.files(".", pattern="_R1.*\\\\.fastq\\\\.gz\$", full.names=TRUE))
    r2_files <- sort(list.files(".", pattern="_R2.*\\\\.fastq\\\\.gz\$", full.names=TRUE))

    if (length(r1_files) == 0) stop("No R1 files found")
    if (length(r2_files) == 0) stop("No R2 files found")

    cat("Plotting quality profiles for", length(r1_files), "R1 files\\n")
    pdf("quality_profile_R1.pdf", width=10, height=6)
    print(plotQualityProfile(r1_files, aggregate=TRUE))
    dev.off()

    cat("Plotting quality profiles for", length(r2_files), "R2 files\\n")
    pdf("quality_profile_R2.pdf", width=10, height=6)
    print(plotQualityProfile(r2_files, aggregate=TRUE))
    dev.off()
    """

    stub:
    """
    touch quality_profile_R1.pdf quality_profile_R2.pdf
    """
}
