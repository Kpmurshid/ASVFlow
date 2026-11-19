#!/usr/bin/env python3
"""Focused dashboard lifecycle integration tests using local C process fixtures."""
import hashlib
import os
import pathlib
import shutil
import socket
import subprocess
import tempfile
import time
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
LAUNCH = ROOT / "bin/launch_dashboard.sh"
STOP = ROOT / "bin/stop_dashboard.sh"

PARENT_SOURCE = r'''#define _GNU_SOURCE
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>
static pid_t child;
static void done(int sig) { if (child > 0) kill(child, SIGTERM); _exit(0); }
int main(int argc, char **argv) {
  char *app = NULL, *port = NULL, *outdir = NULL;
  for (int i=1;i<argc;i++) {
    if (strstr(argv[i], "app.py")) app=argv[i];
    if (!strncmp(argv[i], "--server.port=", 14)) port=argv[i];
    if (!strcmp(argv[i], "--outdir") && i+1<argc) outdir=argv[++i];
  }
  if (!app || !port || !outdir) return 31;
  if (getenv("FIXTURE_FAIL")) return 33;
  signal(SIGTERM, done); signal(SIGINT, done);
  child=fork();
  if (!child) { execl(getenv("FIXTURE_CHILD"), "python3.11", "run", app, port, "--outdir", outdir, (char*)0); _exit(32); }
  while (waitpid(child, NULL, 0)<0) { }
  return 0;
}
'''
CHILD_SOURCE = r'''#define _GNU_SOURCE
#include <arpa/inet.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <unistd.h>
static void done(int sig) { _exit(0); }
int main(int argc, char **argv) {
  signal(SIGTERM, done); signal(SIGINT, done);
  int port=0; for(int i=1;i<argc;i++) if(!strncmp(argv[i],"--server.port=",14)) port=atoi(argv[i]+14);
  int fd=socket(AF_INET,SOCK_STREAM,0); struct sockaddr_in a={0}; a.sin_family=AF_INET; a.sin_addr.s_addr=htonl(INADDR_LOOPBACK); a.sin_port=htons(port);
  if(bind(fd,(void*)&a,sizeof(a)) || listen(fd,8)) return 41;
  for (;;) { int c=accept(fd,0,0); if(c>=0) { const char *r="HTTP/1.0 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok"; write(c,r,strlen(r)); close(c); } }
}
'''


def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


class Lifecycle(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = pathlib.Path(tempfile.mkdtemp(prefix="asvflow-lifecycle-"))
        cls.bin = cls.tmp / "bin"
        cls.bin.mkdir()
        for name, source in (("apptainer", PARENT_SOURCE), ("python3.11", CHILD_SOURCE)):
            src = cls.tmp / f"{name}.c"
            src.write_text(source)
            subprocess.run(["cc", str(src), "-o", str(cls.bin / name)], check=True)
        (cls.tmp / "dashboard.sif").touch()

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp, ignore_errors=True)

    def setUp(self):
        self.case = pathlib.Path(tempfile.mkdtemp(prefix="case-", dir=self.tmp))
        self.state = self.case / "state"
        self.env = os.environ.copy()
        self.env.update({"ASVFLOW_STATE_DIR": str(self.state), "PATH": f"{self.bin}:{self.env['PATH']}", "FIXTURE_CHILD": str(self.bin / "python3.11"), "DASHBOARD_BIND_ADDRESS": "127.0.0.1"})
        self.out = self.case / "results"
        self.port = free_port()

    def tearDown(self):
        # Stop any fixture even when an assertion fails.
        subprocess.run([str(STOP), str(self.out)], env=self.env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        shutil.rmtree(self.case, ignore_errors=True)

    def state_dir(self, outdir=None):
        outdir = pathlib.Path(outdir or self.out).resolve()
        key = hashlib.sha256(f"{ROOT}:{outdir}".encode()).hexdigest()
        return self.state / key

    def launch(self, outdir=None, port=None):
        return subprocess.run([str(LAUNCH), str(outdir or self.out), str(port or self.port), str(self.tmp / "dashboard.sif")], env=self.env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30)

    def stop(self, outdir=None):
        return subprocess.run([str(STOP), str(outdir or self.out)], env=self.env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=15)

    def test_normal_launch_tracks_parent_child_and_stops_repeatedly(self):
        result = self.launch()
        self.assertEqual(result.returncode, 0, result.stdout)
        state = self.state_dir()
        parent = int((state / "dashboard.pid").read_text())
        child = int(subprocess.check_output(["pgrep", "-P", str(parent)], text=True).splitlines()[0])
        self.assertEqual(os.path.basename(os.readlink(f"/proc/{parent}/exe")), "apptainer")
        self.assertEqual(os.path.basename(os.readlink(f"/proc/{child}/exe")), "python3.11")
        self.assertTrue((self.out / ".asvflow_dashboard").is_symlink())
        self.assertEqual((self.out / ".asvflow_dashboard").resolve(), state)
        self.assertEqual(self.stop().returncode, 0)
        self.assertEqual(self.stop().returncode, 0)
        self.assertFalse(pathlib.Path(f"/proc/{parent}").exists())

    def test_deleted_results_still_stops(self):
        self.assertEqual(self.launch().returncode, 0)
        shutil.rmtree(self.out)
        self.assertEqual(self.stop().returncode, 0)

    def test_legacy_state_migrates_and_compatibility_link_is_restored(self):
        self.out.mkdir()
        legacy = self.out / ".asvflow_dashboard"
        legacy.mkdir()
        (legacy / "marker").write_text("legacy")
        result = self.launch()
        self.assertEqual(result.returncode, 0, result.stdout)
        state = self.state_dir()
        self.assertTrue((state / "marker").exists())
        self.assertTrue((self.out / ".asvflow_dashboard").is_symlink())
        self.assertEqual(self.stop().returncode, 0)

    def test_legacy_directory_is_preserved_when_per_user_state_already_exists(self):
        self.out.mkdir()
        legacy = self.out / ".asvflow_dashboard"
        legacy.mkdir()
        (legacy / "artifact.html").write_text("legacy artifact")
        state = self.state_dir()
        state.mkdir(parents=True)
        (state / "current-state").write_text("authoritative state")

        result = self.launch()
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertTrue((self.out / ".asvflow_dashboard").is_symlink())
        self.assertEqual((self.out / ".asvflow_dashboard").resolve(), state)
        self.assertEqual((state / "artifact.html").read_text(), "legacy artifact")
        self.assertEqual((state / "current-state").read_text(), "authoritative state")
        archives = list(self.case.glob("results/.asvflow_dashboard.legacy.*"))
        self.assertEqual(len(archives), 1)
        self.assertEqual((archives[0] / "artifact.html").read_text(), "legacy artifact")

        self.assertEqual(self.stop().returncode, 0)
        self.assertEqual(self.stop().returncode, 0)

    def test_state_isolated_by_output_directory(self):
        second = self.case / "other"
        p2 = free_port()
        self.assertEqual(self.launch().returncode, 0)
        self.assertEqual(self.launch(second, p2).returncode, 0)
        self.assertNotEqual((self.state_dir() / "dashboard.pid").read_text(), (self.state_dir(second) / "dashboard.pid").read_text())
        self.assertEqual(self.stop().returncode, 0)
        self.assertTrue(pathlib.Path(f"/proc/{(self.state_dir(second) / 'dashboard.pid').read_text().strip()}").exists())
        self.assertEqual(self.stop(second).returncode, 0)

    def test_missing_and_stale_state_are_safe(self):
        self.assertEqual(self.stop().returncode, 0)
        state = self.state_dir()
        state.mkdir(parents=True)
        (state / "dashboard.pid").write_text("99999999\n")
        (state / "dashboard.port").write_text(str(self.port))
        result = self.stop()
        self.assertNotEqual(result.returncode, 0)  # incomplete metadata fails closed
        self.assertTrue((state / "dashboard.pid").exists())

    def test_stale_complete_state_is_cleaned_after_process_exit(self):
        self.assertEqual(self.launch().returncode, 0)
        state = self.state_dir()
        parent = int((state / "dashboard.pid").read_text())
        child = int(subprocess.check_output(["pgrep", "-P", str(parent)], text=True).splitlines()[0])
        os.kill(child, 9); os.kill(parent, 9)
        time.sleep(.2)
        result = self.stop()
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertFalse((state / "dashboard.pid").exists())

    def test_inaccessible_proc_fails_closed(self):
        self.assertEqual(self.launch().returncode, 0)
        parent = int((self.state_dir() / "dashboard.pid").read_text())
        shim = self.case / "sitecustomize.py"
        shim.write_text("import os\n_orig=os.open\ndef _deny(path, *a, **k):\n    if path == '/proc/%s': raise PermissionError(13, 'test inaccessible proc')\n    return _orig(path, *a, **k)\nos.open=_deny\n" % parent)
        self.env["PYTHONPATH"] = str(self.case)
        result = self.stop()
        self.assertNotEqual(result.returncode, 0)
        os.kill(parent, 0)
        del self.env["PYTHONPATH"]

    def test_reused_pid_and_unrelated_port_owner_are_never_signaled(self):
        # An unrelated listener blocks launch and remains alive.
        listener = socket.socket()
        listener.bind(("127.0.0.1", self.port)); listener.listen()
        try:
            result = self.launch()
            self.assertNotEqual(result.returncode, 0)
            self.assertTrue(listener.fileno() >= 0)
        finally:
            listener.close()
        # Replace the saved PID with a live unrelated PID; identity must reject it.
        self.port = free_port()
        self.assertEqual(self.launch().returncode, 0)
        state = self.state_dir()
        original = (state / "dashboard.pid").read_text()
        (state / "dashboard.pid").write_text(f"{os.getpid()}\n")
        result = self.stop()
        self.assertNotEqual(result.returncode, 0)
        os.kill(os.getpid(), 0)
        (state / "dashboard.pid").write_text(original)
        self.assertEqual(self.stop().returncode, 0)

    def test_partial_launch_failure_leaves_no_live_fixture(self):
        # Runtime exits between process creation and identity publication.
        self.env["FIXTURE_FAIL"] = "1"
        result = self.launch()
        self.assertNotEqual(result.returncode, 0)
        state = self.state_dir()
        pid_file = state / "dashboard.pid"
        if pid_file.exists():
            pid = int(pid_file.read_text())
            stat_path = pathlib.Path(f"/proc/{pid}/stat")
            if stat_path.exists():
                fields = stat_path.read_text().split()
                self.assertIn(fields[2], ("Z", "X"), f"partial launch left live process {pid}")
        for failed in self.state.parent.glob(state.name + ".failed.*"):
            pid_file = failed / "dashboard.pid"
            if pid_file.exists():
                pid = int(pid_file.read_text())
                stat_path = pathlib.Path(f"/proc/{pid}/stat")
                if stat_path.exists():
                    self.assertIn(stat_path.read_text().split()[2], ("Z", "X"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
