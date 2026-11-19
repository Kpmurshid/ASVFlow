#!/usr/bin/env python3
"""Isolated tests for embedded launch/stop process identity helpers.

These tests never start or signal dashboard processes. They extract the pure
identity functions from each shell helper and exercise synthetic task records.
"""
import ast
import errno
import hashlib
import os
import re
import signal
import stat
import subprocess
import sys
import tempfile
import unittest
from unittest import mock
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def helper_functions(script):
    text = (ROOT / "bin" / script).read_text()
    source = text.split("python3 - \"$@\" <<'PY'\n", 1)[1].split("\nPY\n", 1)[0]
    tree = ast.parse(source)
    names = {
        "read_task", "argv_for", "has_dashboard_command", "leader_matches",
        "is_dashboard_member", "is_dashboard_executable",
    }
    nodes = [node for node in tree.body if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and node.name in names]
    namespace = {
        "os": os, "errno": errno, "hashlib": hashlib, "re": re, "signal": signal, "stat": stat,
        "sys": sys, "time": __import__("time"), "json": __import__("json"),
    }
    exec(compile(ast.Module(body=nodes, type_ignores=[]), script, "exec"), namespace)
    return namespace


def metadata_validator(script, identity, directory):
    text = (ROOT / "bin" / script).read_text()
    source = text.split("python3 - \"$@\" <<'PY'\n", 1)[1].split("\nPY\n", 1)[0]
    tree = ast.parse(source)
    expected = next(
        node for node in tree.body
        if isinstance(node, ast.Assign)
        and any(isinstance(target, ast.Name) and target.id == "expected_keys" for target in node.targets)
    )
    guard = next(
        node for node in tree.body
        if isinstance(node, ast.If)
        and any(isinstance(child, ast.Call) and isinstance(child.func, ast.Name) and child.func.id == "fail"
                for child in ast.walk(node))
        and "Dashboard ownership metadata is invalid or does not match this launch"
        in ast.get_source_segment(source, node)
    )
    function = ast.FunctionDef(
        name="validate_metadata", args=ast.arguments(posonlyargs=[], args=[], kwonlyargs=[], kw_defaults=[], defaults=[]),
        body=[guard, ast.Return(value=ast.Constant(value=True))], decorator_list=[],
    )
    namespace = {
        "os": os, "stat": stat, "identity": identity,
        "pid": 424242, "pgid": 424242, "uid": os.getuid(),
        "project": str(ROOT), "outdir": str(ROOT / "results" / "identity-test"),
        "port": "8501", "identity_path": str(Path(directory) / "dashboard.identity"),
        "fail": lambda message: (_ for _ in ()).throw(ValueError(message)),
    }
    module = ast.fix_missing_locations(ast.Module(body=[expected, function], type_ignores=[]))
    exec(compile(module, script, "exec"), namespace)
    namespace["metadata_dir"] = os.stat(directory, follow_symlinks=False)
    return namespace["validate_metadata"]


class StarterSuidIdentityTests(unittest.TestCase):
    project = str(ROOT)
    outdir = str(ROOT / "results" / "identity-test")
    port = "8501"
    pid = 424242
    pgid = 424242
    cmdline = (
        f"/usr/bin/singularity\0exec\0container.sif\0streamlit\0run\0"
        f"{ROOT}/dashboard/app.py\0--server.port=8501\0--outdir\0{outdir}\0"
    ).encode()

    def task(self, **overrides):
        task = {
            "state": "S", "pgrp": self.pgid, "session": self.pgid,
            "start_ticks": 12345, "uid": os.getuid(),
            "exe": "/usr/bin/singularity", "exe_state": "readable",
            "cmdline": self.cmdline,
        }
        task.update(overrides)
        return task

    def matches(self, ns, task):
        ns.update({
            "pid": self.pid, "pgid": self.pgid, "port": self.port,
            "project": self.project, "outdir": self.outdir,
            "identity": {
                "uid": os.getuid(), "start_ticks": 12345,
                "exe": task["exe"], "exe_state": task["exe_state"],
                "cmdline_sha256": hashlib.sha256(task["cmdline"]).hexdigest(),
            },
        })
        return ns["leader_matches"](task)

    def valid_identity(self):
        return {
            "version": 1, "pid": self.pid, "pgid": self.pgid, "uid": os.getuid(),
            "boot_id": Path("/proc/sys/kernel/random/boot_id").read_text().strip(),
            "start_ticks": 12345, "exe": "/usr/bin/singularity", "exe_state": "readable",
            "cmdline_sha256": hashlib.sha256(self.cmdline).hexdigest(),
            "project": self.project, "outdir": self.outdir, "port": self.port,
        }

    def assert_metadata_valid(self, script, identity):
        with tempfile.TemporaryDirectory(prefix="asvflow_identity_meta_") as directory:
            os.chmod(directory, 0o700)
            return metadata_validator(script, identity, directory)()

    def test_legacy_metadata_without_exe_state_is_rejected(self):
        for script in ("launch_dashboard.sh", "stop_dashboard.sh"):
            identity = self.valid_identity()
            del identity["exe_state"]
            with self.subTest(script=script), self.assertRaises(ValueError):
                self.assert_metadata_valid(script, identity)

    def test_unknown_exe_state_is_rejected(self):
        for script in ("launch_dashboard.sh", "stop_dashboard.sh"):
            identity = self.valid_identity()
            identity["exe_state"] = "unknown"
            with self.subTest(script=script), self.assertRaises(ValueError):
                self.assert_metadata_valid(script, identity)

    def test_inaccessible_metadata_requires_null_exe(self):
        for script in ("launch_dashboard.sh", "stop_dashboard.sh"):
            identity = self.valid_identity()
            identity.update(exe_state="inaccessible", exe="/usr/bin/singularity")
            with self.subTest(script=script), self.assertRaises(ValueError):
                self.assert_metadata_valid(script, identity)

    def test_readable_metadata_requires_absolute_non_null_exe(self):
        for script in ("launch_dashboard.sh", "stop_dashboard.sh"):
            for exe in (None, "singularity"):
                identity = self.valid_identity()
                identity["exe"] = exe
                with self.subTest(script=script, exe=exe), self.assertRaises(ValueError):
                    self.assert_metadata_valid(script, identity)

    def test_valid_metadata_is_accepted_by_both_helpers(self):
        for script in ("launch_dashboard.sh", "stop_dashboard.sh"):
            with self.subTest(script=script):
                self.assertTrue(self.assert_metadata_valid(script, self.valid_identity()))

    def test_starter_suid_inaccessible_executable(self):
        for script in ("launch_dashboard.sh", "stop_dashboard.sh"):
            ns = helper_functions(script)
            task = self.task(exe=None, exe_state="inaccessible")
            self.assertTrue(self.matches(ns, task), script)

    def test_apptainer_runtime_is_accepted_by_both_helpers(self):
        cmdline = (
            f"/usr/bin/apptainer\0exec\0container.sif\0streamlit\0run\0"
            f"{ROOT}/dashboard/app.py\0--server.port=8501\0--outdir\0{self.outdir}\0"
        ).encode()
        task = self.task(
            exe="/usr/bin/apptainer",
            cmdline=cmdline,
        )
        for script in ("launch_dashboard.sh", "stop_dashboard.sh"):
            ns = helper_functions(script)
            self.assertTrue(self.matches(ns, task), script)

    def test_read_task_records_permission_denied_without_losing_process(self):
        ns = helper_functions("launch_dashboard.sh")
        with mock.patch.object(os, "readlink", side_effect=PermissionError(13, "denied")):
            task = ns["read_task"](os.getpid())
        self.assertIsNotNone(task)
        self.assertEqual(task["exe_state"], "inaccessible")
        self.assertIsNone(task["exe"])

    def test_read_task_treats_missing_exe_link_as_gone(self):
        ns = helper_functions("stop_dashboard.sh")
        with mock.patch.object(os, "readlink", side_effect=FileNotFoundError(2, "gone")):
            self.assertIsNone(ns["read_task"](os.getpid()))

    def test_process_disappearance_is_not_inaccessible(self):
        ns = helper_functions("launch_dashboard.sh")
        self.assertIsNone(ns["read_task"](2147483647))

    def test_pid_reuse_rejected_by_start_time(self):
        ns = helper_functions("launch_dashboard.sh")
        self.assertFalse(self.matches(ns, self.task(start_ticks=99999)))

    def test_unrelated_same_pgid_rejected_by_exact_command_line(self):
        ns = helper_functions("stop_dashboard.sh")
        task = self.task(cmdline=b"unrelated\0process\0")
        self.assertFalse(self.matches(ns, task))

    def test_readable_unexpected_executable_rejected(self):
        for script in ("launch_dashboard.sh", "stop_dashboard.sh"):
            ns = helper_functions(script)
            task = self.task(exe="/tmp/unexpected")
            self.assertFalse(self.matches(ns, task), script)

    def test_inaccessible_launcher_with_mismatched_command_line_rejected(self):
        for script in ("launch_dashboard.sh", "stop_dashboard.sh"):
            ns = helper_functions(script)
            task = self.task(exe=None, exe_state="inaccessible", cmdline=b"different\0launcher\0")
            self.assertFalse(self.matches(ns, task), script)

    def test_streamlit_child_requires_readable_expected_executable(self):
        child_cmdline = (
            f"/usr/local/bin/python3.12\0/usr/local/bin/streamlit\0run\0"
            f"{self.project}/dashboard/app.py\0--server.port=8501\0--outdir\0{self.outdir}\0"
        ).encode()
        for script in ("launch_dashboard.sh", "stop_dashboard.sh"):
            ns = helper_functions(script)
            accepted = {
                "state": "S", "pgrp": self.pgid, "session": self.pgid,
            "start_ticks": 22345, "uid": os.getuid(), "ppid": self.pgid,
            "exe": "/usr/local/bin/python3.12",
                "exe_state": "readable", "cmdline": child_cmdline,
            }
            self.assertTrue(ns["is_dashboard_member"](accepted, self.project, self.port, self.outdir, os.getuid(), self.pgid), script)
            for rejected in (
                dict(accepted, exe=None, exe_state="inaccessible"),
                dict(accepted, exe="/tmp/unexpected"),
            ):
                self.assertFalse(ns["is_dashboard_member"](rejected, self.project, self.port, self.outdir, os.getuid(), self.pgid), script)


if __name__ == "__main__":
    unittest.main(verbosity=2)
