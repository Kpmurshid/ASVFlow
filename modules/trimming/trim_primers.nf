nextflow.enable.dsl = 2

process TRIM_PRIMERS {

    tag { sample_id }

    publishDir "${params.outdir}/trimmed", mode: 'copy', pattern: '*.fastq.gz'
    publishDir "${params.outdir}/trimming_reports", mode: 'copy', pattern: '*.{json,txt}'

    input:
        tuple val(sample_id), path(r1), path(r2)

    output:
        tuple val(sample_id), path("${sample_id}_R1_trimmed.fastq.gz"), path("${sample_id}_R2_trimmed.fastq.gz"), emit: trimmed_reads
        path("${sample_id}.cutadapt.json"), emit: trim_json
        path("${sample_id}.cutadapt.txt"),  emit: trim_log

    script:
    def rc = { seq ->
        def comp = ['A':'T', 'T':'A', 'C':'G', 'G':'C',
                    'R':'Y', 'Y':'R', 'S':'S', 'W':'W', 'K':'M', 'M':'K',
                    'B':'V', 'V':'B', 'D':'H', 'H':'D', 'N':'N',
                    'a':'t', 't':'a', 'c':'g', 'g':'c',
                    'r':'y', 'y':'r', 's':'s', 'w':'w', 'k':'m', 'm':'k',
                    'b':'v', 'v':'b', 'd':'h', 'h':'d', 'n':'n']
        seq.reverse().collect { comp[it] ?: it }.join('')
    }
    
    def fwd = params.primer_fwd ?: ''
    def rev = params.primer_rev ?: ''
    def rc_fwd = fwd ? rc(fwd) : ''
    def rc_rev = rev ? rc(rev) : ''
    
    """
    set -euo pipefail
    
    cutadapt \\
        -g ${fwd} \\
        -a ${rc_rev} \\
        -G ${rev} \\
        -A ${rc_fwd} \\
        -e ${params.trim_error_rate} \\
        -O ${params.trim_min_overlap} \\
        --minimum-length ${params.trim_min_length} \\
        ${params.discard_untrimmed ? '--discard-untrimmed' : ''} \\
        --json ${sample_id}.cutadapt.json \\
        -o ${sample_id}_R1_trimmed.fastq.gz \\
        -p ${sample_id}_R2_trimmed.fastq.gz \\
        ${r1} ${r2} \\
        > ${sample_id}.cutadapt.txt
    """

    stub:
    """
    touch ${sample_id}_R1_trimmed.fastq.gz
    touch ${sample_id}_R2_trimmed.fastq.gz
    touch ${sample_id}.cutadapt.json
    touch ${sample_id}.cutadapt.txt
    """
}
