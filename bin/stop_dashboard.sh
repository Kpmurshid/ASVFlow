#!/bin/bash
# ASVFlow Live Dashboard Shutdown Script
# Gracefully stops the dashboard process

set -e

OUTDIR="${1:-results}"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DASHBOARD_DIR="${OUTDIR}/.asvflow_dashboard"
PID_FILE="${DASHBOARD_DIR}/dashboard.pid"
PORT_FILE="${DASHBOARD_DIR}/dashboard.port"
PGID_FILE="${DASHBOARD_DIR}/dashboard.pgid"
PROJECT_FILE="${DASHBOARD_DIR}/dashboard.project"
OUTDIR_FILE="${DASHBOARD_DIR}/dashboard.outdir"

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

# Function to verify dashboard identity before termination
verify_dashboard_identity() {
    local pid="$1"
    local pgid="$2"
    local expected_project="$3"
    local expected_outdir="$4"

    # Check if process exists
    if ! kill -0 "$pid" 2>/dev/null; then
        return 1
    fi

    # Verify PGID == PID (must be process group leader)
    local actual_pgid=$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d ' ')
    if [ -z "$actual_pgid" ] || [ "$actual_pgid" != "$pid" ] || [ "$actual_pgid" != "$pgid" ]; then
        return 1
    fi

    # Verify stored project and outdir match
    if [ -f "${PROJECT_FILE}" ] && [ -f "${OUTDIR_FILE}" ]; then
        local stored_project=$(cat "${PROJECT_FILE}")
        local stored_outdir=$(cat "${OUTDIR_FILE}")

        if [ "${stored_project}" = "${expected_project}" ] && [ "${stored_outdir}" = "${expected_outdir}" ]; then
            # Find streamlit process in the group and verify cmdline
            local streamlit_pids=$(pgrep -g "$pgid" -x "streamlit" 2>/dev/null || true)
            if [ -n "$streamlit_pids" ]; then
                for spid in $streamlit_pids; do
                    if [ -f "/proc/$spid/cmdline" ]; then
                        local cmdline=$(tr '\0' ' ' < /proc/$spid/cmdline 2>/dev/null || true)
                        # Check for dashboard app.py and outdir in command line
                        if echo "$cmdline" | grep -q "dashboard/app.py" && \
                           echo "$cmdline" | grep -q "outdir.*${expected_outdir}"; then
                            return 0
                        fi
                    fi
                done
            fi
        fi
    fi

    return 1
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
    log_warning "No dashboard PID file found in ${OUTDIR}"
    log_warning "Dashboard may not be running"
    exit 0
fi

PID=$(cat "${PID_FILE}")
PGID=$(cat "${PGID_FILE}" 2>/dev/null || echo "${PID}")
PORT=$(cat "${PORT_FILE}" 2>/dev/null || echo "unknown")

# Convert to absolute path for comparison
OUTDIR_ABS="$(cd "${OUTDIR}" 2>/dev/null && pwd || echo "${OUTDIR}")"

# First check if process is still alive
if ! kill -0 "${PID}" 2>/dev/null; then
    log_warning "Dashboard process (PID: ${PID}) not running"
    log_warning "Cleaning up stale state files"
    rm -f "${PID_FILE}" "${PORT_FILE}" "${PGID_FILE}" "${PROJECT_FILE}" "${OUTDIR_FILE}"
    exit 0
fi

# Verify this is our dashboard before killing
if ! verify_dashboard_identity "${PID}" "${PGID}" "${PROJECT_DIR}" "${OUTDIR_ABS}"; then
    log_error "PID ${PID} exists but does not match this dashboard's identity"
    log_error "Refusing to kill potentially unrelated process"
    log_error "State files preserved in: ${DASHBOARD_DIR}"
    exit 1
fi

log_info "Stopping dashboard (PID: ${PID}, PGID: ${PGID}, Port: ${PORT})"

# Try graceful shutdown - kill entire process group
if ! kill -TERM -"${PGID}" 2>/dev/null; then
    log_error "Failed to send TERM signal to process group ${PGID}"
    log_error "State files preserved in: ${DASHBOARD_DIR}"
    exit 1
fi

# Wait up to 10 seconds for graceful shutdown
TIMEOUT=20
for i in $(seq 1 ${TIMEOUT}); do
    # Check if main process is gone
    if ! kill -0 "${PID}" 2>/dev/null; then
        # Verify no streamlit processes remain in the group
        if ! pgrep -g "${PGID}" -x "streamlit" >/dev/null 2>&1; then
            break
        fi
    fi
    sleep 0.5
done

# Check if process is still running after graceful shutdown
if kill -0 "${PID}" 2>/dev/null; then
    log_warning "Graceful shutdown timed out, forcing shutdown..."
    if ! kill -KILL -"${PGID}" 2>/dev/null; then
        log_error "Failed to send KILL signal to process group ${PGID}"
        log_error "State files preserved in: ${DASHBOARD_DIR}"
        exit 1
    fi
    sleep 1
fi

# Final verification - check both process termination and port release
PROCESS_DEAD=false
PORT_RELEASED=false

if ! kill -0 "${PID}" 2>/dev/null; then
    # Also verify no streamlit processes remain
    if ! pgrep -g "${PGID}" -x "streamlit" >/dev/null 2>&1; then
        PROCESS_DEAD=true
    fi
fi

if [ "${PORT}" != "unknown" ]; then
    if ! is_port_in_use "${PORT}"; then
        PORT_RELEASED=true
    fi
else
    PORT_RELEASED=true
fi

# Only remove state files if both process is dead and port is released
if [ "${PROCESS_DEAD}" = "true" ] && [ "${PORT_RELEASED}" = "true" ]; then
    log_info "Dashboard stopped"
    rm -f "${PID_FILE}" "${PORT_FILE}" "${PGID_FILE}" "${PROJECT_FILE}" "${OUTDIR_FILE}"
    exit 0
else
    if [ "${PROCESS_DEAD}" = "false" ]; then
        log_error "Dashboard process or children may still be running"
    fi
    if [ "${PORT_RELEASED}" = "false" ]; then
        log_error "Port ${PORT} is still in use"
    fi
    log_error "NOT removing state files - manual cleanup may be required"
    log_error "State files location: ${DASHBOARD_DIR}"
    exit 1
fi
