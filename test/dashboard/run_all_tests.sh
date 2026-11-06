#!/bin/bash
# ASVFlow Live Dashboard Test Suite Runner
# Phase 1.1 - Reliability and Accuracy Tests

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo ""
echo "=========================================="
echo "ASVFlow Live Dashboard Test Suite"
echo "Phase 1.1 - Reliability and Accuracy"
echo "=========================================="
echo ""

TOTAL_PASSED=0
TOTAL_FAILED=0
TEST_SUITES=0

run_test_suite() {
    local test_script=$1
    local test_name=$2

    echo -e "${BLUE}Running: ${test_name}${NC}"
    echo "=========================================="

    if bash "${test_script}"; then
        echo -e "${GREEN}✓ ${test_name} PASSED${NC}"
        TOTAL_PASSED=$((TOTAL_PASSED + 1))
    else
        echo -e "${RED}✗ ${test_name} FAILED${NC}"
        TOTAL_FAILED=$((TOTAL_FAILED + 1))
    fi

    TEST_SUITES=$((TEST_SUITES + 1))
    echo ""
}

# Check if dashboard SIF exists
if [ ! -f "${SCRIPT_DIR}/../../tools/asvflow-dashboard.sif" ]; then
    echo -e "${YELLOW}Warning: Dashboard container not found${NC}"
    echo "Some tests may fail. Build with:"
    echo "  cd ${SCRIPT_DIR}/../.."
    echo "  singularity build tools/asvflow-dashboard.sif containers/dashboard.def"
    echo ""
fi

# Run test suites
run_test_suite "${SCRIPT_DIR}/test_pid_validation.sh" "PID Validation and Stale PID Cleanup"
run_test_suite "${SCRIPT_DIR}/test_multirun.sh" "Port Conflicts and Multi-Instance"
run_test_suite "${SCRIPT_DIR}/test_parsers.sh" "Parser Robustness"

# Summary
echo "=========================================="
echo "FINAL TEST SUMMARY"
echo "=========================================="
echo -e "Test Suites Run: ${TEST_SUITES}"
echo -e "${GREEN}Passed: ${TOTAL_PASSED}${NC}"
echo -e "${RED}Failed: ${TOTAL_FAILED}${NC}"
echo ""

if [ ${TOTAL_FAILED} -eq 0 ]; then
    echo -e "${GREEN}★ ALL TESTS PASSED ★${NC}"
    echo ""
    exit 0
else
    echo -e "${RED}Some test suites failed${NC}"
    echo ""
    exit 1
fi
