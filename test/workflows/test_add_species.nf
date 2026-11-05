nextflow.enable.dsl = 2

// Import module to test
include { ADD_SPECIES } from '../../modules/taxonomy/add_species.nf'

workflow {

    // Define input channels from test fixtures
    taxonomy_rds_ch = Channel.fromPath(params.test_taxonomy_rds)
    taxonomy_tsv_ch = Channel.fromPath(params.test_taxonomy_tsv)
    silva_ref_ch = Channel.fromPath(params.silva_species_ref)

    // Run module
    ADD_SPECIES(
        taxonomy_rds_ch,
        taxonomy_tsv_ch,
        silva_ref_ch
    )
}
