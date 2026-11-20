nextflow.enable.dsl = 2

process PHYLOGENETIC_DIVERSITY {
    tag { 'phylogenetic_diversity' }
    publishDir "${params.outdir}/community", mode: 'copy'
    input:
        path(phyloseq_rds)
        path(tree_file)
        path(metadata_file)
        path(calculation_script)
    output:
        path('faith_pd.tsv'), emit: faith_pd
        path('phylogenetic_diversity_status.txt'), emit: status
        path('beta_diversity_weighted_unifrac_pcoa.tsv'), emit: weighted
        path('beta_diversity_unweighted_unifrac_pcoa.tsv'), emit: unweighted
        path('beta_diversity_phylogenetic_stats.tsv'), emit: stats
        path('beta_diversity_distances_weighted_unifrac.rds'), emit: weighted_dist
        path('beta_diversity_distances_unweighted_unifrac.rds'), emit: unweighted_dist
    script:
    """
    Rscript '${calculation_script}' '${phyloseq_rds}' '${tree_file}' . '${metadata_file}'
    """

    stub:
    """
    printf 'sample_id\tFaith_PD\tstatus\trooting\nS1\tNA\tunavailable\tnone\n' > faith_pd.tsv
    printf 'unavailable\n' > phylogenetic_diversity_status.txt
    printf 'sample_id\tPC1\tPC2\nS1\tNA\tNA\n' > beta_diversity_weighted_unifrac_pcoa.tsv
    cp beta_diversity_weighted_unifrac_pcoa.tsv beta_diversity_unweighted_unifrac_pcoa.tsv
    printf 'metric\tPC\teigenvalue\tvariance_explained\n' > beta_diversity_phylogenetic_stats.tsv
    touch beta_diversity_distances_weighted_unifrac.rds beta_diversity_distances_unweighted_unifrac.rds
    """
}
