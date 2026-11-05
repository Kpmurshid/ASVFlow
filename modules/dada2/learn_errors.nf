nextflow.enable.dsl = 2

process LEARN_ERRORS {

    tag { "error_learning" }

    publishDir "${params.outdir}/dada2/error_models", mode: 'copy'

    input:
        path(filtered_fastq)

    output:
        tuple path("error_model_F.rds"), path("error_model_R.rds"), emit: error_models
        path("error_plot_F.pdf"), emit: plot_f
        path("error_plot_R.pdf"), emit: plot_r

    script:
    """
    #!/usr/bin/env Rscript
    library(dada2)

    r1_files <- sort(list.files(".", pattern="_R1_filt\\\\.fastq\\\\.gz\$", full.names=TRUE))
    r2_files <- sort(list.files(".", pattern="_R2_filt\\\\.fastq\\\\.gz\$", full.names=TRUE))

    if (length(r1_files) == 0) stop("No R1 filtered files found")
    if (length(r2_files) == 0) stop("No R2 filtered files found")

    cat("Learning errors from", length(r1_files), "R1 files\\n")
    err_f <- learnErrors(r1_files, multithread=${task.cpus}, nbases=${params.dada2_learn_nbases})

    cat("Learning errors from", length(r2_files), "R2 files\\n")
    err_r <- learnErrors(r2_files, multithread=${task.cpus}, nbases=${params.dada2_learn_nbases})

    saveRDS(err_f, "error_model_F.rds")
    saveRDS(err_r, "error_model_R.rds")

    pdf("error_plot_F.pdf", width=10, height=10)
    plotErrors(err_f, nominalQ=TRUE)
    dev.off()

    pdf("error_plot_R.pdf", width=10, height=10)
    plotErrors(err_r, nominalQ=TRUE)
    dev.off()
    """

    stub:
    """
    #!/usr/bin/env Rscript
    saveRDS(list(err_out=matrix(1:10), err_in=matrix(1:10), trans=matrix(1:10)), "error_model_F.rds")
    saveRDS(list(err_out=matrix(1:10), err_in=matrix(1:10), trans=matrix(1:10)), "error_model_R.rds")
    system("touch error_plot_F.pdf error_plot_R.pdf")
    """
}
