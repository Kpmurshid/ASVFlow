#!/bin/bash
# ASVFlow Live Dashboard Shutdown Script
# Gracefully stops the dashboard process

set -e

OUTDIR="${1:-results}"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTDIR_ABS="$(realpath -m -- "${OUTDIR}")"
STATE_ROOT="${ASVFLOW_STATE_DIR:-${XDG_STATE_HOME:-${HOME}/.local/state}/asvflow/dashboard}"
STATE_KEY="$(printf '%s' "${PROJECT_DIR}:${OUTDIR_ABS}" | sha256sum | awk '{print $1}')"
DASHBOARD_DIR="${STATE_ROOT}/${STATE_KEY}"
# Read old in-results state when migrating an installation created before the
# external state directory was introduced.
if [ ! -d "${DASHBOARD_DIR}" ] && [ -d "${OUTDIR}/.asvflow_dashboard" ] && [ ! -L "${OUTDIR}/.asvflow_dashboard" ]; then
    DASHBOARD_DIR="${OUTDIR}/.asvflow_dashboard"
fi
PID_FILE="${DASHBOARD_DIR}/dashboard.pid"
PORT_FILE="${DASHBOARD_DIR}/dashboard.port"
PGID_FILE="${DASHBOARD_DIR}/dashboard.pgid"
PROJECT_FILE="${DASHBOARD_DIR}/dashboard.project"
OUTDIR_FILE="${DASHBOARD_DIR}/dashboard.outdir"
BIND_ADDRESS_FILE="${DASHBOARD_DIR}/dashboard.bind_address"
IDENTITY_FILE="${DASHBOARD_DIR}/dashboard.identity"

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[Dashboard]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[Dashboard]${NC} $1"
}

log_error() {
    echo -e "${RED}[Dashboard]${NC} $1"
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
        try:
            exe = os.readlink("exe", dir_fd=proc_fd)
            exe_state = "readable"
        except FileNotFoundError:
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
    try:
        outdir_index = argv.index("--outdir")
    except ValueError:
        return False
    return (
        os.path.join(project, "dashboard", "app.py") in argv
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


helper_args = sys.argv[1:]
if len(helper_args) < 7:
    fail("Dashboard process helper requires action, PID, PGID, port, project, output directory, and identity path")
action, pid_text, pgid_text, port, project, outdir = helper_args[:6]
IDENTITY_PATH = helper_args[6]
extra = helper_args[7:]
if not pid_text.isdecimal() or not pgid_text.isdecimal():
    fail("PID and PGID must be decimal integers")
pid, pgid = int(pid_text), int(pgid_text)

try:
    fd = os.open(IDENTITY_PATH, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0))
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
metadata_dir = os.stat(os.path.dirname(IDENTITY_PATH), follow_symlinks=False)
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


def same_process_instance(left, right):
    # /proc stat's state field changes during normal scheduling (R/S/D); it is
    # not part of process identity. Compare stable fields before pidfd signals.
    if left is None or right is None:
        return False
    # The launcher may be reparented after its shell exits; PPID is therefore
    # intentionally excluded while its session and start time remain stable.
    stable = ("pgrp", "session", "start_ticks", "uid", "exe", "exe_state", "cmdline")
    return all(left.get(key) == right.get(key) for key in stable)


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
        if not same_process_instance(before, original_task):
            # A previously signaled child can make its verified container
            # parent exit naturally. Accept only when the whole group is gone.
            current_group = read_group()
            if not current_group:
                break
            close_group(current_group)
            fail(f"Process {target_pid} changed before pidfd_open")
        try:
            pidfd = os.pidfd_open(target_pid)
        except ProcessLookupError:
            current_group = read_group()
            if not current_group:
                break
            close_group(current_group)
            continue
        try:
            fdinfo = open(f"/proc/self/fdinfo/{pidfd}", encoding="ascii").read()
            if f"Pid:\t{target_pid}\n" not in fdinfo:
                fail(f"pidfd does not refer to expected PID {target_pid}")
            current = read_task(target_pid, proc_fd)
            if not same_process_instance(current, original_task):
                current_group = read_group()
                if not current_group:
                    break
                close_group(current_group)
                fail(f"pidfd target {target_pid} does not match the verified process instance")
            current_group = read_group()
            if not current_group:
                fail("Original dashboard ownership or process-group membership was lost")
            try:
                current_member = next(
                    (member for member in current_group if member[0] == target_pid),
                    None,
                )
                if current_member is None or not same_process_instance(current_member[1], original_task):
                    fail(f"Process {target_pid} is no longer a verified dashboard group member")
            finally:
                close_group(current_group)
            current = read_task(target_pid, proc_fd)
            if not same_process_instance(current, original_task):
                fail(f"Process {target_pid} changed immediately before signaling")
            signal.pidfd_send_signal(pidfd, signal_number)
        finally:
            os.close(pidfd)
finally:
    close_group(group)
PY
}

# Function to check if port is still in use
is_port_in_use() {
    local port="$1"
    if lsof -i ":${port}" -sTCP:LISTEN 2>/dev/null | grep -q ":${port}"; then
        return 0
    fi
    if ss -tuln 2>/dev/null | grep -q ":${port}.*LISTEN"; then
        return 0
    fi
    return 1
}

if [ ! -f "${PID_FILE}" ]; then
    log_warning "No dashboard PID file found in ${DASHBOARD_DIR}"
    log_warning "Dashboard may not be running"
    exit 0
fi

PID=$(cat "${PID_FILE}")
PGID=$(cat "${PGID_FILE}" 2>/dev/null || echo "")
PORT=$(cat "${PORT_FILE}" 2>/dev/null || echo "unknown")

# Convert to absolute path for comparison
OUTDIR_ABS="$(cd "${OUTDIR}" 2>/dev/null && pwd || echo "${OUTDIR}")"

if [[ ! "${PID}" =~ ^[0-9]+$ || ! "${PGID}" =~ ^[0-9]+$ || ! "${PORT}" =~ ^[0-9]+$ ]]; then
    log_error "Dashboard PID, PGID, or port metadata is missing or invalid"
    log_error "State files preserved in: ${DASHBOARD_DIR}"
    exit 1
fi

if [ ! -f "${IDENTITY_FILE}" ] || [ ! -f "${PROJECT_FILE}" ] || [ ! -f "${OUTDIR_FILE}" ]; then
    log_error "Dashboard ownership metadata is missing (legacy or partial state)"
    log_error "Refusing automatic termination; verify process identity manually before recovery."
    log_error "Do not signal stored PID/PGID values directly."
    log_error "State files preserved in: ${DASHBOARD_DIR}"
    exit 1
fi

if [ "$(cat "${PROJECT_FILE}")" != "${PROJECT_DIR}" ] || [ "$(cat "${OUTDIR_FILE}")" != "${OUTDIR_ABS}" ]; then
    log_error "Stored project or output-directory metadata does not match"
    log_error "Refusing automatic termination; state files preserved in: ${DASHBOARD_DIR}"
    exit 1
fi

if dashboard_process_helper inspect "${PID}" "${PGID}" "${PORT}" "${PROJECT_DIR}" "${OUTDIR_ABS}" "${IDENTITY_FILE}"; then
    :
else
    HELPER_STATUS=$?
    if [ "${HELPER_STATUS}" -eq 2 ]; then
        if ! is_port_in_use "${PORT}"; then
            log_warning "Verified dashboard process group is gone; cleaning stale state"
            rm -f "${PID_FILE}" "${PORT_FILE}" "${PGID_FILE}" "${PROJECT_FILE}" "${OUTDIR_FILE}" "${BIND_ADDRESS_FILE}" "${IDENTITY_FILE}"
            exit 0
        fi
        log_error "Dashboard process group is gone but port ${PORT} remains in use"
    else
        log_error "Dashboard ownership verification failed"
    fi
    log_error "State files preserved in: ${DASHBOARD_DIR}"
    exit 1
fi

log_info "Stopping dashboard (PID: ${PID}, PGID: ${PGID}, Port: ${PORT})"
if ! dashboard_process_helper signal "${PID}" "${PGID}" "${PORT}" "${PROJECT_DIR}" "${OUTDIR_ABS}" "${IDENTITY_FILE}" TERM; then
    log_error "TERM was not sent because ownership could not be verified"
    log_error "State files preserved in: ${DASHBOARD_DIR}"
    exit 1
fi

GROUP_GONE=false
for i in $(seq 1 20); do
    if dashboard_process_helper inspect "${PID}" "${PGID}" "${PORT}" "${PROJECT_DIR}" "${OUTDIR_ABS}" "${IDENTITY_FILE}"; then
        sleep 0.5
    else
        HELPER_STATUS=$?
        if [ "${HELPER_STATUS}" -eq 2 ]; then
            GROUP_GONE=true
            break
        fi
        log_error "Ownership verification failed after TERM; preserving state files"
        exit 1
    fi
done

if [ "${GROUP_GONE}" != "true" ]; then
    if dashboard_process_helper inspect "${PID}" "${PGID}" "${PORT}" "${PROJECT_DIR}" "${OUTDIR_ABS}" "${IDENTITY_FILE}"; then
        log_warning "Graceful shutdown timed out; verifying ownership again before KILL..."
        if ! dashboard_process_helper signal "${PID}" "${PGID}" "${PORT}" "${PROJECT_DIR}" "${OUTDIR_ABS}" "${IDENTITY_FILE}" KILL; then
            log_error "KILL was not sent because ownership could not be verified"
            log_error "State files preserved in: ${DASHBOARD_DIR}"
            exit 1
        fi
    else
        HELPER_STATUS=$?
        if [ "${HELPER_STATUS}" -eq 2 ]; then
            GROUP_GONE=true
        else
            log_error "Ownership verification failed; refusing KILL"
            log_error "State files preserved in: ${DASHBOARD_DIR}"
            exit 1
        fi
    fi
fi

if [ "${GROUP_GONE}" != "true" ]; then
    for i in $(seq 1 20); do
        if dashboard_process_helper inspect "${PID}" "${PGID}" "${PORT}" "${PROJECT_DIR}" "${OUTDIR_ABS}" "${IDENTITY_FILE}"; then
            sleep 0.5
        else
            HELPER_STATUS=$?
            if [ "${HELPER_STATUS}" -eq 2 ]; then
                GROUP_GONE=true
                break
            fi
            log_error "Ownership verification failed after KILL; preserving state files"
            exit 1
        fi
    done
fi

if [ "${GROUP_GONE}" = "true" ] && ! is_port_in_use "${PORT}"; then
    log_info "Dashboard stopped"
    rm -f "${PID_FILE}" "${PORT_FILE}" "${PGID_FILE}" "${PROJECT_FILE}" "${OUTDIR_FILE}" "${BIND_ADDRESS_FILE}" "${IDENTITY_FILE}"
    exit 0
else
    if [ "${GROUP_GONE}" != "true" ]; then
        log_error "Dashboard process group may still be running"
    fi
    if is_port_in_use "${PORT}"; then
        log_error "Port ${PORT} is still in use"
    fi
    log_error "NOT removing state files - manual cleanup may be required"
    log_error "State files location: ${DASHBOARD_DIR}"
    exit 1
fi
