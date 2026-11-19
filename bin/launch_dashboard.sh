#!/bin/bash
# ASVFlow Live Dashboard Launcher
# Launches dashboard in background with robust error handling

set -e

# Default values
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTDIR="${1:-results}"
PORT="${2:-8501}"
DASHBOARD_SIF="${3:-${PROJECT_DIR}/tools/asvflow-dashboard.sif}"
DASHBOARD_BIND_ADDRESS="${DASHBOARD_BIND_ADDRESS:-}"
if [ -z "${DASHBOARD_BIND_ADDRESS}" ]; then
    if command -v tailscale >/dev/null 2>&1; then
        TAILSCALE_IP="$(tailscale ip -4 2>/dev/null | head -n 1 || true)"
        if [[ "${TAILSCALE_IP}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
            DASHBOARD_BIND_ADDRESS="${TAILSCALE_IP}"
        fi
    fi
    DASHBOARD_BIND_ADDRESS="${DASHBOARD_BIND_ADDRESS:-127.0.0.1}"
fi
DASHBOARD_SIF_ABS="$(cd "$(dirname "${DASHBOARD_SIF}")" && pwd)/$(basename "${DASHBOARD_SIF}")"
if command -v apptainer >/dev/null 2>&1; then
    CONTAINER_RUNTIME="$(command -v apptainer)"
elif command -v singularity >/dev/null 2>&1; then
    CONTAINER_RUNTIME="$(command -v singularity)"
else
    echo "[Dashboard] ERROR: Neither Apptainer nor Singularity was found in PATH" >&2
    exit 1
fi

# Authoritative lifecycle state must survive deletion of the results directory.
# Keep a compatibility symlink in OUTDIR for Nextflow and existing tooling.
OUTDIR_ABS_CHECK="$(realpath -m -- "${OUTDIR}")"
STATE_ROOT="${ASVFLOW_STATE_DIR:-${XDG_STATE_HOME:-${HOME}/.local/state}/asvflow/dashboard}"
STATE_KEY="$(printf '%s' "${PROJECT_DIR}:${OUTDIR_ABS_CHECK}" | sha256sum | awk '{print $1}')"
DASHBOARD_DIR="${STATE_ROOT}/${STATE_KEY}"
COMPAT_DASHBOARD_DIR="${OUTDIR}/.asvflow_dashboard"
PID_FILE="${DASHBOARD_DIR}/dashboard.pid"
LOG_FILE="${DASHBOARD_DIR}/dashboard.log"
PORT_FILE="${DASHBOARD_DIR}/dashboard.port"
PGID_FILE="${DASHBOARD_DIR}/dashboard.pgid"
PROJECT_FILE="${DASHBOARD_DIR}/dashboard.project"
OUTDIR_FILE="${DASHBOARD_DIR}/dashboard.outdir"
BIND_ADDRESS_FILE="${DASHBOARD_DIR}/dashboard.bind_address"
IDENTITY_FILE="${DASHBOARD_DIR}/dashboard.identity"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[Dashboard]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[Dashboard]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[Dashboard]${NC} $1"
}

log_error() {
    echo -e "${RED}[Dashboard]${NC} $1"
}

format_url_host() {
    local address="$1"
    if [[ "${address}" == *:* && "${address}" != \[*\] ]]; then
        printf '[%s]' "${address}"
    else
        printf '%s' "${address}"
    fi
}

# Find an available port
check_port() {
    if lsof -i ":$1" >/dev/null 2>&1 || ss -tuln 2>/dev/null | grep -q ":$1 "; then
        return 1
    fi
    return 0
}

check_port_free_verified() {
    local socket_table
    command -v ss >/dev/null 2>&1 || return 2
    socket_table=$(ss -H -tuln 2>/dev/null) || return 2
    if awk -v port=":$1" '$5 ~ (port "$" ) { found = 1 } END { exit !found }' <<< "${socket_table}"; then
        return 1
    fi
    return 0
}

cleanup_verified_dashboard_state() {
    local port="$1"
    if ! check_port "${port}"; then
        log_error "Port ${port} remains in use; preserving dashboard state"
        return 1
    fi
    rm -f "${PID_FILE}" "${PORT_FILE}" "${PGID_FILE}" "${PROJECT_FILE}" "${OUTDIR_FILE}" "${BIND_ADDRESS_FILE}" "${IDENTITY_FILE}"
}

dashboard_process_helper() {
    python3 - "$@" <<'PY'
import hashlib
import json
import errno
import os
import re
import signal
import stat
import sys
import tempfile
import time


def fail(message):
    print(message, file=sys.stderr)
    raise SystemExit(1)


def read_task(pid, proc_fd=None):
    proc = f"/proc/{pid}"
    owned_fd = proc_fd is None
    try:
        if owned_fd:
            proc_fd = os.open(proc, os.O_RDONLY | os.O_DIRECTORY)

        def read_bytes(name):
            fd = os.open(name, os.O_RDONLY, dir_fd=proc_fd)
            with os.fdopen(fd, "rb") as stream:
                return stream.read()

        def read_text(name):
            fd = os.open(name, os.O_RDONLY, dir_fd=proc_fd)
            with os.fdopen(fd, "r", encoding="ascii") as stream:
                return stream.read()

        raw_stat = read_bytes("stat").decode()
        fields = raw_stat[raw_stat.rfind(")") + 2:].split()
        status = read_text("status")
        uid_line = next(line for line in status.splitlines() if line.startswith("Uid:"))
        uid = int(uid_line.split()[1])
        cmdline = read_bytes("cmdline")
        environ = read_bytes("environ")
        container_env = {}
        for entry in environ.split(b"\0"):
            key, separator, value = entry.partition(b"=")
            if separator and key in (
                b"APPTAINER_CONTAINER", b"SINGULARITY_CONTAINER",
                b"APPTAINER_COMMAND", b"SINGULARITY_COMMAND",
            ):
                container_env[key.decode("ascii")] = os.fsdecode(value)
        try:
            exe = os.readlink("exe", dir_fd=proc_fd)
            exe_state = "readable"
        except FileNotFoundError:
            # The proc entry disappeared; it is not an inaccessible executable.
            return None
        except OSError as error:
            if error.errno not in (errno.EACCES, errno.EPERM):
                raise
            exe = None
            exe_state = "inaccessible"
        return {
            "state": fields[0],
            "ppid": int(fields[1]),
            "pgrp": int(fields[2]),
            "session": int(fields[3]),
            "start_ticks": int(fields[19]),
            "uid": uid,
            "exe": exe,
            "exe_state": exe_state,
            "cmdline": cmdline,
            "container_env": container_env,
        }
    except (FileNotFoundError, ProcessLookupError):
        return None
    except (OSError, ValueError, StopIteration, IndexError) as error:
        fail(f"Cannot verify process {pid}: {error}")
    finally:
        if owned_fd and proc_fd is not None:
            os.close(proc_fd)


def argv_for(task):
    if not task or not task["cmdline"]:
        return []
    return [os.fsdecode(arg) for arg in task["cmdline"].split(b"\0") if arg]


def has_dashboard_command(task, project, port, outdir):
    argv = argv_for(task)
    app = os.path.join(project, "dashboard", "app.py")
    try:
        outdir_index = argv.index("--outdir")
    except ValueError:
        return False
    return (
        app in argv
        and f"--server.port={port}" in argv
        and outdir_index + 1 < len(argv)
        and argv[outdir_index + 1] == outdir
    )


def is_dashboard_executable(task):
    if task["exe_state"] != "readable":
        return False
    executable = os.path.basename(task["exe"])
    return executable == "streamlit" or re.fullmatch(
        r"python(?:\d+(?:\.\d+)*)?", executable
    ) is not None


def is_dashboard_member(task, project, port, outdir, expected_uid, pgid):
    argv = argv_for(task)
    app = os.path.join(project, "dashboard", "app.py")
    try:
        app_index = argv.index(app)
        outdir_index = argv.index("--outdir")
    except ValueError:
        return False
    return (
        task["uid"] == expected_uid
        and task["ppid"] == pgid
        and task["pgrp"] == pgid
        and task["session"] == pgid
        and is_dashboard_executable(task)
        and app_index > 0
        and "run" in argv[:app_index]
        and f"--server.port={port}" in argv
        and outdir_index + 1 < len(argv)
        and argv[outdir_index + 1] == outdir
    )


action, pid_text, pgid_text, port, project, outdir, *rest = sys.argv[1:]
if not pid_text.isdecimal() or not pgid_text.isdecimal():
    fail("PID and PGID must be decimal integers")
pid, pgid = int(pid_text), int(pgid_text)

def write_identity(identity_path, task):
    identity = {
        "version": 1,
        "pid": pid,
        "pgid": pgid,
        "uid": task["uid"],
        "boot_id": open("/proc/sys/kernel/random/boot_id", encoding="ascii").read().strip(),
        "start_ticks": task["start_ticks"],
        "exe": task["exe"],
        "exe_state": task["exe_state"],
        "cmdline_sha256": hashlib.sha256(task["cmdline"]).hexdigest(),
        "project": project,
        "outdir": outdir,
        "port": port,
    }
    directory = os.path.dirname(identity_path)
    directory_stat = os.stat(directory, follow_symlinks=False)
    if (
        not stat.S_ISDIR(directory_stat.st_mode)
        or directory_stat.st_uid != os.getuid()
        or directory_stat.st_mode & 0o022
    ):
        fail("Dashboard state directory has unsafe type, owner, or permissions")
    if os.path.lexists(identity_path):
        fail("Identity path already exists; refusing to overwrite ownership metadata")
    fd, temporary = tempfile.mkstemp(prefix=".dashboard.identity.", dir=directory)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            json.dump(identity, stream)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        # link() publishes atomically and fails if another launcher already
        # created the destination; unlike replace(), it cannot clobber it.
        os.link(temporary, identity_path, follow_symlinks=False)
        os.unlink(temporary)
        dir_fd = os.open(directory, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(dir_fd)
        finally:
            os.close(dir_fd)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


if action == "create":
    if len(rest) != 4:
        fail("create action requires identity, container, project metadata, and output metadata paths")
    identity_path, expected_container, project_file, outdir_file = rest
    deadline = time.monotonic() + 3
    task = None
    while time.monotonic() < deadline:
        task = read_task(pid)
        if (
            task
            and task["pgrp"] == pgid == pid
            and task["session"] == pgid
            and task["uid"] == os.getuid()
            and task["exe_state"] in ("readable", "inaccessible")
            and (
                task["exe_state"] == "inaccessible"
                or os.path.basename(task["exe"]) in ("singularity", "apptainer", "starter")
            )
            and "exec" in argv_for(task)
            and has_dashboard_command(task, project, port, outdir)
        ):
            break
        time.sleep(0.05)
    else:
        if (
            task
            and task["exe_state"] == "readable"
            and os.path.basename(task["exe"]) == "starter"
        ):
            # Apptainer exposes its starter process as the session leader and
            # places the dashboard command in the verified container child.
            action = "adopt-legacy"
            rest = [identity_path, expected_container, project_file, outdir_file]
        else:
            fail("Cannot establish launcher identity and session ownership")

    if action == "create":
        write_identity(identity_path, task)
        raise SystemExit(0)

if action == "adopt-legacy":
    if len(rest) != 4:
        fail("Legacy adoption requires identity, container, project metadata, and output metadata paths")
    identity_path, expected_container, project_file, outdir_file = rest
    if os.path.exists(identity_path) or os.path.islink(identity_path):
        fail("Identity path already exists; refusing to replace existing ownership metadata")
    if pid <= 0 or pgid != pid:
        fail("Legacy state does not identify a session-leader PID/PGID pair")
    if not port.isdecimal() or not 1 <= int(port) <= 65535:
        fail(f"Legacy dashboard port is invalid: {port!r}")
    metadata_fds = []
    metadata_records = []
    for metadata_path, expected_value, label in (
        (project_file, project, "project"),
        (outdir_file, outdir, "output directory"),
    ):
        try:
            metadata_fd = os.open(metadata_path, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0))
            metadata_stat = os.fstat(metadata_fd)
            with os.fdopen(os.dup(metadata_fd), "r", encoding="utf-8") as metadata_stream:
                metadata_value = metadata_stream.read().strip()
        except OSError as error:
            fail(f"Cannot securely read legacy {label} ownership metadata: {error}")
        if (
            not stat.S_ISREG(metadata_stat.st_mode)
            or metadata_stat.st_nlink != 1
            or metadata_stat.st_uid != os.getuid()
            or metadata_value != expected_value
        ):
            fail(f"Legacy {label} ownership metadata must be a single-link regular file owned by this user and match the requested path")
        metadata_fds.append(metadata_fd)
        metadata_records.append((metadata_path, metadata_stat.st_dev, metadata_stat.st_ino))

    leader = read_task(pid)
    if not leader or leader["state"] in ("Z", "X"):
        fail(f"Legacy launcher PID {pid} is absent or not live")
    if leader["uid"] != os.getuid():
        fail(f"Legacy launcher owner UID {leader['uid']} does not match current UID {os.getuid()}")
    if leader["pgrp"] != pgid or leader["session"] != pgid:
        fail("Legacy launcher is not the recorded process-group and session leader")
    if leader["exe_state"] != "readable" or os.path.basename(leader["exe"]) not in ("starter", "apptainer", "singularity"):
        fail(f"Legacy launcher executable is not a readable Apptainer/Singularity runtime: {leader['exe']}")

    members = []
    dashboard_pids = []
    dashboard_snapshot = None
    try:
        entries = list(os.scandir("/proc"))
    except OSError as error:
        fail(f"Cannot enumerate processes for legacy adoption: {error}")
    for entry in entries:
        if not entry.name.isdecimal():
            continue
        member_pid = int(entry.name)
        try:
            with open(f"/proc/{member_pid}/stat", "rb") as stream:
                raw_stat = stream.read().decode()
            stat_fields = raw_stat[raw_stat.rfind(")") + 2:].split()
            if len(stat_fields) < 4 or int(stat_fields[2]) != pgid:
                continue
        except (FileNotFoundError, ProcessLookupError):
            continue
        except (OSError, ValueError, IndexError) as error:
            fail(f"Cannot establish process-group membership for {member_pid}: {error}")
        try:
            task = read_task(member_pid)
        except SystemExit:
            raise
        if task is None or task["pgrp"] != pgid or task["state"] in ("Z", "X"):
            continue
        if task["session"] != pgid:
            fail(f"Process {member_pid} in the legacy group has an unexpected session")
        if member_pid == pid:
            if task != leader:
                fail("Legacy launcher changed while it was being inspected")
            members.append(task)
            continue

        argv = argv_for(task)
        app = os.path.join(project, "dashboard", "app.py")
        outdir_index = argv.index("--outdir") if "--outdir" in argv else -1
        executable = os.path.basename(task["exe"] or "")
        container_paths = {
            task["container_env"].get("APPTAINER_CONTAINER"),
            task["container_env"].get("SINGULARITY_CONTAINER"),
        }
        container_paths.discard(None)
        valid_member = (
            task["uid"] == leader["uid"]
            and task["ppid"] == pid
            and task["pgrp"] == pgid
            and task["session"] == pgid
            and task["exe_state"] == "readable"
            and re.fullmatch(r"python(?:\d+(?:\.\d+)*)?", executable) is not None
            and app in argv
            and "run" in argv[:argv.index(app)]
            and f"--server.port={port}" in argv
            and outdir_index >= 0
            and outdir_index + 1 < len(argv)
            and argv[outdir_index + 1] == outdir
            and container_paths == {expected_container}
            and task["container_env"].get("APPTAINER_COMMAND", task["container_env"].get("SINGULARITY_COMMAND")) == "exec"
        )
        if not valid_member:
            fail(f"Process {member_pid} shares the legacy session but is not the expected dashboard container child")
        members.append(task)
        dashboard_pids.append(member_pid)
        dashboard_snapshot = task

    if not any(task["ppid"] == pid and os.path.join(project, "dashboard", "app.py") in argv_for(task) for task in members):
        fail("No direct Streamlit child was verified for the recorded launcher")
    if len(members) < 2:
        fail("Legacy process group did not contain both the runtime leader and dashboard child")

    # Confirm that the verified Streamlit child itself owns the requested listening socket.
    port_hex = f"{int(port):04X}"
    listening_inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, encoding="ascii") as stream:
                next(stream, None)
                for line in stream:
                    fields = line.split()
                    if len(fields) > 9 and fields[1].rsplit(":", 1)[-1].upper() == port_hex and fields[3] == "0A":
                        listening_inodes.add(fields[9])
        except OSError as error:
            fail(f"Cannot verify the listening socket in {table}: {error}")
    if len(dashboard_pids) != 1:
        fail(f"Expected exactly one verified dashboard child; found {len(dashboard_pids)}")
    dashboard_pid = dashboard_pids[0]
    try:
        owned_inodes = set()
        for fd_name in os.listdir(f"/proc/{dashboard_pid}/fd"):
            target = os.readlink(f"/proc/{dashboard_pid}/fd/{fd_name}")
            if target.startswith("socket:[") and target.endswith("]"):
                owned_inodes.add(target[8:-1])
    except OSError as error:
        fail(f"Cannot verify sockets owned by dashboard child {dashboard_pid}: {error}")
    if not listening_inodes.intersection(owned_inodes):
        fail(f"Verified dashboard child {dashboard_pid} does not own a LISTEN socket on port {port}")

    current = read_task(pid)
    if current != leader:
        fail("Legacy launcher changed during verification")
    if read_task(dashboard_pid) != dashboard_snapshot:
        fail("Verified dashboard child changed during verification")
    state_dir = os.path.dirname(identity_path)
    state_stat = os.stat(state_dir, follow_symlinks=False)
    if not stat.S_ISDIR(state_stat.st_mode) or state_stat.st_uid != os.getuid():
        fail("Legacy dashboard state directory is not a user-owned directory")
    for metadata_path, device, inode in metadata_records:
        path_stat = os.stat(metadata_path, follow_symlinks=False)
        if path_stat.st_dev != device or path_stat.st_ino != inode:
            fail("Legacy ownership metadata changed during verification")
    os.chmod(state_dir, 0o700, follow_symlinks=False)
    for metadata_fd in metadata_fds:
        os.fchmod(metadata_fd, 0o600)
        os.close(metadata_fd)
    write_identity(identity_path, leader)
    print("Verified legacy dashboard ownership and atomically wrote identity metadata")
    raise SystemExit(0)

if action == "legacy-inspect":
    if pid <= 0 or pgid <= 0:
        fail("PID and PGID must be positive integers")

    def process_group(task_pid):
        try:
            with open(f"/proc/{task_pid}/stat", "rb") as stream:
                raw_stat = stream.read().decode()
            fields = raw_stat[raw_stat.rfind(")") + 2:].split()
            if len(fields) < 3:
                fail(f"Cannot parse process metadata for {task_pid}")
            return int(fields[2])
        except (FileNotFoundError, ProcessLookupError):
            return None
        except OSError:
            try:
                return os.getpgid(task_pid)
            except (FileNotFoundError, ProcessLookupError):
                return None
            except OSError as error:
                fail(f"Cannot determine process-group membership for {task_pid}: {error}")
        except (ValueError, IndexError) as error:
            fail(f"Cannot inspect process {task_pid}: {error}")

    try:
        processes = list(os.scandir("/proc"))
    except OSError as error:
        fail(f"Cannot inspect /proc: {error}")
    for entry in processes:
        if not entry.name.isdecimal():
            continue
        task_pid = int(entry.name)
        task_pgid = process_group(task_pid)
        if task_pgid is not None and (task_pid == pid or task_pgid == pgid):
            raise SystemExit(0)
    raise SystemExit(2)

if action == "inspect":
    if len(rest) < 1:
        fail("inspect action requires identity_path")
    identity_path = rest[0]
    extra = rest[1:]
elif action == "signal":
    if len(rest) < 2 or rest[1] not in ("TERM", "KILL"):
        fail("signal action requires identity_path and signal name (TERM or KILL)")
    identity_path = rest[0]
    extra = [rest[1]]
else:
    fail("Invalid dashboard process-helper action")

try:
    fd = os.open(identity_path, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0))
    metadata_stat = os.fstat(fd)
    if (
        not stat.S_ISREG(metadata_stat.st_mode)
        or metadata_stat.st_uid != os.getuid()
        or metadata_stat.st_mode & 0o022
    ):
        fail("Dashboard ownership metadata has unsafe type, owner, or permissions")
    with os.fdopen(fd, "r", encoding="utf-8") as stream:
        identity = json.load(stream)
except (OSError, ValueError, json.JSONDecodeError) as error:
    fail(f"Cannot read dashboard ownership metadata: {error}")

expected_keys = {
    "version", "pid", "pgid", "uid", "boot_id", "start_ticks", "exe",
    "cmdline_sha256", "exe_state", "project", "outdir", "port",
}
metadata_dir = os.stat(os.path.dirname(identity_path), follow_symlinks=False)
if (
    not isinstance(identity, dict)
    or set(identity) != expected_keys
    or type(identity["version"]) is not int
    or type(identity["pid"]) is not int
    or type(identity["pgid"]) is not int
    or type(identity["uid"]) is not int
    or type(identity["start_ticks"]) is not int
    or identity["version"] != 1
    or identity["pid"] != pid
    or identity["pgid"] != pgid
    or identity["uid"] != os.getuid()
    or identity["project"] != project
    or identity["outdir"] != outdir
    or identity["port"] != port
    or identity["boot_id"] != open("/proc/sys/kernel/random/boot_id", encoding="ascii").read().strip()
    or identity["start_ticks"] <= 0
    or identity["exe_state"] not in ("readable", "inaccessible")
    or (identity["exe_state"] == "readable" and (
        not isinstance(identity["exe"], str) or not os.path.isabs(identity["exe"])
    ))
    or (identity["exe_state"] == "inaccessible" and identity["exe"] is not None)
    or not isinstance(identity["cmdline_sha256"], str)
    or len(identity["cmdline_sha256"]) != 64
    or any(character not in "0123456789abcdef" for character in identity["cmdline_sha256"])
    or not stat.S_ISDIR(metadata_dir.st_mode)
    or metadata_dir.st_uid != os.getuid()
    or metadata_dir.st_mode & 0o022
):
    fail("Dashboard ownership metadata is invalid or does not match this launch")


def leader_matches(task):
    argv = argv_for(task)
    executable = os.path.basename(task["exe"] or "")
    runtime_parent = (
        executable == "starter"
        and len(argv) == 1
        and argv[0] == "Apptainer runtime parent: asvflow-dashboard.sif"
    )
    return bool(
        task
        and task["state"] not in ("Z", "X")
        and task["pgrp"] == pgid
        and task["session"] == pgid
        and task["uid"] == identity["uid"]
        and task["start_ticks"] == identity["start_ticks"]
        and task["exe_state"] == identity["exe_state"]
        and task["exe"] == identity["exe"]
        and hashlib.sha256(task["cmdline"]).hexdigest() == identity["cmdline_sha256"]
        and (
            identity["exe_state"] == "inaccessible"
            or executable in ("singularity", "apptainer", "starter")
        )
        and (
            ("exec" in argv and has_dashboard_command(task, project, port, outdir))
            or runtime_parent
        )
    )


def read_group():
    members = []
    for entry in os.scandir("/proc"):
        if not entry.name.isdecimal():
            continue
        task_pid = int(entry.name)
        try:
            raw_stat = open(f"/proc/{task_pid}/stat", "rb").read().decode()
            stat_fields = raw_stat[raw_stat.rfind(")") + 2:].split()
        except (FileNotFoundError, ProcessLookupError):
            continue
        except OSError as error:
            fail(f"Cannot inspect process-group membership for {task_pid}: {error}")
        if int(stat_fields[2]) != pgid:
            continue
        try:
            proc_fd = os.open(
                f"/proc/{task_pid}", os.O_RDONLY | os.O_DIRECTORY
            )
        except (FileNotFoundError, ProcessLookupError):
            continue
        task = read_task(task_pid, proc_fd)
        if not task:
            os.close(proc_fd)
            fail(f"Cannot verify process {task_pid} in the target process group (inaccessible or parsing error)")
        if task["pgrp"] != pgid or task["state"] in ("Z", "X"):
            os.close(proc_fd)
            continue
        if task["session"] != pgid:
            os.close(proc_fd)
            fail(f"Process {task_pid} in the dashboard group has an unexpected session")
        if task_pid == pid:
            if not leader_matches(task):
                os.close(proc_fd)
                fail("Launcher identity changed; refusing to signal the process group")
        elif not is_dashboard_member(task, project, port, outdir, identity["uid"], pgid):
            os.close(proc_fd)
            fail(f"Unverified process {task_pid} shares the dashboard process group")
        members.append((task_pid, task, proc_fd))

    leader = next((task for task_pid, task, _ in members if task_pid == pid), None)
    if leader is None:
        if members:
            for _, _, proc_fd in members:
                os.close(proc_fd)
            fail("Launcher identity is gone while processes remain in its group")
        return None
    if not members:
        return None
    if not any(member_pid == pid for member_pid, _, _ in members):
        for _, _, proc_fd in members:
            os.close(proc_fd)
        fail("The original launcher is not the process-group leader")
    return sorted(members, key=lambda member: member[0] == pid)


def close_group(group):
    if group:
        for _, _, proc_fd in group:
            os.close(proc_fd)


if action == "inspect":
    group = read_group()
    close_group(group)
    raise SystemExit(0 if group else 2)

if action != "signal" or len(extra) != 1 or extra[0] not in ("TERM", "KILL"):
    fail("Invalid dashboard process-helper action")
if not hasattr(os, "pidfd_open") or not hasattr(signal, "pidfd_send_signal"):
    fail("This Python/Linux runtime lacks pidfd signaling; refusing numeric-PID signaling")

group = read_group()
if not group:
    fail("Original dashboard launcher is no longer running")
signal_number = signal.SIGTERM if extra[0] == "TERM" else signal.SIGKILL

try:
    for target_pid, original_task, proc_fd in group:
        before = read_task(target_pid, proc_fd)
        if before is None or before != original_task:
            fail(f"Process {target_pid} changed before pidfd_open")
        try:
            pidfd = os.pidfd_open(target_pid)
        except ProcessLookupError:
            continue
        try:
            fdinfo = open(f"/proc/self/fdinfo/{pidfd}", encoding="ascii").read()
            if f"Pid:\t{target_pid}\n" not in fdinfo:
                fail(f"pidfd does not refer to expected PID {target_pid}")
            current = read_task(target_pid, proc_fd)
            if current is None or current != original_task:
                fail(f"pidfd target {target_pid} does not match the verified process instance")
            current_group = read_group()
            if not current_group:
                fail("Original dashboard ownership or process-group membership was lost")
            try:
                current_member = next(
                    (member for member in current_group if member[0] == target_pid),
                    None,
                )
                if current_member is None or current_member[1] != original_task:
                    fail(f"Process {target_pid} is no longer a verified dashboard group member")
            finally:
                close_group(current_group)
            current = read_task(target_pid, proc_fd)
            if current is None or current != original_task:
                fail(f"Process {target_pid} changed immediately before signaling")
            signal.pidfd_send_signal(pidfd, signal_number)
        finally:
            os.close(pidfd)
finally:
    close_group(group)
PY
}

# Migrate pre-existing in-results state on first use, preserving its identity
# record so an already-running container remains stoppable.
if [ ! -e "${DASHBOARD_DIR}" ] && [ -d "${COMPAT_DASHBOARD_DIR}" ] && [ ! -L "${COMPAT_DASHBOARD_DIR}" ]; then
    mkdir -p "${STATE_ROOT}"
    chmod 700 "${STATE_ROOT}"
    mv "${COMPAT_DASHBOARD_DIR}" "${DASHBOARD_DIR}"
fi
# Create dashboard directory
mkdir -p "${STATE_ROOT}" "${DASHBOARD_DIR}"
chmod 700 "${STATE_ROOT}" "${DASHBOARD_DIR}"
if [ -L "${DASHBOARD_DIR}" ] || [ ! -d "${DASHBOARD_DIR}" ]; then
    log_error "Dashboard state path is not a real directory; refusing unsafe metadata writes"
    exit 1
fi
if [ "$(stat -c %u "${DASHBOARD_DIR}")" != "$(id -u)" ]; then
    log_error "Dashboard state directory is not owned by the current user"
    exit 1
fi

# Check if dashboard SIF exists
if [ ! -f "${DASHBOARD_SIF}" ]; then
    log_error "Dashboard container not found: ${DASHBOARD_SIF}"
    log_error "Please build the container first:"
    log_error "  cd ${PROJECT_DIR}"
    log_error "  ${CONTAINER_RUNTIME} build ${DASHBOARD_SIF} containers/dashboard.def"
    exit 1
fi

# Function to verify a running dashboard by checking process, cmdline, port, and metadata
is_dashboard_running() {
    local pid="$1"
    local expected_port="$2"
    local expected_project="$3"
    local expected_outdir="$4"

    # Check if PID exists
    if ! kill -0 "$pid" 2>/dev/null; then
        return 1
    fi

    # Verify port is listening
    if ! (lsof -i ":${expected_port}" -sTCP:LISTEN 2>/dev/null | grep -q ":${expected_port}"); then
        if ! (ss -tuln 2>/dev/null | grep -q ":${expected_port}.*LISTEN"); then
            return 1
        fi
    fi

    # Determine verification strategy based on available metadata files
    local has_metadata=false
    if [ -f "${PROJECT_FILE}" ] && [ -f "${OUTDIR_FILE}" ]; then
        local stored_project=$(cat "${PROJECT_FILE}")
        local stored_outdir=$(cat "${OUTDIR_FILE}")

        # For dashboards with metadata, verify it matches
        if [ "${stored_project}" = "${expected_project}" ] && [ "${stored_outdir}" = "${expected_outdir}" ]; then
            has_metadata=true
        else
            # Metadata exists but doesn't match - not our dashboard
            return 1
        fi
    fi

    # Find streamlit process - strategy depends on PGID and metadata availability
    local actual_pgid=$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d ' ')
    local streamlit_pids=""

    # If this is a process-group-managed dashboard (PGID == PID), search within group
    if [ -n "$actual_pgid" ] && [ "$actual_pgid" = "$pid" ]; then
        streamlit_pids=$(pgrep -g "$pid" -x "streamlit" 2>/dev/null || true)
    else
        # Legacy dashboard or parent exited: verify port ownership instead of ancestry
        # Try lsof first, then ss if lsof returns no usable PID
        local port_owners=""
        if command -v lsof >/dev/null 2>&1; then
            port_owners=$(lsof -ti ":${expected_port}" -sTCP:LISTEN 2>/dev/null || true)
        fi

        # If lsof returned nothing, try ss
        if [ -z "$port_owners" ] && command -v ss >/dev/null 2>&1; then
            # Use exact local port match: :PORT with word boundary
            port_owners=$(ss -tlnp 2>/dev/null | awk -v port=":${expected_port}" '$4 ~ port" " || $4 ~ port"$" {print}' | grep -oP 'pid=\K[0-9]+' || true)
        fi

        if [ -n "$port_owners" ]; then
            # Inspect all PIDs, require unambiguous match
            local matching_streamlit=""
            local match_count=0
            for port_pid in $port_owners; do
                if [ -f "/proc/$port_pid/comm" ]; then
                    local comm=$(cat "/proc/$port_pid/comm" 2>/dev/null || echo "")
                    if [ "$comm" = "streamlit" ]; then
                        matching_streamlit="$port_pid"
                        match_count=$((match_count + 1))
                    fi
                fi
            done
            # Only use if exactly one Streamlit process owns the port
            if [ $match_count -eq 1 ]; then
                streamlit_pids="$matching_streamlit"
            fi
        fi
    fi

    # Verify streamlit process identity via cmdline
    if [ -n "$streamlit_pids" ]; then
        for spid in $streamlit_pids; do
            if [ -f "/proc/$spid/cmdline" ]; then
                local cmdline=$(tr '\0' ' ' < /proc/$spid/cmdline 2>/dev/null || true)
                # Verify full identity: app.py, port, project path and outdir in command line
                if echo "$cmdline" | grep -q "dashboard/app.py" && \
                   echo "$cmdline" | grep -q "server.port.*${expected_port}" && \
                   echo "$cmdline" | grep -q "${expected_project}" && \
                   echo "$cmdline" | grep -q "outdir.*${expected_outdir}"; then
                    return 0
                fi
            fi
        done
    fi

    return 1
}

# Function to safely stop verified dashboard
stop_verified_dashboard() {
    local pid="$1"
    local pgid="$2"
    local port="$3"
    local helper_status

    log_info "Stopping existing dashboard (PID: ${pid}, PGID: ${pgid}, Port: ${port})"
    if ! dashboard_process_helper signal "${pid}" "${pgid}" "${port}" "${PROJECT_DIR}" "${OUTDIR_ABS_CHECK}" "${IDENTITY_FILE}" TERM; then
        log_error "Ownership verification failed; refusing to signal the dashboard process group"
        return 1
    fi

    for i in $(seq 1 20); do
        if dashboard_process_helper inspect "${pid}" "${pgid}" "${port}" "${PROJECT_DIR}" "${OUTDIR_ABS_CHECK}" "${IDENTITY_FILE}"; then
            sleep 0.5
        else
            helper_status=$?
            if [ "${helper_status}" -eq 2 ]; then
                log_info "Dashboard stopped successfully"
                cleanup_verified_dashboard_state "${port}" && return 0
                return 1
            fi
            log_error "Dashboard ownership could not be verified after TERM; preserving state files"
            return 1
        fi
    done

    if dashboard_process_helper inspect "${pid}" "${pgid}" "${port}" "${PROJECT_DIR}" "${OUTDIR_ABS_CHECK}" "${IDENTITY_FILE}"; then
        log_warning "Graceful shutdown timed out, verifying ownership again before KILL..."
        if ! dashboard_process_helper signal "${pid}" "${pgid}" "${port}" "${PROJECT_DIR}" "${OUTDIR_ABS_CHECK}" "${IDENTITY_FILE}" KILL; then
            log_error "Ownership verification failed; refusing to send KILL"
            return 1
        fi
    else
        helper_status=$?
        if [ "${helper_status}" -eq 2 ]; then
            log_info "Dashboard stopped successfully"
            cleanup_verified_dashboard_state "${port}" && return 0
            return 1
        fi
        log_error "Dashboard ownership could not be verified; preserving state files"
        return 1
    fi

    for i in $(seq 1 20); do
        if dashboard_process_helper inspect "${pid}" "${pgid}" "${port}" "${PROJECT_DIR}" "${OUTDIR_ABS_CHECK}" "${IDENTITY_FILE}"; then
            sleep 0.5
        else
            helper_status=$?
            if [ "${helper_status}" -eq 2 ]; then
                log_info "Dashboard stopped successfully"
                cleanup_verified_dashboard_state "${port}" && return 0
                return 1
            fi
            break
        fi
    done

    log_error "Dashboard termination could not be confirmed; preserving state files"
    return 1
}

# Check if dashboard already running
if [ -f "${PID_FILE}" ] && [ -f "${PORT_FILE}" ]; then
    OLD_PID=$(cat "${PID_FILE}")
    OLD_PORT=$(cat "${PORT_FILE}")
    OLD_PGID=$(cat "${PGID_FILE}" 2>/dev/null || echo "${OLD_PID}")
    OLD_BIND_ADDRESS=$(cat "${BIND_ADDRESS_FILE}" 2>/dev/null || echo "")

    # Convert to absolute paths for comparison
    OUTDIR_ABS_CHECK="$(cd "${OUTDIR}" 2>/dev/null && pwd || echo "${OUTDIR}")"

    # Missing identity metadata can only use read-only legacy recovery.
    if [ ! -e "${IDENTITY_FILE}" ] && [ ! -L "${IDENTITY_FILE}" ]; then
        if dashboard_process_helper legacy-inspect "${OLD_PID}" "${OLD_PGID}" "${OLD_PORT}" "${PROJECT_DIR}" "${OUTDIR_ABS_CHECK}" "${IDENTITY_FILE}"; then
            log_warning "Legacy process group is active; verifying its complete runtime and dashboard identity before adoption"
            STORED_PROJECT=$(cat "${PROJECT_FILE}" 2>/dev/null || true)
            STORED_OUTDIR=$(cat "${OUTDIR_FILE}" 2>/dev/null || true)
            if [ "${STORED_PROJECT}" != "${PROJECT_DIR}" ] || [ "${STORED_OUTDIR}" != "${OUTDIR_ABS_CHECK}" ]; then
                log_error "Stored project/output-directory ownership files do not match this launch"
                log_error "Legacy dashboard was not adopted and no process was signaled"
                exit 1
            fi
            if ! dashboard_process_helper adopt-legacy "${OLD_PID}" "${OLD_PGID}" "${OLD_PORT}" "${PROJECT_DIR}" "${OUTDIR_ABS_CHECK}" "${IDENTITY_FILE}" "${DASHBOARD_SIF_ABS}" "${PROJECT_FILE}" "${OUTDIR_FILE}"; then
                log_error "Legacy dashboard recovery was refused; no process was signaled"
                exit 1
            fi

            OLD_BIND_ADDRESS=$(cat "${BIND_ADDRESS_FILE}" 2>/dev/null || echo "")
            if [ "${PORT}" = "${OLD_PORT}" ] && [ "${DASHBOARD_BIND_ADDRESS}" = "${OLD_BIND_ADDRESS}" ]; then
                log_info "Verified legacy dashboard adopted and already matches the requested configuration"
                log_info "  PID: ${OLD_PID}, Port: ${OLD_PORT}"
                exit 0
            fi

            log_info "Verified legacy dashboard adopted; using validated ownership metadata for the requested restart"
            if ! stop_verified_dashboard "${OLD_PID}" "${OLD_PGID}" "${OLD_PORT}"; then
                log_error "Failed to stop the verified legacy dashboard"
                exit 1
            fi
        else
            HELPER_STATUS=$?
            if [ "${HELPER_STATUS}" -eq 2 ]; then
                if check_port_free_verified "${OLD_PORT}"; then
                    log_warning "Legacy process group is absent and port ${OLD_PORT} is free; cleaning stale state"
                    rm -f "${PID_FILE}" "${PORT_FILE}" "${PGID_FILE}" "${PROJECT_FILE}" "${OUTDIR_FILE}" "${BIND_ADDRESS_FILE}" "${IDENTITY_FILE}"
                else
                    PORT_CHECK_STATUS=$?
                    if [ "${PORT_CHECK_STATUS}" -eq 1 ]; then
                        log_error "Port ${OLD_PORT} remains in use"
                    else
                        log_error "Could not confirm port ${OLD_PORT} is free"
                    fi
                    log_error "State files preserved in: ${DASHBOARD_DIR}"
                    exit 1
                fi
            else
                log_error "Could not verify legacy PID and process-group absence"
                log_error "State files preserved in: ${DASHBOARD_DIR}"
                exit 1
            fi
        fi
    # First check if the process group is still alive
    elif kill -0 "${OLD_PID}" 2>/dev/null; then
        # Process exists, verify it's our dashboard
        if is_dashboard_running "${OLD_PID}" "${OLD_PORT}" "${PROJECT_DIR}" "${OUTDIR_ABS_CHECK}"; then
            # Dashboard is running and verified - check if configuration matches
            CONFIG_MATCHES=true
            CONFIG_DIFF=""

            # Check if requested port differs (and isn't occupied by another service)
            if [ "${PORT}" != "${OLD_PORT}" ]; then
                if check_port "${PORT}"; then
                    CONFIG_MATCHES=false
                    CONFIG_DIFF="${CONFIG_DIFF}  Port: ${OLD_PORT} -> ${PORT}\n"
                fi
            fi

            # Missing bind metadata is unknown and cannot establish a match.
            if [ -z "${OLD_BIND_ADDRESS}" ]; then
                CONFIG_MATCHES=false
                CONFIG_DIFF="${CONFIG_DIFF}  Bind address: UNKNOWN -> ${DASHBOARD_BIND_ADDRESS}\n"
            elif [ "${DASHBOARD_BIND_ADDRESS}" != "${OLD_BIND_ADDRESS}" ]; then
                CONFIG_MATCHES=false
                CONFIG_DIFF="${CONFIG_DIFF}  Bind address: ${OLD_BIND_ADDRESS} -> ${DASHBOARD_BIND_ADDRESS}\n"
            fi

            if [ "${CONFIG_MATCHES}" = "true" ]; then
                # Configuration matches, reuse existing dashboard
                log_info "Dashboard already running with matching configuration"
                log_info "  PID: ${OLD_PID}, Port: ${OLD_PORT}"

                # Build display URL based on bind address
                DISPLAY_URL="http://localhost:${OLD_PORT}"
                if [ -n "${OLD_BIND_ADDRESS}" ] && [ "${OLD_BIND_ADDRESS}" != "127.0.0.1" ] && [ "${OLD_BIND_ADDRESS}" != "0.0.0.0" ] && [ "${OLD_BIND_ADDRESS}" != "::" ]; then
                    DISPLAY_URL="http://$(format_url_host "${OLD_BIND_ADDRESS}"):${OLD_PORT}"
                fi

                echo ""
                echo "╔════════════════════════════════════════╗"
                echo "║  ASVFlow Live Dashboard                ║"
                printf "║  %-36s  ║\n" "${DISPLAY_URL}"
                echo "╚════════════════════════════════════════╝"
                echo ""
                exit 0
            else
                # Configuration differs, restart dashboard
                log_warning "Existing dashboard configuration differs from requested:"
                echo -e "${CONFIG_DIFF}"
                log_info "Restarting dashboard with new configuration..."

                # Verify dashboard identity before stopping
                if [ -f "${PROJECT_FILE}" ] && [ -f "${OUTDIR_FILE}" ]; then
                    STORED_PROJECT=$(cat "${PROJECT_FILE}")
                    STORED_OUTDIR=$(cat "${OUTDIR_FILE}")

                    if [ "${STORED_PROJECT}" = "${PROJECT_DIR}" ] && [ "${STORED_OUTDIR}" = "${OUTDIR_ABS_CHECK}" ]; then
                        # Verified - safe to stop
                        if ! stop_verified_dashboard "${OLD_PID}" "${OLD_PGID}" "${OLD_PORT}"; then
                            log_error "Failed to stop existing dashboard"
                            log_error "Do not signal stored PID/PGID values directly; verify ownership manually before recovery."
                            exit 1
                        fi
                        # Continue to launch new dashboard below
                    else
                        log_error "Cannot restart: stored metadata doesn't match current project"
                        log_error "Do not remove state files or signal stored IDs until process ownership and termination are manually confirmed."
                        exit 1
                    fi
                else
                    # Legacy dashboard without complete metadata - cannot safely restart
                    log_error "Existing dashboard lacks configuration metadata"
                    log_error "Do not use bin/stop_dashboard.sh; it cannot verify this legacy dashboard."
                    log_error "Stop it through the terminal or process manager that launched it."
                    log_error "If unavailable, have an administrator verify its process identity before stopping it."
                    exit 1
                fi
            fi
        else
            # Process exists but identity verification failed - do not clean
            log_error "PID ${OLD_PID} exists but does not match expected dashboard identity"
            log_error "Do not signal stored PID/PGID values or remove state files without manually confirming ownership and termination."
            exit 1
        fi
    else
        if dashboard_process_helper inspect "${OLD_PID}" "${OLD_PGID}" "${OLD_PORT}" "${PROJECT_DIR}" "${OUTDIR_ABS_CHECK}" "${IDENTITY_FILE}"; then
            log_error "The stored launcher PID is unavailable but its process group is active"
            log_error "Refusing cleanup without confirmed dashboard termination"
            exit 1
        else
            HELPER_STATUS=$?
            if [ "${HELPER_STATUS}" -eq 2 ]; then
                if check_port "${OLD_PORT}"; then
                    log_warning "Verified dashboard process group is gone, cleaning stale state"
                    rm -f "${PID_FILE}" "${PORT_FILE}" "${PGID_FILE}" "${PROJECT_FILE}" "${OUTDIR_FILE}" "${BIND_ADDRESS_FILE}" "${IDENTITY_FILE}"
                else
                    log_error "Dashboard process group is gone but port ${OLD_PORT} remains in use"
                    log_error "State files preserved in: ${DASHBOARD_DIR}"
                    exit 1
                fi
            else
                log_error "Could not verify stale dashboard ownership"
                log_error "State files preserved in: ${DASHBOARD_DIR}"
                exit 1
            fi
        fi
    fi
fi

chmod 700 "${DASHBOARD_DIR}"

ACTUAL_PORT="${PORT}"
if ! check_port "${ACTUAL_PORT}"; then
    log_error "Port ${ACTUAL_PORT} is already in use; refusing to start another dashboard or choose a fallback port"
    exit 1
fi

# Create output directory if it doesn't exist
mkdir -p "${OUTDIR}"
if [ -e "${COMPAT_DASHBOARD_DIR}" ] && [ ! -L "${COMPAT_DASHBOARD_DIR}" ]; then
    # A prior installation can leave a real compatibility directory after
    # per-user state has already been created. Merge only missing entries so
    # legacy artifacts remain available and current lifecycle metadata wins.
    find "${COMPAT_DASHBOARD_DIR}" -mindepth 1 -maxdepth 1 -exec cp -a --update=none -- {} "${DASHBOARD_DIR}/" \;
    chmod 700 "${DASHBOARD_DIR}"

    # Keep the original tree intact as an archive. Never replace an existing
    # archive, even if launches happen close together.
    legacy_archive="${COMPAT_DASHBOARD_DIR}.legacy.$(date +%s).$$"
    while [ -e "${legacy_archive}" ] || [ -L "${legacy_archive}" ]; do
        legacy_archive="${COMPAT_DASHBOARD_DIR}.legacy.$(date +%s).$$.${RANDOM}"
    done
    mv "${COMPAT_DASHBOARD_DIR}" "${legacy_archive}"
    log_info "Preserved legacy dashboard directory at ${legacy_archive}"
fi
ln -sfn "${DASHBOARD_DIR}" "${COMPAT_DASHBOARD_DIR}"

# Convert to absolute paths
OUTDIR_ABS="$(cd "${OUTDIR}" && pwd)"
# Launch dashboard in background
log_info "Starting dashboard..."
log_info "  Output directory: ${OUTDIR_ABS}"
log_info "  Port: ${ACTUAL_PORT}"
log_info "  Log file: ${LOG_FILE}"

# Use setsid to create new session - this makes the process the session leader and PGID = PID
# We avoid nested shell strings by using environment export
export STREAMLIT_SERVER_PORT="${ACTUAL_PORT}"
export STREAMLIT_SERVER_ADDRESS="${DASHBOARD_BIND_ADDRESS}"
export STREAMLIT_SERVER_HEADLESS=true
export STREAMLIT_BROWSER_GATHER_USAGE_STATS=false

setsid "${CONTAINER_RUNTIME}" exec \
    -B "${PROJECT_DIR}:${PROJECT_DIR}:ro" \
    -B "${OUTDIR_ABS}:${OUTDIR_ABS}:ro" \
    --pwd "${PROJECT_DIR}" \
    --cleanenv \
    "${DASHBOARD_SIF_ABS}" \
    streamlit run "${PROJECT_DIR}/dashboard/app.py" \
    --server.port="${ACTUAL_PORT}" \
    --server.address="${DASHBOARD_BIND_ADDRESS}" \
    --server.headless=true \
    --browser.gatherUsageStats=false \
    -- --outdir "${OUTDIR_ABS}" \
    > "${LOG_FILE}" 2>&1 &

DASHBOARD_PID=$!

# Verify the isolated session's process-group leader
DASHBOARD_PGID=$(ps -o pgid= -p "${DASHBOARD_PID}" 2>/dev/null | tr -d ' ')
if [ -z "${DASHBOARD_PGID}" ] || [ "${DASHBOARD_PGID}" != "${DASHBOARD_PID}" ]; then
    log_error "Failed to create process group (PID: ${DASHBOARD_PID}, PGID: ${DASHBOARD_PGID})"
    FAILED_STATE_DIR="${DASHBOARD_DIR}.failed.${DASHBOARD_PID}"
    mkdir -p "${FAILED_STATE_DIR}"
    echo "${DASHBOARD_PID}" > "${FAILED_STATE_DIR}/dashboard.pid"
    echo "${DASHBOARD_PGID:-unknown}" > "${FAILED_STATE_DIR}/dashboard.pgid"
    echo "${ACTUAL_PORT}" > "${FAILED_STATE_DIR}/dashboard.port"
    echo "${PROJECT_DIR}" > "${FAILED_STATE_DIR}/dashboard.project"
    echo "${OUTDIR_ABS}" > "${FAILED_STATE_DIR}/dashboard.outdir"
    log_error "Refusing automatic cleanup because process-group ownership could not be established."
    log_error "Verify the process identity manually before attempting recovery."
    log_error "Failure state preserved in: ${FAILED_STATE_DIR}"
    log_error "Check log file: ${LOG_FILE}"
    exit 1
fi

# Save PID, PGID, port, project, outdir, and bind address for reliable identification
echo "${DASHBOARD_PID}" > "${PID_FILE}"
echo "${DASHBOARD_PGID}" > "${PGID_FILE}"
echo "${ACTUAL_PORT}" > "${PORT_FILE}"
echo "${PROJECT_DIR}" > "${PROJECT_FILE}"
echo "${OUTDIR_ABS}" > "${OUTDIR_FILE}"
echo "${DASHBOARD_BIND_ADDRESS}" > "${BIND_ADDRESS_FILE}"
if ! dashboard_process_helper create "${DASHBOARD_PID}" "${DASHBOARD_PGID}" "${ACTUAL_PORT}" "${PROJECT_DIR}" "${OUTDIR_ABS}" "${IDENTITY_FILE}" "${DASHBOARD_SIF_ABS}" "${PROJECT_FILE}" "${OUTDIR_FILE}"; then
    log_error "Could not establish stable process ownership metadata."
    # The runtime may have failed before creating a container. Remove only
    # bookkeeping for an absent/zombie launcher and a confirmed free port.
    # A live or unverifiable process is left untouched with its state intact.
    LAUNCHER_STATE="$(ps -o stat= -p "${DASHBOARD_PID}" 2>/dev/null | tr -d ' ' || true)"
    if { [ -z "${LAUNCHER_STATE}" ] || [[ "${LAUNCHER_STATE}" == Z* || "${LAUNCHER_STATE}" == X* ]]; } && check_port_free_verified "${ACTUAL_PORT}"; then
        rm -f "${PID_FILE}" "${PORT_FILE}" "${PGID_FILE}" "${PROJECT_FILE}" "${OUTDIR_FILE}" "${BIND_ADDRESS_FILE}" "${IDENTITY_FILE}"
        log_warning "Removed state for the failed, inactive launch."
    else
        log_error "No processes were signaled; state files are preserved for manual recovery."
    fi
    exit 1
fi

# Wait for startup (max 15 seconds)
log_info "Waiting for dashboard to start..."
STARTUP_SUCCESS=false

# Build health check URL based on bind address (once, outside loop)
# Wildcard addresses are not directly reachable - use localhost for health check
if [ "${DASHBOARD_BIND_ADDRESS}" = "0.0.0.0" ] || [ "${DASHBOARD_BIND_ADDRESS}" = "::" ]; then
    HEALTH_CHECK_URL="http://127.0.0.1:${ACTUAL_PORT}"
else
    HEALTH_CHECK_URL="http://$(format_url_host "${DASHBOARD_BIND_ADDRESS}"):${ACTUAL_PORT}"
fi

for i in $(seq 1 30); do
    if ! kill -0 "${DASHBOARD_PID}" 2>/dev/null; then
        log_error "Dashboard process died during startup"
        log_error "Check log file: ${LOG_FILE}"
        if dashboard_process_helper inspect "${DASHBOARD_PID}" "${DASHBOARD_PGID}" "${ACTUAL_PORT}" "${PROJECT_DIR}" "${OUTDIR_ABS}" "${IDENTITY_FILE}"; then
            log_error "Dashboard process group remains active; state files preserved"
        else
            HELPER_STATUS=$?
            if [ "${HELPER_STATUS}" -eq 2 ]; then
                if check_port "${ACTUAL_PORT}"; then
                    rm -f "${PID_FILE}" "${PORT_FILE}" "${PGID_FILE}" "${PROJECT_FILE}" "${OUTDIR_FILE}" "${BIND_ADDRESS_FILE}" "${IDENTITY_FILE}"
                else
                    log_error "Dashboard process group is gone but port ${ACTUAL_PORT} remains in use"
                    log_error "State files preserved in: ${DASHBOARD_DIR}"
                fi
            else
                log_error "Dashboard ownership could not be verified; state files preserved"
            fi
        fi
        exit 1
    fi

    if curl -fsS -o /dev/null "${HEALTH_CHECK_URL}" 2>/dev/null; then
        STARTUP_SUCCESS=true
        break
    fi

    sleep 0.5
done

# Build display URL based on bind address
DISPLAY_URL="http://localhost:${ACTUAL_PORT}"
if [ "${DASHBOARD_BIND_ADDRESS}" != "127.0.0.1" ] && [ "${DASHBOARD_BIND_ADDRESS}" != "0.0.0.0" ] && [ "${DASHBOARD_BIND_ADDRESS}" != "::" ]; then
    DISPLAY_URL="http://$(format_url_host "${DASHBOARD_BIND_ADDRESS}"):${ACTUAL_PORT}"
fi

if [ "${STARTUP_SUCCESS}" = "true" ]; then
    log_success "Dashboard started successfully!"
    echo ""
    echo "╔════════════════════════════════════════╗"
    echo "║  ASVFlow Live Dashboard                ║"
    printf "║  %-36s  ║\n" "${DISPLAY_URL}"
    echo "║                                        ║"
    echo "║  PID: ${DASHBOARD_PID}                        ║"
    echo "║  Stop: bin/stop_dashboard.sh ${OUTDIR} ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    exit 0
else
    log_warning "Dashboard launched but not responding yet"
    log_warning "Process is running (PID: ${DASHBOARD_PID})"
    log_warning "Check log: ${LOG_FILE}"
    echo ""
    echo "Dashboard URL (may take a few more seconds): ${DISPLAY_URL}"
    echo ""
    exit 1
fi
