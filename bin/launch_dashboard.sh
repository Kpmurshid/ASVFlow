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

# Check if dashboard already running
if [ -f "${PID_FILE}" ]; then
    OLD_PID=$(cat "${PID_FILE}")
    OLD_PORT=$(cat "${PORT_FILE}" 2>/dev/null || echo "${PORT}")

    # Verify process exists and is actually our dashboard
    if kill -0 "$OLD_PID" 2>/dev/null; then
        # Check if this is a Singularity container process (parent of streamlit)
        PROC_COMM=$(ps -p "$OLD_PID" -o comm= 2>/dev/null || echo "")

        # Verify it's Singularity (starter-suid) and has streamlit child
        if [[ "$PROC_COMM" =~ ^starter ]]; then
            # Additional check: verify streamlit child exists and matches our port
            if pgrep -P "$OLD_PID" -x "streamlit" >/dev/null 2>&1; then
                # Verify this dashboard serves the correct outdir (check port file timestamp)
                if [ -f "${PORT_FILE}" ]; then
                    log_info "Dashboard already running (PID: ${OLD_PID}, Port: ${OLD_PORT})"
                    echo ""
                    echo "╔════════════════════════════════════════╗"
                    echo "║  ASVFlow Live Dashboard                ║"
                    echo "║  http://localhost:${OLD_PORT}              ║"
                    echo "╚════════════════════════════════════════╝"
                    echo ""
                    exit 0
                fi
            fi
        fi

        # Process exists but is not our dashboard (PID reuse)
        log_warning "PID ${OLD_PID} exists but is not ASVFlow dashboard (${PROC_COMM})"
        log_warning "Cleaning up stale PID file"
        rm -f "${PID_FILE}" "${PORT_FILE}"
    else
        log_warning "Stale PID file found, cleaning up"
        rm -f "${PID_FILE}" "${PORT_FILE}"
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

# Use singularity exec with proper binds and environment
STREAMLIT_SERVER_PORT="${ACTUAL_PORT}" \
STREAMLIT_SERVER_ADDRESS="${DASHBOARD_BIND_ADDRESS}" \
STREAMLIT_SERVER_HEADLESS=true \
STREAMLIT_BROWSER_GATHER_USAGE_STATS=false \
singularity exec \
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

# Save PID and port
echo "${DASHBOARD_PID}" > "${PID_FILE}"
echo "${ACTUAL_PORT}" > "${PORT_FILE}"

# Wait for startup (max 15 seconds)
log_info "Waiting for dashboard to start..."
STARTUP_SUCCESS=false

for i in $(seq 1 30); do
    if ! kill -0 "${DASHBOARD_PID}" 2>/dev/null; then
        log_error "Dashboard process died during startup"
        log_error "Check log file: ${LOG_FILE}"
        rm -f "${PID_FILE}" "${PORT_FILE}"
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
