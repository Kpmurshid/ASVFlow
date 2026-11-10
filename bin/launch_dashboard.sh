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
    log_error "Attempting cleanup of launched processes..."

    # Persist failure state before attempting cleanup (in case cleanup partially fails)
    # Use a temporary directory to avoid overwriting state from a successful dashboard
    FAILED_STATE_DIR="${DASHBOARD_DIR}.failed.${DASHBOARD_PID}"
    mkdir -p "${FAILED_STATE_DIR}"
    echo "${DASHBOARD_PID}" > "${FAILED_STATE_DIR}/dashboard.pid"
    echo "${DASHBOARD_PGID:-unknown}" > "${FAILED_STATE_DIR}/dashboard.pgid"
    echo "${ACTUAL_PORT}" > "${FAILED_STATE_DIR}/dashboard.port"
    echo "${PROJECT_DIR}" > "${FAILED_STATE_DIR}/dashboard.project"
    echo "${OUTDIR_ABS}" > "${FAILED_STATE_DIR}/dashboard.outdir"

    CLEANUP_FAILED=false

    # Determine cleanup strategy based on PGID state
    if [ -n "${DASHBOARD_PGID}" ] && [ "${DASHBOARD_PGID}" != "${DASHBOARD_PID}" ]; then
        # Unexpected PGID - terminate only the direct Singularity PID we launched
        if kill -0 "${DASHBOARD_PID}" 2>/dev/null; then
            kill -TERM "${DASHBOARD_PID}" 2>/dev/null || true
            sleep 1
            if kill -0 "${DASHBOARD_PID}" 2>/dev/null; then
                kill -KILL "${DASHBOARD_PID}" 2>/dev/null || true
                sleep 0.5
            fi
            # Verify both parent termination and no orphaned Streamlit children
            if kill -0 "${DASHBOARD_PID}" 2>/dev/null; then
                CLEANUP_FAILED=true
            else
                # Parent terminated - check for orphaned Streamlit on this port
                if lsof -i ":${ACTUAL_PORT}" -sTCP:LISTEN 2>/dev/null | grep -q ":${ACTUAL_PORT}"; then
                    CLEANUP_FAILED=true
                elif ss -tuln 2>/dev/null | grep -q ":${ACTUAL_PORT}.*LISTEN"; then
                    CLEANUP_FAILED=true
                fi
            fi
        fi
    elif [ -n "${DASHBOARD_PGID}" ] && [ "${DASHBOARD_PGID}" = "${DASHBOARD_PID}" ]; then
        # PGID matches PID - verify the process identity before signaling group
        # Confirm DASHBOARD_PID still exists, has correct PGID, and is the Singularity command
        if kill -0 "${DASHBOARD_PID}" 2>/dev/null; then
            CURRENT_PGID=$(ps -o pgid= -p "${DASHBOARD_PID}" 2>/dev/null | tr -d ' ')
            if [ "$CURRENT_PGID" = "${DASHBOARD_PGID}" ] && [ -f "/proc/${DASHBOARD_PID}/cmdline" ]; then
                PID_CMDLINE=$(tr '\0' ' ' < "/proc/${DASHBOARD_PID}/cmdline" 2>/dev/null || echo "")
                # Verify this is the Singularity exec we launched
                if echo "$PID_CMDLINE" | grep -q "singularity exec" && \
                   echo "$PID_CMDLINE" | grep -q "dashboard/app.py"; then
                    # Identity confirmed - safe to terminate the group
                    kill -TERM -"${DASHBOARD_PGID}" 2>/dev/null || true
                    sleep 1
                    if pgrep -g "${DASHBOARD_PGID}" >/dev/null 2>&1; then
                        kill -KILL -"${DASHBOARD_PGID}" 2>/dev/null || true
                        sleep 0.5
                    fi
                    # Verify no processes remain in group (parent and children)
                    if pgrep -g "${DASHBOARD_PGID}" >/dev/null 2>&1; then
                        CLEANUP_FAILED=true
                    fi
                    # Also verify no Streamlit process on the port
                    if ! pgrep -g "${DASHBOARD_PGID}" >/dev/null 2>&1; then
                        if lsof -i ":${ACTUAL_PORT}" -sTCP:LISTEN 2>/dev/null | grep -q ":${ACTUAL_PORT}"; then
                            CLEANUP_FAILED=true
                        elif ss -tuln 2>/dev/null | grep -q ":${ACTUAL_PORT}.*LISTEN"; then
                            CLEANUP_FAILED=true
                        fi
                    fi
                else
                    # Process exists but not the one we launched - do not signal
                    log_error "Process ${DASHBOARD_PID} exists but is not the expected Singularity command"
                    CLEANUP_FAILED=true
                fi
            else
                # PGID changed or process no longer exists - try to cleanup what remains
                if kill -0 "${DASHBOARD_PID}" 2>/dev/null; then
                    kill -TERM "${DASHBOARD_PID}" 2>/dev/null || true
                    sleep 1
                    if kill -0 "${DASHBOARD_PID}" 2>/dev/null; then
                        kill -KILL "${DASHBOARD_PID}" 2>/dev/null || true
                        sleep 0.5
                    fi
                    if kill -0 "${DASHBOARD_PID}" 2>/dev/null; then
                        CLEANUP_FAILED=true
                    fi
                fi
                # Check port regardless
                if lsof -i ":${ACTUAL_PORT}" -sTCP:LISTEN 2>/dev/null | grep -q ":${ACTUAL_PORT}"; then
                    CLEANUP_FAILED=true
                elif ss -tuln 2>/dev/null | grep -q ":${ACTUAL_PORT}.*LISTEN"; then
                    CLEANUP_FAILED=true
                fi
            fi
        fi
    else
        # No PGID - try direct PID cleanup
        if kill -0 "${DASHBOARD_PID}" 2>/dev/null; then
            kill -TERM "${DASHBOARD_PID}" 2>/dev/null || true
            sleep 1
            if kill -0 "${DASHBOARD_PID}" 2>/dev/null; then
                kill -KILL "${DASHBOARD_PID}" 2>/dev/null || true
                sleep 0.5
            fi
            # Verify both parent and port
            if kill -0 "${DASHBOARD_PID}" 2>/dev/null; then
                CLEANUP_FAILED=true
            else
                # Parent gone - check port for orphaned child
                if lsof -i ":${ACTUAL_PORT}" -sTCP:LISTEN 2>/dev/null | grep -q ":${ACTUAL_PORT}"; then
                    CLEANUP_FAILED=true
                elif ss -tuln 2>/dev/null | grep -q ":${ACTUAL_PORT}.*LISTEN"; then
                    CLEANUP_FAILED=true
                fi
            fi
        fi
    fi

    if [ "$CLEANUP_FAILED" = "true" ]; then
        log_error "Failed to terminate all launched processes"
        log_error "Manual cleanup required for PID ${DASHBOARD_PID} and/or port ${ACTUAL_PORT}"
        log_error "State directory preserved: ${FAILED_STATE_DIR}"
    else
        log_error "Cleanup completed"
        rm -rf "${FAILED_STATE_DIR}"
    fi

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

# Build health check URL based on bind address (once, outside loop)
# Wildcard addresses are not directly reachable - use localhost for health check
if [ "${DASHBOARD_BIND_ADDRESS}" = "0.0.0.0" ] || [ "${DASHBOARD_BIND_ADDRESS}" = "::" ]; then
    HEALTH_CHECK_URL="http://127.0.0.1:${ACTUAL_PORT}"
else
    HEALTH_CHECK_URL="http://${DASHBOARD_BIND_ADDRESS}:${ACTUAL_PORT}"
fi

for i in $(seq 1 30); do
    if ! kill -0 "${DASHBOARD_PID}" 2>/dev/null; then
        log_error "Dashboard process died during startup"
        log_error "Check log file: ${LOG_FILE}"
        rm -f "${PID_FILE}" "${PORT_FILE}" "${PGID_FILE}" "${PROJECT_FILE}" "${OUTDIR_FILE}"
        exit 1
    fi

    if curl -s -o /dev/null "${HEALTH_CHECK_URL}" 2>/dev/null; then
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
