nextflow.enable.dsl = 2

// Import module to test
include { ASSIGN_TAXONOMY } from '../../modules/taxonomy/assign_taxonomy.nf'

workflow {

    // Define input channels from test fixtures
    seqtab_rds_ch = Channel.fromPath(params.test_seqtab_rds)
    seqtab_fasta_ch = Channel.fromPath(params.test_seqtab_fasta)
    silva_ref_ch = Channel.fromPath(params.silva_genus_ref)

    // Run module
    ASSIGN_TAXONOMY(
        seqtab_rds_ch,
        seqtab_fasta_ch,
        silva_ref_ch
    )
}
