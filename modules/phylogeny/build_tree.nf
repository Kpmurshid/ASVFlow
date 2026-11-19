nextflow.enable.dsl = 2

process BUILD_ASV_PHYLOGENY {
    tag { 'phylogeny_tree' }
    publishDir "${params.outdir}/phylogeny", mode: 'copy'

    input:
        path(alignment)
        path(alignment_status)
        path(validator_script)

    output:
        path('asv_tree.nwk'), emit: tree, optional: true
        path('phylogeny_status.txt'), emit: status

    script:
    """
    status=\$(cat '${alignment_status}')
    count=\$(grep -c '^>' '${alignment}' || true)
    if [ "\$status" = available ] && [ "\$count" -ge 2 ]; then
      FastTree -nt '${alignment}' > asv_tree.nwk 2> fasttree.log
      bash '${validator_script}' asv_tree.nwk '${alignment}'
      printf 'available\\n' > phylogeny_status.txt
    elif [ "\$count" -eq 1 ]; then
      label=\$(grep '^>' '${alignment}' | head -1 | sed 's/^>//')
      printf '%s;\\n' "\$label" > asv_tree.nwk
      printf 'insufficient_sequences\\n' > phylogeny_status.txt
    else
      rm -f asv_tree.nwk
      printf '%s\\n' "\$status" > phylogeny_status.txt
    fi
    """

    stub:
    """
    printf '(ASV_0001:0.1,ASV_0002:0.1);\\n' > asv_tree.nwk
    printf 'available\\n' > phylogeny_status.txt
    """
}
