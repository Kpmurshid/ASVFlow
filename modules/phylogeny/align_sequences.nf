nextflow.enable.dsl = 2

process ALIGN_ASV_SEQUENCES {
    tag { 'phylogeny_alignment' }
    publishDir "${params.outdir}/phylogeny", mode: 'copy'

    input:
        path(fasta)

    output:
        path('asv_alignment.fasta'), emit: alignment
        path('alignment_status.txt'), emit: status

    script:
    """
    count=\$(grep -c '^>' '${fasta}' || true)
    if [ "\$count" -ge 2 ]; then
      mafft --auto '${fasta}' > asv_alignment.fasta 2> mafft.log
      printf 'available\\n' > alignment_status.txt
    else
      cp '${fasta}' asv_alignment.fasta
      printf '%s\\n' "\$([ "\$count" -eq 1 ] && echo insufficient_sequences || echo empty_input)" > alignment_status.txt
    fi
    """

    stub:
    """
    cp '${fasta}' asv_alignment.fasta
    printf 'available\\n' > alignment_status.txt
    """
}
