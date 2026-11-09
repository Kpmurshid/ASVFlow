#!/bin/bash
# ASVFlow Live Dashboard Launcher
# Launches dashboard in background with robust error handling

set -e

# Default values
OUTDIR="${1:-results}"
PORT="${2:-8501}"
DASHBOARD_SIF="${3:-tools/asvflow-dashboard.sif}"
DASHBOARD_BIND_ADDRESS="${DASHBOARD_BIND_ADDRESS:-127.0.0.1}"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Dashboard state directory
DASHBOARD_DIR="${OUTDIR}/.asvflow_dashboard"
PID_FILE="${DASHBOARD_DIR}/dashboard.pid"
LOG_FILE="${DASHBOARD_DIR}/dashboard.log"
PORT_FILE="${DASHBOARD_DIR}/dashboard.port"
PGID_FILE="${DASHBOARD_DIR}/dashboard.pgid"
PROJECT_FILE="${DASHBOARD_DIR}/dashboard.project"
OUTDIR_FILE="${DASHBOARD_DIR}/dashboard.outdir"

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

# Create dashboard directory
mkdir -p "${DASHBOARD_DIR}"

# Check if dashboard SIF exists
if [ ! -f "${DASHBOARD_SIF}" ]; then
    log_error "Dashboard container not found: ${DASHBOARD_SIF}"
    log_error "Please build the container first:"
    log_error "  cd ${PROJECT_DIR}"
    log_error "  singularity build ${DASHBOARD_SIF} containers/dashboard.def"
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

    # Verify PID is a process group leader (PGID == PID)
    local actual_pgid=$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d ' ')
    if [ "$actual_pgid" != "$pid" ]; then
        return 1
    fi

    # Verify port is listening
    if ! (lsof -i ":${expected_port}" -sTCP:LISTEN 2>/dev/null | grep -q ":${expected_port}"); then
        if ! (ss -tuln 2>/dev/null | grep -q ":${expected_port}.*LISTEN"); then
            return 1
        fi
    fi

    # Verify project and outdir match stored values
    if [ -f "${PROJECT_FILE}" ] && [ -f "${OUTDIR_FILE}" ]; then
        local stored_project=$(cat "${PROJECT_FILE}")
        local stored_outdir=$(cat "${OUTDIR_FILE}")

        if [ "${stored_project}" = "${expected_project}" ] && [ "${stored_outdir}" = "${expected_outdir}" ]; then
            # Find streamlit process in the group and verify cmdline
            local streamlit_pids=$(pgrep -g "$pid" -x "streamlit" 2>/dev/null || true)
            if [ -n "$streamlit_pids" ]; then
                for spid in $streamlit_pids; do
                    if [ -f "/proc/$spid/cmdline" ]; then
                        local cmdline=$(tr '\0' ' ' < /proc/$spid/cmdline 2>/dev/null || true)
                        # Check for dashboard app.py, port, and outdir in command line
                        if echo "$cmdline" | grep -q "dashboard/app.py" && \
                           echo "$cmdline" | grep -q "server.port.*${expected_port}" && \
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

# Check if dashboard already running
if [ -f "${PID_FILE}" ] && [ -f "${PORT_FILE}" ]; then
    OLD_PID=$(cat "${PID_FILE}")
    OLD_PORT=$(cat "${PORT_FILE}")

    # Convert to absolute paths for comparison
    OUTDIR_ABS_CHECK="$(cd "${OUTDIR}" 2>/dev/null && pwd || echo "${OUTDIR}")"

    # First check if the process group is still alive
    if kill -0 "${OLD_PID}" 2>/dev/null; then
        # Process exists, verify it's our dashboard
        if is_dashboard_running "${OLD_PID}" "${OLD_PORT}" "${PROJECT_DIR}" "${OUTDIR_ABS_CHECK}"; then
            log_info "Dashboard already running (PID: ${OLD_PID}, Port: ${OLD_PORT})"
            echo ""
            echo "╔════════════════════════════════════════╗"
            echo "║  ASVFlow Live Dashboard                ║"
            echo "║  http://localhost:${OLD_PORT}              ║"
            echo "╚════════════════════════════════════════╝"
            echo ""
            exit 0
        else
            # Process exists but identity verification failed - do not clean
            log_error "PID ${OLD_PID} exists but does not match expected dashboard identity"
            log_error "Please stop the process manually and remove: ${DASHBOARD_DIR}"
            exit 1
        fi
    else
        # Process is dead, safe to clean up stale files
        log_warning "Stale dashboard state files found, cleaning up"
        rm -f "${PID_FILE}" "${PORT_FILE}" "${PGID_FILE}" "${PROJECT_FILE}" "${OUTDIR_FILE}"
    fi
fi

# Find available port if default is taken
check_port() {
    if lsof -i ":$1" >/dev/null 2>&1 || ss -tuln 2>/dev/null | grep -q ":$1 "; then
        return 1
    fi
    return 0
}

ACTUAL_PORT="${PORT}"
if ! check_port "${ACTUAL_PORT}"; then
    log_warning "Port ${ACTUAL_PORT} already in use, searching for available port..."
    for try_port in $(seq 8501 8520); do
        if check_port "${try_port}"; then
            ACTUAL_PORT="${try_port}"
            log_info "Found available port: ${ACTUAL_PORT}"
            break
        fi
    done

    if [ "${ACTUAL_PORT}" = "${PORT}" ]; then
        log_error "No available ports found in range 8501-8520"
        exit 1
    fi
fi

# Create output directory if it doesn't exist
mkdir -p "${OUTDIR}"

# Convert to absolute paths
OUTDIR_ABS="$(cd "${OUTDIR}" && pwd)"
DASHBOARD_SIF_ABS="$(cd "$(dirname "${DASHBOARD_SIF}")" && pwd)/$(basename "${DASHBOARD_SIF}")"

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

setsid singularity exec \
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

# Verify PGID == PID (setsid should ensure this)
DASHBOARD_PGID=$(ps -o pgid= -p "${DASHBOARD_PID}" 2>/dev/null | tr -d ' ')
if [ -z "${DASHBOARD_PGID}" ] || [ "${DASHBOARD_PGID}" != "${DASHBOARD_PID}" ]; then
    log_error "Failed to create process group (PID: ${DASHBOARD_PID}, PGID: ${DASHBOARD_PGID})"
    log_error "Check log file: ${LOG_FILE}"
    exit 1
fi

# Save PID, PGID, port, project, and outdir for reliable identification
echo "${DASHBOARD_PID}" > "${PID_FILE}"
echo "${DASHBOARD_PGID}" > "${PGID_FILE}"
echo "${ACTUAL_PORT}" > "${PORT_FILE}"
echo "${PROJECT_DIR}" > "${PROJECT_FILE}"
echo "${OUTDIR_ABS}" > "${OUTDIR_FILE}"

# Wait for startup (max 15 seconds)
log_info "Waiting for dashboard to start..."
STARTUP_SUCCESS=false

for i in $(seq 1 30); do
    if ! kill -0 "${DASHBOARD_PID}" 2>/dev/null; then
        log_error "Dashboard process died during startup"
        log_error "Check log file: ${LOG_FILE}"
        rm -f "${PID_FILE}" "${PORT_FILE}" "${PGID_FILE}" "${PROJECT_FILE}" "${OUTDIR_FILE}"
        exit 1
    fi

    if curl -s -o /dev/null "http://localhost:${ACTUAL_PORT}" 2>/dev/null; then
        STARTUP_SUCCESS=true
        break
    fi

    sleep 0.5
done

if [ "${STARTUP_SUCCESS}" = "true" ]; then
    log_success "Dashboard started successfully!"
    echo ""
    echo "╔════════════════════════════════════════╗"
    echo "║  ASVFlow Live Dashboard                ║"
    echo "║  http://localhost:${ACTUAL_PORT}              ║"
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
    echo "Dashboard URL (may take a few more seconds): http://localhost:${ACTUAL_PORT}"
    echo ""
    exit 0
fi
