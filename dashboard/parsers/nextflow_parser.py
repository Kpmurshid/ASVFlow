"""
Nextflow Execution Metadata Parser

Parses Nextflow metadata using:
1. nextflow log command (reliable session info)
2. .nextflow/history file (fallback)
"""

import subprocess
import re
from pathlib import Path
from typing import Dict, List, Optional
import pandas as pd


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
        command = run_info.get('command', '')

        # Look for --outdir parameter
        match = re.search(r'--outdir\s+(\S+)', command)
        if match:
            return match.group(1)

        # Default
        return 'results'

    def get_task_log(self, session_id: str) -> pd.DataFrame:
        """Get task-level details using nextflow log <session_id>

        Args:
            session_id: Nextflow session ID (UUID format)

        Returns:
            DataFrame with task execution data for the specified session
        """
        try:
            result = subprocess.run(
                ["nextflow", "log", session_id, "-f",
                 "task_id,hash,name,status,exit,submit,duration,realtime,pcpu,peak_rss"],
                cwd=self.project_dir,
                capture_output=True,
                text=True,
                timeout=10
            )

            if result.returncode != 0:
                return pd.DataFrame()

            lines = result.stdout.strip().split('\n')
            if not lines:
                return pd.DataFrame()

            # Parse tab-separated output
            data = []
            for line in lines:
                parts = line.split('\t')
                if len(parts) >= 10:
                    data.append({
                        'task_id': parts[0],
                        'hash': parts[1],
                        'name': parts[2],
                        'status': parts[3],
                        'exit': parts[4],
                        'submit': parts[5],
                        'duration': parts[6],
                        'realtime': parts[7],
                        'pcpu': parts[8],
                        'peak_rss': parts[9]
                    })

            return pd.DataFrame(data)

        except Exception as e:
            print(f"Warning: Failed to get task log: {e}")
            return pd.DataFrame()
