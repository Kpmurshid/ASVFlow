"""
ASVFlow Output Scanner

Scans output directories for available results and parses execution trace.
Phase 2: Extended with scientific results parsers.
"""

import pandas as pd
from pathlib import Path
from typing import Dict, List, Optional


class OutputScanner:
    """Scan ASVFlow output directory for available results"""

    def __init__(self, outdir: str):
        self.outdir = Path(outdir)

    def get_execution_trace(self, session_id: Optional[str] = None, monitor=None) -> pd.DataFrame:
        """Parse execution trace from Nextflow's task log.

        Args:
            session_id: Nextflow session ID (UUID format). If provided with monitor,
                       retrieves session-specific task data from Nextflow's internal database.
            monitor: NextflowMonitor instance. Required when session_id is provided.

        Returns:
            DataFrame with task execution data, or empty DataFrame if unavailable.

        Note: When session_id is provided, this method uses Nextflow's internal task log
              as the authoritative source and does NOT fall back to trace files, ensuring
              strict session isolation.
        """
        # If session_id is provided, enforce strict session isolation
        if session_id:
            # If monitor is not provided, cannot query session-specific data
            if not monitor:
                return pd.DataFrame()

            # Query Nextflow's internal task log for session-specific data
            try:
                df = monitor.get_task_log(session_id)
                # Return immediately, even if empty - do not fall back to trace files
                # when session_id is explicitly provided
                return df
            except Exception as e:
                print(f"Warning: Failed to get task log from Nextflow: {e}")
                # Return empty DataFrame on failure when session_id is provided
                return pd.DataFrame()

        # Legacy fallback: Only used when session_id is None
        # This preserves backward compatibility for callers without session info

        # Look for timestamped trace files in pipeline_info
        pipeline_info_dir = self.outdir / 'pipeline_info'
        if pipeline_info_dir.exists():
            # Get the most recent trace file
            trace_files = sorted(pipeline_info_dir.glob('trace_*.txt'), reverse=True)
            if trace_files:
                try:
                    df = pd.read_csv(trace_files[0], sep='\t')
                    return df
                except Exception as e:
                    print(f"Warning: Failed to parse {trace_files[0]}: {e}")

        # Legacy fallback: execution_trace.txt in outdir root
        trace_file = self.outdir / 'execution_trace.txt'
        if trace_file.exists():
            try:
                df = pd.read_csv(trace_file, sep='\t')
                return df
            except Exception as e:
                print(f"Warning: Failed to parse execution_trace.txt: {e}")

        return pd.DataFrame()

    def get_task_status_summary(self, session_id: Optional[str] = None, monitor=None) -> Dict[str, int]:
        """Aggregate task counts by status from execution trace.

        Args:
            session_id: Nextflow session ID for session-specific data.
            monitor: NextflowMonitor instance for retrieving task log.

        Note: Only completed/cached tasks appear in execution trace.
        Running tasks are NOT detected by this implementation.
        """
        df = self.get_execution_trace(session_id, monitor)

        if df.empty:
            return {
                'total': 0,
                'completed': 0,
                'cached': 0,
                'failed': 0,
                'aborted': 0
            }

        # Normalize exit codes to numeric, treating non-numeric as NaN
        df['exit_numeric'] = pd.to_numeric(df['exit'], errors='coerce')

        summary = {
            'total': len(df),
            'completed': len(df[df['status'] == 'COMPLETED']),
            'cached': len(df[df['status'] == 'CACHED']),
            'aborted': len(df[df['status'] == 'ABORTED']),
            'failed': len(df[(df['exit_numeric'] != 0) & (df['exit_numeric'].notna()) & (df['status'] != 'ABORTED')])
        }

        return summary

    def scan_available_outputs(self) -> Dict:
        """
        Scan output directory for available result files.
        Returns structured dict with file paths.
        """
        outputs = {
            'qc': {},
            'dada2': {},
            'taxonomy': {},
            'community': {},
            'reports': {}
        }

        # QC outputs
        if (self.outdir / 'qc').exists():
            outputs['qc']['raw_multiqc'] = self._find_file('qc/raw/multiqc_report.html')
            outputs['qc']['trimmed_multiqc'] = self._find_file('qc/trimmed/multiqc_report.html')
            outputs['qc']['raw_fastqc'] = list(self.outdir.glob('qc/raw/*_fastqc.html'))
            outputs['qc']['trimmed_fastqc'] = list(self.outdir.glob('qc/trimmed/*_fastqc.html'))

        # DADA2 outputs
        if (self.outdir / 'dada2').exists():
            outputs['dada2']['seqtab'] = self._find_file('dada2/final/seqtab_nochim.tsv')
            outputs['dada2']['track_reads'] = self._find_file('dada2/final/track_reads.tsv')
            outputs['dada2']['chimera_stats'] = self._find_file('dada2/final/chimera_stats.tsv')
            outputs['dada2']['quality_profiles'] = list(self.outdir.glob('dada2/qc/quality_profile_*.pdf'))
            outputs['dada2']['error_plots'] = list(self.outdir.glob('dada2/error_models/error_plot_*.pdf'))

        # Taxonomy outputs
        if (self.outdir / 'taxonomy').exists():
            outputs['taxonomy']['taxonomy_table'] = self._find_file('taxonomy/taxonomy.tsv')
            outputs['taxonomy']['taxonomy_species'] = self._find_file('taxonomy/taxonomy_species.tsv')
            outputs['taxonomy']['taxonomy_stats'] = self._find_file('taxonomy/taxonomy_stats.tsv')

        # Community analysis outputs (optional)
        if (self.outdir / 'community').exists():
            outputs['community']['alpha_diversity'] = self._find_file('community/alpha_diversity.tsv')
            outputs['community']['alpha_plot'] = self._find_file('community/alpha_diversity.pdf')
            outputs['community']['beta_bray'] = self._find_file('community/beta_diversity_bray_pcoa.tsv')
            outputs['community']['beta_jaccard'] = self._find_file('community/beta_diversity_jaccard_pcoa.tsv')
            outputs['community']['beta_bray_plot'] = self._find_file('community/beta_diversity_bray_pcoa.pdf')
            outputs['community']['beta_jaccard_plot'] = self._find_file('community/beta_diversity_jaccard_pcoa.pdf')
            outputs['community']['rarefaction'] = self._find_file('community/rarefaction_curves.pdf')
            outputs['community']['sequencing_depth'] = self._find_file('community/sequencing_depth.tsv')
            outputs['community']['comp_phylum_counts'] = self._find_file('community/composition_phylum_counts.tsv')
            outputs['community']['comp_phylum_relabund'] = self._find_file('community/composition_phylum_relabund.tsv')
            outputs['community']['comp_genus_counts'] = self._find_file('community/composition_genus_counts.tsv')
            outputs['community']['comp_genus_relabund'] = self._find_file('community/composition_genus_relabund.tsv')

        # Nextflow reports
        outputs['reports']['execution_report'] = self._find_file('execution_report.html')
        outputs['reports']['execution_timeline'] = self._find_file('execution_timeline.html')
        outputs['reports']['execution_trace'] = self._find_file('execution_trace.txt')

        return outputs

    def _find_file(self, relative_path: str) -> Optional[Path]:
        """Check if file exists and return Path or None"""
        file_path = self.outdir / relative_path
        return file_path if file_path.exists() else None

    def get_output_stats(self) -> Dict:
        """Get summary statistics about available outputs"""
        outputs = self.scan_available_outputs()

        stats = {
            'qc_available': any(outputs['qc'].values()),
            'dada2_available': any(outputs['dada2'].values()),
            'taxonomy_available': any(outputs['taxonomy'].values()),
            'community_available': any(outputs['community'].values()),
            'reports_available': any(outputs['reports'].values())
        }

        return stats

    # Phase 2: Scientific results parsers

    def get_dada2_track_reads(self) -> Optional[pd.DataFrame]:
        """Parse DADA2 read tracking file"""
        track_file = self._find_file('dada2/final/track_reads.tsv')
        if not track_file:
            return None

        try:
            df = pd.read_csv(track_file, sep='\t')
            return df
        except Exception as e:
            print(f"Warning: Failed to parse track_reads.tsv: {e}")
            return None

    def get_dada2_chimera_stats(self) -> Optional[pd.DataFrame]:
        """Parse DADA2 chimera removal statistics"""
        chimera_file = self._find_file('dada2/final/chimera_stats.tsv')
        if not chimera_file:
            return None

        try:
            df = pd.read_csv(chimera_file, sep='\t')
            return df
        except Exception as e:
            print(f"Warning: Failed to parse chimera_stats.tsv: {e}")
            return None

    def get_dada2_seqtab(self) -> Optional[pd.DataFrame]:
        """Parse DADA2 ASV sequence table"""
        seqtab_file = self._find_file('dada2/final/seqtab_nochim.tsv')
        if not seqtab_file:
            return None

        try:
            # First column is ASV_ID (index)
            df = pd.read_csv(seqtab_file, sep='\t', index_col=0)
            return df
        except Exception as e:
            print(f"Warning: Failed to parse seqtab_nochim.tsv: {e}")
            return None

    def get_taxonomy(self) -> Optional[pd.DataFrame]:
        """Parse taxonomy table"""
        tax_file = self._find_file('taxonomy/taxonomy.tsv')
        if not tax_file:
            return None

        try:
            df = pd.read_csv(tax_file, sep='\t')
            return df
        except Exception as e:
            print(f"Warning: Failed to parse taxonomy.tsv: {e}")
            return None

    def get_taxonomy_stats(self) -> Optional[pd.DataFrame]:
        """Parse taxonomy statistics"""
        stats_file = self._find_file('taxonomy/taxonomy_stats.tsv')
        if not stats_file:
            return None

        try:
            df = pd.read_csv(stats_file, sep='\t')
            return df
        except Exception as e:
            print(f"Warning: Failed to parse taxonomy_stats.tsv: {e}")
            return None

    def get_alpha_diversity(self) -> Optional[pd.DataFrame]:
        """Parse alpha diversity metrics"""
        alpha_file = self._find_file('community/alpha_diversity.tsv')
        if not alpha_file:
            return None

        try:
            df = pd.read_csv(alpha_file, sep='\t')
            return df
        except Exception as e:
            print(f"Warning: Failed to parse alpha_diversity.tsv: {e}")
            return None

    def get_beta_diversity_pcoa(self, metric='bray') -> Optional[pd.DataFrame]:
        """Parse beta diversity PCoA coordinates

        Args:
            metric: 'bray' or 'jaccard'
        """
        if metric == 'bray':
            pcoa_file = self._find_file('community/beta_diversity_bray_pcoa.tsv')
        elif metric == 'jaccard':
            pcoa_file = self._find_file('community/beta_diversity_jaccard_pcoa.tsv')
        else:
            raise ValueError(f"Invalid metric: {metric}. Use 'bray' or 'jaccard'")

        if not pcoa_file:
            return None

        try:
            df = pd.read_csv(pcoa_file, sep='\t')
            return df
        except Exception as e:
            print(f"Warning: Failed to parse beta diversity PCoA: {e}")
            return None

    def get_taxonomic_composition(self, rank='genus', abundance_type='relabund') -> Optional[pd.DataFrame]:
        """Parse taxonomic composition tables

        Args:
            rank: 'phylum' or 'genus'
            abundance_type: 'counts' or 'relabund'
        """
        if rank not in ['phylum', 'genus']:
            raise ValueError(f"Invalid rank: {rank}. Use 'phylum' or 'genus'")
        if abundance_type not in ['counts', 'relabund']:
            raise ValueError(f"Invalid type: {abundance_type}. Use 'counts' or 'relabund'")

        filename = f'community/composition_{rank}_{abundance_type}.tsv'
        comp_file = self._find_file(filename)

        if not comp_file:
            return None

        try:
            # First column is sample ID (index)
            df = pd.read_csv(comp_file, sep='\t', index_col=0)
            return df
        except Exception as e:
            print(f"Warning: Failed to parse {filename}: {e}")
            return None
