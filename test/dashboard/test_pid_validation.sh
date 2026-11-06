#!/bin/bash
# Test: PID validation and stale PID cleanup
# Tests Phase 1.1 PID verification improvements

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
    rm -rf /tmp/dashboard_test_* 2>/dev/null || true
    pkill -f "dashboard_test_" 2>/dev/null || true
}

trap cleanup EXIT

echo "=========================================="
echo "PID Validation and Stale PID Cleanup Tests"
echo "=========================================="
echo ""

# Test 1: Stale PID cleanup (process doesn't exist)
log_test "Test 1: Stale PID cleanup - process doesn't exist"
TEST_DIR="/tmp/dashboard_test_stale_$$"
mkdir -p "${TEST_DIR}/.asvflow_dashboard"
echo "999999" > "${TEST_DIR}/.asvflow_dashboard/dashboard.pid"
echo "8501" > "${TEST_DIR}/.asvflow_dashboard/dashboard.port"

if "${LAUNCH_SCRIPT}" "${TEST_DIR}" 8599 2>&1 | grep -q "Stale PID file found"; then
    if [ ! -f "${TEST_DIR}/.asvflow_dashboard/dashboard.pid" ] || [ "$(cat ${TEST_DIR}/.asvflow_dashboard/dashboard.pid)" != "999999" ]; then
        log_pass "Stale PID file was cleaned up and new dashboard started"
    else
        log_fail "Stale PID file was not cleaned up properly"
    fi
else
    log_fail "Script did not detect stale PID file"
fi
"${STOP_SCRIPT}" "${TEST_DIR}" > /dev/null 2>&1 || true
rm -rf "${TEST_DIR}"

# Test 2: PID reuse detection (PID exists but is not dashboard)
log_test "Test 2: PID reuse detection - PID exists but wrong process"
TEST_DIR="/tmp/dashboard_test_reuse_$$"
mkdir -p "${TEST_DIR}/.asvflow_dashboard"

# Use current shell's PID - we can check it but it's not Singularity
echo "$$" > "${TEST_DIR}/.asvflow_dashboard/dashboard.pid"
echo "8501" > "${TEST_DIR}/.asvflow_dashboard/dashboard.port"

OUTPUT=$("${LAUNCH_SCRIPT}" "${TEST_DIR}" 8599 2>&1)
if echo "$OUTPUT" | grep -q "not ASVFlow dashboard"; then
    log_pass "PID reuse detected and rejected"
else
    # May also show as "Stale PID" if process name doesn't match
    if echo "$OUTPUT" | grep -E "(not ASVFlow dashboard|Cleaning up stale)" >/dev/null; then
        log_pass "PID reuse handled (cleaned up non-dashboard process)"
    else
        log_fail "PID reuse not detected (may have accepted wrong PID)"
    fi
fi
"${STOP_SCRIPT}" "${TEST_DIR}" > /dev/null 2>&1 || true
rm -rf "${TEST_DIR}"

# Test 3: Valid dashboard detection
log_test "Test 3: Valid dashboard already running"
TEST_DIR="/tmp/dashboard_test_valid_$$"
mkdir -p "${TEST_DIR}"

# Start real dashboard
"${LAUNCH_SCRIPT}" "${TEST_DIR}" 8599 > /tmp/launch1.log 2>&1 &
sleep 3

if [ -f "${TEST_DIR}/.asvflow_dashboard/dashboard.pid" ]; then
    DASHBOARD_PID=$(cat "${TEST_DIR}/.asvflow_dashboard/dashboard.pid")

    # Try to launch again - should detect existing dashboard
    OUTPUT=$("${LAUNCH_SCRIPT}" "${TEST_DIR}" 8599 2>&1)

    if echo "$OUTPUT" | grep -q "Dashboard already running"; then
        log_pass "Existing dashboard correctly detected"
    else
        log_fail "Existing dashboard not detected"
    fi

    # Verify PID is still the same
    CURRENT_PID=$(cat "${TEST_DIR}/.asvflow_dashboard/dashboard.pid")
    if [ "${CURRENT_PID}" = "${DASHBOARD_PID}" ]; then
        log_pass "PID unchanged after detection"
    else
        log_fail "PID changed unexpectedly"
    fi
else
    log_fail "Dashboard PID file not created"
fi

"${STOP_SCRIPT}" "${TEST_DIR}" > /dev/null 2>&1 || true
rm -rf "${TEST_DIR}"

# Test 4: Stop script refuses to kill wrong process
log_test "Test 4: Stop script refuses to kill unrelated process"
TEST_DIR="/tmp/dashboard_test_stop_$$"
mkdir -p "${TEST_DIR}/.asvflow_dashboard"

# Use current shell's PID (bash, not Singularity starter)
echo "$$" > "${TEST_DIR}/.asvflow_dashboard/dashboard.pid"
echo "8501" > "${TEST_DIR}/.asvflow_dashboard/dashboard.port"

OUTPUT=$("${STOP_SCRIPT}" "${TEST_DIR}" 2>&1 || true)
if echo "$OUTPUT" | grep -q "Refusing to kill"; then
    log_pass "Stop script correctly refused to kill wrong process"
else
    log_fail "Stop script did not validate process identity"
fi

rm -rf "${TEST_DIR}"

# Test 5: Singularity process verification
log_test "Test 5: Verify dashboard process is Singularity starter"
TEST_DIR="/tmp/dashboard_test_singularity_$$"
mkdir -p "${TEST_DIR}"

"${LAUNCH_SCRIPT}" "${TEST_DIR}" 8599 > /dev/null 2>&1 &
sleep 3

if [ -f "${TEST_DIR}/.asvflow_dashboard/dashboard.pid" ]; then
    DASHBOARD_PID=$(cat "${TEST_DIR}/.asvflow_dashboard/dashboard.pid")
    PROC_COMM=$(ps -p "${DASHBOARD_PID}" -o comm= 2>/dev/null || echo "not_found")

    if [[ "$PROC_COMM" =~ ^starter ]]; then
        log_pass "Dashboard PID is Singularity starter process"

        # Verify streamlit child exists
        if pgrep -P "${DASHBOARD_PID}" -x "streamlit" >/dev/null 2>&1; then
            log_pass "Streamlit child process found under Singularity parent"
        else
            log_fail "Streamlit child process not found"
        fi
    else
        log_fail "Dashboard PID is not Singularity starter (found: ${PROC_COMM})"
    fi
else
    log_fail "Dashboard PID file not created"
fi

"${STOP_SCRIPT}" "${TEST_DIR}" > /dev/null 2>&1 || true
rm -rf "${TEST_DIR}"

echo ""
echo "=========================================="
echo "Test Summary"
echo "=========================================="
echo -e "${GREEN}Passed: ${TESTS_PASSED}${NC}"
echo -e "${RED}Failed: ${TESTS_FAILED}${NC}"
echo ""

if [ ${TESTS_FAILED} -eq 0 ]; then
    echo -e "${GREEN}All PID validation tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed${NC}"
    exit 1
fi
