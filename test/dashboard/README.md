# ASVFlow Live Dashboard - Test Suite

## Overview

Automated test suite for Phase 1.1 reliability and accuracy improvements. Tests verify PID validation, process identity checking, multi-instance isolation, and parser robustness.

## Requirements

- Bash 4.0+
- Python 3.9+
- Linux 5.1+ with `/proc` mounted (pidfd support is required for safe signaling)
- `setsid`, GNU `stat`, and `curl`; `ss` or `lsof` is recommended for port checks
- Singularity/Apptainer
- Dashboard container built: `tools/asvflow-dashboard.sif`

## Running Tests

### All Tests
```bash
cd test/dashboard
./run_all_tests.sh
```

### Individual Test Suites
```bash
# PID validation and stale PID cleanup
./test_pid_validation.sh

# Port conflicts and multiple instances
./test_multirun.sh

# Parser robustness with edge cases
./test_parsers.sh
```

## Test Coverage

### 1. PID Validation (test_pid_validation.sh)

**Tests:**
- Stale PID cleanup (process no longer exists)
- PID reuse detection (PID exists but is wrong process)
- Valid dashboard detection (already running)
- Stop script refuses to kill unrelated processes
- Singularity process tree verification

**What's Tested:**
- Process identity verification using process name
- Singularity starter-suid detection
- Streamlit child process verification
- Protection against killing unrelated processes

### 2. Multi-Instance Support (test_multirun.sh)

**Tests:**
- Port conflict automatic resolution
- Multiple independent dashboard instances
- Dashboard isolation by output directory
- Independent shutdown (stopping one doesn't affect others)

**What's Tested:**
- Port range 8501-8520 conflict handling
- 3 simultaneous dashboards with unique PIDs
- Output directory-specific PID files
- Isolated lifecycle management

### 3. Parser Robustness (test_parsers.sh)

**Tests:**
- Missing execution_trace.txt file
- Empty trace file
- Valid trace file with task summary
- Removal of 'running' field from Phase 1

**What's Tested:**
- Graceful handling of missing files
- Empty DataFrame for missing/empty files
- Correct task counting (completed, cached, failed)
- Phase 1.1 accuracy: no false "running" tasks

## Test Results Format

Each test suite reports:
- Individual test pass/fail status
- Summary with pass/fail counts
- Exit code 0 on success, 1 on failure

Example output:
```
==========================================
Test Summary
==========================================
Passed: 7
Failed: 0

All PID validation tests passed!
```

## Cleanup

Tests automatically clean up temporary files on exit. If interrupted, manually remove:
```bash
rm -rf /tmp/dashboard_test_*
rm -rf /tmp/dashboard_multirun_*
rm -rf /tmp/dashboard_parser_test_*
```

## Adding New Tests

1. Create test script in `test/dashboard/`
2. Follow naming convention: `test_<feature>.sh`
3. Use color-coded log functions
4. Include cleanup trap
5. Return proper exit codes
6. Add to `run_all_tests.sh`

## Known Limitations

- Tests require dashboard container to be built
- Some tests may fail if ports 8501-8520 are in use
- Parser tests use lightweight fixtures (no full pipeline needed)
- Process identity checks support both Apptainer and Singularity process names
