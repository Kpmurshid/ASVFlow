"""
Nextflow Execution Metadata Parser

Parses Nextflow metadata using:
1. nextflow log command (reliable session info)
2. .nextflow/history file (fallback)
"""

import subprocess
import re
import json
import shlex
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional


class NextflowMonitor:
    """Monitor Nextflow execution metadata"""

    def __init__(self, project_dir: str = "."):
        self.project_dir = Path(project_dir).resolve()
        self.nf_dir = self.project_dir / ".nextflow"
        self.history_file = self.nf_dir / "history"

    def list_runs(self) -> List[Dict]:
        """
        Get all runs using nextflow log command.
        More reliable than parsing .nextflow/history directly.
        """
        try:
            result = subprocess.run(
                ["nextflow", "log"],
                cwd=self.project_dir,
                capture_output=True,
                text=True,
                timeout=5
            )

            if result.returncode != 0:
                return self._parse_history_fallback()

            runs = []
            lines = result.stdout.strip().split('\n')

            # Skip header line
            for line in lines[1:]:
                if not line.strip():
                    continue

                parts = line.split('\t')
                if len(parts) >= 7:
                    runs.append({
                        'timestamp': parts[0].strip(),
                        'duration': parts[1].strip(),
                        'run_name': parts[2].strip(),
                        'status': parts[3].strip(),
                        'revision_id': parts[4].strip(),
                        'session_id': parts[5].strip(),
                        'command': parts[6].strip() if len(parts) > 6 else ''
                    })

            return runs

        except Exception as e:
            print(f"Warning: Failed to run 'nextflow log': {e}")
            return self._parse_history_fallback()

    def _parse_history_fallback(self) -> List[Dict]:
        """Fallback: Parse .nextflow/history file directly"""
        if not self.history_file.exists():
            return []

        runs = []
        try:
            with open(self.history_file, 'r') as f:
                for line in f:
                    parts = line.strip().split('\t')
                    if len(parts) >= 6:
                        runs.append({
                            'timestamp': parts[0],
                            'duration': parts[1],
                            'run_name': parts[2],
                            'status': parts[3],
                            'revision_id': parts[4],
                            'session_id': parts[5],
                            'command': parts[6] if len(parts) > 6 else ''
                        })
        except Exception as e:
            print(f"Warning: Failed to parse history file: {e}")

        return runs

    def get_run_by_name(self, run_name: str) -> Optional[Dict]:
        """Get specific run metadata by run name"""
        runs = self.list_runs()
        for run in runs:
            if run['run_name'] == run_name:
                return run
        return None

    def get_latest_run(self) -> Optional[Dict]:
        """Get the most recent run"""
        runs = self.list_runs()
        return runs[-1] if runs else None

    def get_run_outdir(self, run_info: Dict) -> Optional[str]:
        """Extract output directory from run command"""
        metadata = self._run_metadata(run_info)
        if metadata and metadata.get('outdir'):
            return metadata['outdir']
        tokens = self._command_tokens(run_info)
        value = self._option_value(tokens, '--outdir')
        return value or 'results'

    @staticmethod
    def _command_tokens(run_info: Dict) -> List[str]:
        try:
            return shlex.split(run_info.get('command', ''))
        except ValueError:
            return []

    @staticmethod
    def _option_value(tokens: List[str], option: str) -> Optional[str]:
        for index, token in enumerate(tokens):
            if token == option and index + 1 < len(tokens) and not tokens[index + 1].startswith('-'):
                return tokens[index + 1]
            if token.startswith(option + '='):
                return token.split('=', 1)[1]
        return None

    def _resolved_outdir(self, run_info: Dict) -> Path:
        metadata = self._run_metadata(run_info)
        if metadata and metadata.get('outdir'):
            return Path(metadata['outdir']).expanduser().resolve()
        path = Path(self.get_run_outdir(run_info)).expanduser()
        return (path if path.is_absolute() else self.project_dir / path).resolve()

    def _run_metadata(self, run_info: Dict) -> Optional[Dict]:
        run_key = re.sub(
            r'[^A-Za-z0-9_.-]', '_',
            f"{run_info.get('run_name', '')}_{run_info.get('session_id', '')}"
        )
        metadata_dir = self.project_dir / '.asvflow_dashboard' / 'runs'
        candidates = [metadata_dir / f'{run_key}.json']
        candidates.extend(sorted(metadata_dir.glob(f'{run_key}_*.json')))
        records = []
        for path in candidates:
            try:
                with path.open(encoding='utf-8') as stream:
                    data = json.load(stream)
                if (
                    data.get('version') in (1, 2)
                    and data.get('run_name') == run_info.get('run_name')
                    and data.get('session_id') == run_info.get('session_id')
                    and isinstance(data.get('started_at_ms'), int)
                ):
                    records.append(data)
            except (OSError, ValueError, TypeError):
                continue
        if not records:
            return None

        command = run_info.get('command', '')
        matching_command = [record for record in records if record.get('command_line') == command]
        if matching_command:
            records = matching_command
        try:
            timestamp_ms = int(datetime.strptime(
                run_info['timestamp'], '%Y-%m-%d %H:%M:%S'
            ).timestamp() * 1000)
            return min(records, key=lambda record: abs(record['started_at_ms'] - timestamp_ms))
        except (KeyError, TypeError, ValueError):
            return max(records, key=lambda record: record['started_at_ms'])

    def _artifact_path(self, run_info: Dict, kind: str) -> Path:
        metadata = self._run_metadata(run_info)
        if metadata and metadata.get('artifact_paths', {}).get(kind):
            return Path(metadata['artifact_paths'][kind]).expanduser().resolve()
        options = {
            'trace': ('-with-trace', 'execution_trace.txt'),
            'report': ('-with-report', 'execution_report.html'),
            'timeline': ('-with-timeline', 'execution_timeline.html'),
        }
        option, default_name = options[kind]
        explicit_path = self._option_value(self._command_tokens(run_info), option)
        if not explicit_path:
            return (self._resolved_outdir(run_info) / default_name).resolve()
        path = Path(explicit_path).expanduser()
        if path.is_absolute():
            return path.resolve()
        metadata = self._run_metadata(run_info)
        launch_dir = Path(metadata['launch_dir']) if metadata and metadata.get('launch_dir') else self.project_dir
        return (launch_dir / path).resolve()

    def _artifact_failure_logged(self, run_info: Dict, kind: str, start_ms: int, next_start_ms: Optional[int]) -> bool:
        log_path = self.project_dir / '.nextflow.log'
        try:
            stat_result = log_path.stat()
            log_mtime_ms = stat_result.st_mtime_ns // 1_000_000
            if log_mtime_ms < start_ms or (next_start_ms is not None and log_mtime_ms >= next_start_ms):
                return False
            content = log_path.read_text(encoding='utf-8', errors='replace')
        except OSError:
            return False

        patterns = {
            'trace': ('TraceFileObserver', 'writer'),
            'report': ('Failed to render execution report',),
            'timeline': ('Failed to render execution timeline',),
        }
        if kind == 'trace':
            return 'TraceFileObserver' in content and ('writer' in content or 'trace file' in content.lower())
        return any(pattern in content for pattern in patterns[kind])

    def get_run_artifacts(self, run_info: Dict, runs: Optional[List[Dict]] = None) -> Dict[str, Dict]:
        """Resolve selected-run artifacts and reject files outside that invocation's time window."""
        runs = runs or [run_info]
        metadata = self._run_metadata(run_info)
        run_start_ms = metadata.get('started_at_ms') if metadata else None
        result = {}
        for kind in ('trace', 'report', 'timeline'):
            path = self._artifact_path(run_info, kind)
            later_starts = []
            if run_start_ms is not None:
                for other in runs:
                    if other is run_info or (
                        other.get('run_name') == run_info.get('run_name')
                        and other.get('session_id') == run_info.get('session_id')
                    ):
                        continue
                    other_metadata = self._run_metadata(other)
                    if not other_metadata or other_metadata['started_at_ms'] <= run_start_ms:
                        continue
                    if self._artifact_path(other, kind) == path:
                        later_starts.append(other_metadata['started_at_ms'])
            next_start_ms = min(later_starts) if later_starts else None

            artifact_exists = path.is_file()
            fresh = False
            if artifact_exists and metadata:
                invocation_id = metadata.get('invocation_id')
                invocation_path = invocation_id and invocation_id in path.parts
                if invocation_path:
                    # A unique per-invocation path is the primary identity check.
                    fresh = True
                elif run_start_ms is not None:
                    # Explicit CLI paths may be shared; use workflow.start, which predates
                    # observer initialization, as a secondary freshness check.
                    mtime_ms = path.stat().st_mtime_ns // 1_000_000
                    fresh = mtime_ms >= run_start_ms and (
                        next_start_ms is None or mtime_ms < next_start_ms
                    )

            status = 'Missing'
            if fresh:
                status = 'Available'
            elif run_info.get('status') in ('-', 'RUNNING'):
                status = 'Pending'
            elif run_start_ms is not None and self._artifact_failure_logged(
                run_info, kind, run_start_ms, next_start_ms
            ):
                status = 'Generation failed'
            elif run_info.get('status') in ('OK', 'COMPLETED'):
                status = 'Unavailable'
            elif run_info.get('status') in ('ERR', 'FAILED', 'ABORTED'):
                status = 'Missing (failed/partial run)'

            result[kind] = {
                'path': str(path),
                'status': status,
                'requested': True,
                'run_metadata_available': metadata is not None,
            }
        return result
