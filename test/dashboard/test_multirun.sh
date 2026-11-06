#!/bin/bash
# Test: Port conflict handling and multiple dashboard instances
# Verifies independent dashboard instances can run simultaneously

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
LAUNCH_SCRIPT="${PROJECT_DIR}/bin/launch_dashboard.sh"
STOP_SCRIPT="${PROJECT_DIR}/bin/stop_dashboard.sh"

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

TESTS_PASSED=0
TESTS_FAILED=0

log_test() {
    echo -e "${YELLOW}[TEST]${NC} $1"
}

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

cleanup() {
    rm -rf /tmp/dashboard_multirun_* 2>/dev/null || true
}

trap cleanup EXIT

echo "=========================================="
echo "Port Conflict and Multi-Instance Tests"
echo "=========================================="
echo ""

# Test 1: Port conflict resolution
log_test "Test 1: Port conflict automatic resolution"
TEST_DIR1="/tmp/dashboard_multirun_1_$$"
TEST_DIR2="/tmp/dashboard_multirun_2_$$"
mkdir -p "${TEST_DIR1}" "${TEST_DIR2}"

# Start first dashboard on port 8501
"${LAUNCH_SCRIPT}" "${TEST_DIR1}" 8501 > /tmp/launch_port1.log 2>&1 &
sleep 3

PORT1=$(cat "${TEST_DIR1}/.asvflow_dashboard/dashboard.port" 2>/dev/null || echo "none")
if [ "${PORT1}" = "8501" ]; then
    log_pass "First dashboard started on requested port 8501"

    # Try to start second dashboard on same port - should auto-resolve
    "${LAUNCH_SCRIPT}" "${TEST_DIR2}" 8501 > /tmp/launch_port2.log 2>&1 &
    sleep 3

    PORT2=$(cat "${TEST_DIR2}/.asvflow_dashboard/dashboard.port" 2>/dev/null || echo "none")
    if [ "${PORT2}" != "8501" ] && [ "${PORT2}" != "none" ]; then
        log_pass "Second dashboard auto-resolved to port ${PORT2}"
    else
        log_fail "Port conflict not resolved (PORT2=${PORT2})"
    fi
else
    log_fail "First dashboard did not start on expected port"
fi

"${STOP_SCRIPT}" "${TEST_DIR1}" > /dev/null 2>&1 || true
"${STOP_SCRIPT}" "${TEST_DIR2}" > /dev/null 2>&1 || true
rm -rf "${TEST_DIR1}" "${TEST_DIR2}"

# Test 2: Multiple independent dashboards
log_test "Test 2: Multiple independent dashboard instances"
TEST_DIRS=()
for i in 1 2 3; do
    TEST_DIR="/tmp/dashboard_multirun_${i}_$$"
    TEST_DIRS+=("${TEST_DIR}")
    mkdir -p "${TEST_DIR}"

    PORT=$((8500 + i))
    "${LAUNCH_SCRIPT}" "${TEST_DIR}" ${PORT} > /dev/null 2>&1 &
    sleep 2
done

sleep 2

# Verify all instances running
ALL_RUNNING=true
for i in 1 2 3; do
    TEST_DIR="${TEST_DIRS[$((i-1))]}"
    if [ -f "${TEST_DIR}/.asvflow_dashboard/dashboard.pid" ]; then
        PID=$(cat "${TEST_DIR}/.asvflow_dashboard/dashboard.pid")
        if ! kill -0 "${PID}" 2>/dev/null; then
            ALL_RUNNING=false
        fi
    else
        ALL_RUNNING=false
    fi
done

if [ "${ALL_RUNNING}" = "true" ]; then
    log_pass "All 3 dashboard instances running independently"
else
    log_fail "Not all dashboard instances started successfully"
fi

# Verify PIDs are different
PIDS=()
for TEST_DIR in "${TEST_DIRS[@]}"; do
    if [ -f "${TEST_DIR}/.asvflow_dashboard/dashboard.pid" ]; then
        PIDS+=($(cat "${TEST_DIR}/.asvflow_dashboard/dashboard.pid"))
    fi
done

UNIQUE_PIDS=$(printf '%s\n' "${PIDS[@]}" | sort -u | wc -l)
if [ ${UNIQUE_PIDS} -eq 3 ]; then
    log_pass "Each dashboard has unique PID"
else
    log_fail "Dashboard PIDs are not unique (found ${UNIQUE_PIDS} unique PIDs)"
fi

# Clean up all instances
for TEST_DIR in "${TEST_DIRS[@]}"; do
    "${STOP_SCRIPT}" "${TEST_DIR}" > /dev/null 2>&1 || true
    rm -rf "${TEST_DIR}"
done

# Test 3: Dashboard isolation by output directory
log_test "Test 3: Dashboard instances isolated by output directory"
TEST_DIR1="/tmp/dashboard_multirun_iso1_$$"
TEST_DIR2="/tmp/dashboard_multirun_iso2_$$"
mkdir -p "${TEST_DIR1}" "${TEST_DIR2}"

"${LAUNCH_SCRIPT}" "${TEST_DIR1}" 8501 > /dev/null 2>&1 &
"${LAUNCH_SCRIPT}" "${TEST_DIR2}" 8502 > /dev/null 2>&1 &
sleep 3

PID1=$(cat "${TEST_DIR1}/.asvflow_dashboard/dashboard.pid" 2>/dev/null || echo "0")
PID2=$(cat "${TEST_DIR2}/.asvflow_dashboard/dashboard.pid" 2>/dev/null || echo "0")

if [ "${PID1}" != "0" ] && [ "${PID2}" != "0" ] && [ "${PID1}" != "${PID2}" ]; then
    log_pass "Dashboards isolated by output directory"

    # Stop first, verify second still running
    "${STOP_SCRIPT}" "${TEST_DIR1}" > /dev/null 2>&1
    sleep 1

    if ! kill -0 "${PID1}" 2>/dev/null && kill -0 "${PID2}" 2>/dev/null; then
        log_pass "Stopping one dashboard doesn't affect others"
    else
        log_fail "Dashboard shutdown affected other instances"
    fi
else
    log_fail "Dashboard isolation failed"
fi

"${STOP_SCRIPT}" "${TEST_DIR2}" > /dev/null 2>&1 || true
rm -rf "${TEST_DIR1}" "${TEST_DIR2}"

echo ""
echo "=========================================="
echo "Test Summary"
echo "=========================================="
echo -e "${GREEN}Passed: ${TESTS_PASSED}${NC}"
echo -e "${RED}Failed: ${TESTS_FAILED}${NC}"
echo ""

if [ ${TESTS_FAILED} -eq 0 ]; then
    echo -e "${GREEN}All multi-instance tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed${NC}"
    exit 1
fi
