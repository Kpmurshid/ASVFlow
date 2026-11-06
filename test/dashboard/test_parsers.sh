#!/bin/bash
# Test: Run discovery and trace parsing with various edge cases
# Tests parsers with missing, incomplete, and malformed data

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

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
    rm -rf /tmp/dashboard_parser_test_* 2>/dev/null || true
}

trap cleanup EXIT

echo "=========================================="
echo "Parser Robustness Tests"
echo "=========================================="
echo ""

# Test 1: Missing execution trace file
log_test "Test 1: Missing execution_trace.txt"
TEST_DIR="/tmp/dashboard_parser_test_missing_$$"
mkdir -p "${TEST_DIR}"

python3 << EOF
import sys
sys.path.insert(0, '${PROJECT_DIR}/dashboard')
from parsers import OutputScanner

scanner = OutputScanner('${TEST_DIR}')
df = scanner.get_execution_trace()

if df.empty:
    print("PASS: Empty DataFrame returned for missing trace file")
    sys.exit(0)
else:
    print("FAIL: Non-empty DataFrame for missing file")
    sys.exit(1)
EOF

if [ $? -eq 0 ]; then
    log_pass "Missing trace file handled gracefully"
else
    log_fail "Missing trace file not handled"
fi

rm -rf "${TEST_DIR}"

# Test 2: Empty execution trace file
log_test "Test 2: Empty execution_trace.txt"
TEST_DIR="/tmp/dashboard_parser_test_empty_$$"
mkdir -p "${TEST_DIR}"
touch "${TEST_DIR}/execution_trace.txt"

python3 << EOF
import sys
sys.path.insert(0, '${PROJECT_DIR}/dashboard')
from parsers import OutputScanner

scanner = OutputScanner('${TEST_DIR}')
df = scanner.get_execution_trace()

if df.empty:
    print("PASS: Empty DataFrame for empty file")
    sys.exit(0)
else:
    print("FAIL: Non-empty DataFrame for empty file")
    sys.exit(1)
EOF

if [ $? -eq 0 ]; then
    log_pass "Empty trace file handled gracefully"
else
    log_fail "Empty trace file not handled"
fi

rm -rf "${TEST_DIR}"

# Test 3: Valid trace file with task summary verification
log_test "Test 3: Task summary excludes 'running' field"
TEST_DIR="/tmp/dashboard_parser_test_valid_$$"
mkdir -p "${TEST_DIR}"
cat > "${TEST_DIR}/execution_trace.txt" << 'TRACEFILE'
task_id	hash	native_id	name	status	exit	submit	duration	realtime	%cpu	peak_rss	peak_vmem	rchar	wchar
1	a1/b2c3d4	12345	TASK1	COMPLETED	0	2026-11-06 10:00:00	5s	4.8s	98.5%	100 MB	500 MB	1 MB	500 KB
2	e5/f6g7h8	12346	TASK2	CACHED	0	2026-11-06 10:00:05	1s	0.5s	0%	0	0	0	0
3	i9/j0k1l2	12347	TASK3	COMPLETED	1	2026-11-06 10:00:10	3s	2.9s	95.2%	80 MB	400 MB	800 KB	200 KB
TRACEFILE

python3 << EOF
import sys
sys.path.insert(0, '${PROJECT_DIR}/dashboard')
from parsers import OutputScanner

scanner = OutputScanner('${TEST_DIR}')
summary = scanner.get_task_status_summary()

# Verify 'running' key doesn't exist
if 'running' in summary:
    print("FAIL: 'running' key should not exist in Phase 1.1")
    sys.exit(1)
else:
    print("PASS: 'running' key removed from summary")

# Check counts
if summary['total'] == 3 and summary['completed'] == 2 and summary['cached'] == 1 and summary['failed'] == 1:
    print("PASS: Task summary calculated correctly")
    sys.exit(0)
else:
    print(f"FAIL: Summary incorrect: {summary}")
    sys.exit(1)
EOF

if [ $? -eq 0 ]; then
    log_pass "Task summary correct without 'running' field"
else
    log_fail "Task summary verification failed"
fi

rm -rf "${TEST_DIR}"

echo ""
echo "=========================================="
echo "Test Summary"
echo "=========================================="
echo -e "${GREEN}Passed: ${TESTS_PASSED}${NC}"
echo -e "${RED}Failed: ${TESTS_FAILED}${NC}"
echo ""

if [ ${TESTS_FAILED} -eq 0 ]; then
    echo -e "${GREEN}All parser tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed${NC}"
    exit 1
fi
