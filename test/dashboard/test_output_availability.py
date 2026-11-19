#!/usr/bin/env python3
"""Focused tests for incremental dashboard output discovery and run states."""

import sys
import tempfile
import unittest
from pathlib import Path

PROJECT_DIR = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(PROJECT_DIR / "dashboard"))

from parsers import NextflowMonitor, OutputScanner


class OutputAvailabilityTests(unittest.TestCase):
    def test_all_output_keys_exist_before_directories_are_created(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            scanner = OutputScanner(temp_dir, run_info={"status": "RUNNING"})
            outputs = scanner.scan_available_outputs()

            self.assertIn("seqtab", outputs["dada2"])
            self.assertIsNone(outputs["dada2"]["seqtab"])
            self.assertEqual(outputs["dada2"]["quality_profiles"], [])
            self.assertEqual(scanner.get_artifact_status("dada2", "seqtab"), "Pending")

    def test_missing_outputs_have_distinct_terminal_states(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            completed = OutputScanner(temp_dir, run_info={"status": "OK"})
            failed = OutputScanner(temp_dir, run_info={"status": "ERR"})

            self.assertEqual(completed.get_artifact_status("dada2", "seqtab"), "Unavailable")
            self.assertEqual(failed.get_artifact_status("dada2", "seqtab"), "Missing (failed/partial run)")
            self.assertIn("completed", completed.artifact_status_message("dada2", "seqtab", "ASV table"))
            self.assertIn("failed or partial", failed.artifact_status_message("dada2", "seqtab", "ASV table"))

    def test_artifact_becomes_available_during_any_run_state(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            artifact = Path(temp_dir) / "dada2/final/seqtab_nochim.tsv"
            artifact.parent.mkdir(parents=True)
            artifact.write_text("ASV_ID\tS1\nASV_1\t10\n")
            scanner = OutputScanner(temp_dir, run_info={"status": "RUNNING"})

            self.assertEqual(scanner.get_artifact_status("dada2", "seqtab"), "Available")

    def test_nextflow_report_status_distinguishes_pending_completed_and_failed(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            monitor = NextflowMonitor(project_dir=temp_dir)
            command = f"nextflow run main.nf --outdir {temp_dir}/results"
            statuses = []
            for run_status in ("RUNNING", "OK", "ERR"):
                run = {
                    "run_name": "test",
                    "session_id": run_status,
                    "timestamp": "2026-11-19 10:00:00",
                    "status": run_status,
                    "command": command,
                }
                statuses.append(monitor.get_run_artifacts(run)["report"]["status"])

            self.assertEqual(statuses, ["Pending", "Unavailable", "Missing (failed/partial run)"])


if __name__ == "__main__":
    unittest.main()
