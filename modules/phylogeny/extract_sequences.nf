nextflow.enable.dsl = 2

process EXTRACT_ASV_SEQUENCES {
    tag { 'phylogeny_sequences' }
    publishDir "${params.outdir}/phylogeny", mode: 'copy'

    input:
        path(seqtab_rds)

    output:
        path('asv_sequences.fasta'), emit: sequences
        path('asv_sequence_ids.tsv'), emit: ids

    script:
    """
    #!/usr/bin/env Rscript
    seqtab <- readRDS('${seqtab_rds}')
    seqs <- colnames(seqtab)
    asv_ids <- paste0('ASV_', sprintf('%04d', seq_along(seqs)))
    con <- file('asv_sequences.fasta', 'w')
    map <- file('asv_sequence_ids.tsv', 'w')
    writeLines('ASV_ID\tsequence', map)
    if (length(seqs) > 0 && !is.null(seqs)) {
      for (i in seq_along(seqs)) {
        writeLines(paste0('>', asv_ids[i]), con)
        writeLines(seqs[i], con)
        writeLines(paste(asv_ids[i], seqs[i], sep='\t'), map)
      }
    }
    close(con); close(map)
    cat('Extracted', length(seqs), 'representative ASV sequences\\n')
    """

    stub:
    """
    printf '>ASV_0001\\nACGT\\n>ASV_0002\\nACGA\\n' > asv_sequences.fasta
    printf 'ASV_ID\\tsequence\\nASV_0001\\tACGT\\nASV_0002\\tACGA\\n' > asv_sequence_ids.tsv
    """
}
