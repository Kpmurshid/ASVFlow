#!/bin/bash
# ASVFlow Live Dashboard Shutdown Script
# Gracefully stops the dashboard process

set -e

OUTDIR="${1:-results}"
DASHBOARD_DIR="${OUTDIR}/.asvflow_dashboard"
PID_FILE="${DASHBOARD_DIR}/dashboard.pid"
PORT_FILE="${DASHBOARD_DIR}/dashboard.port"

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

if [ ! -f "${PID_FILE}" ]; then
    log_warning "No dashboard PID file found in ${OUTDIR}"
    log_warning "Dashboard may not be running"
    exit 0
fi

PID=$(cat "${PID_FILE}")
PORT=$(cat "${PORT_FILE}" 2>/dev/null || echo "unknown")

if ! kill -0 "${PID}" 2>/dev/null; then
    log_warning "Dashboard process (PID: ${PID}) not running"
    rm -f "${PID_FILE}" "${PORT_FILE}"
    exit 0
fi

# Verify this is actually a dashboard process before killing
PROC_COMM=$(ps -p "${PID}" -o comm= 2>/dev/null || echo "")
if [[ ! "$PROC_COMM" =~ ^starter ]]; then
    log_error "PID ${PID} is not a Singularity process (found: ${PROC_COMM})"
    log_error "Refusing to kill unrelated process"
    log_warning "Cleaning up stale PID file"
    rm -f "${PID_FILE}" "${PORT_FILE}"
    exit 1
fi

log_info "Stopping dashboard (PID: ${PID}, Port: ${PORT})"

# Try graceful shutdown first
kill -TERM "${PID}" 2>/dev/null || true

# Wait up to 5 seconds for graceful shutdown
for i in $(seq 1 10); do
    if ! kill -0 "${PID}" 2>/dev/null; then
        log_info "Dashboard stopped gracefully"
        rm -f "${PID_FILE}" "${PORT_FILE}"
        exit 0
    fi
    sleep 0.5
done

# Force kill if still running
log_warning "Forcing dashboard shutdown..."
kill -KILL "${PID}" 2>/dev/null || true
rm -f "${PID_FILE}" "${PORT_FILE}"

log_info "Dashboard stopped"
exit 0
