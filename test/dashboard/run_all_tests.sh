#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

python3 test/dashboard/test_lifecycle.py
python3 test/dashboard/test_starter_suid_identity.py

if command -v apptainer >/dev/null 2>&1; then
    CONTAINER_RUNTIME=apptainer
elif command -v singularity >/dev/null 2>&1; then
    CONTAINER_RUNTIME=singularity
else
    echo "Apptainer or Singularity is required for the output availability test." >&2
    exit 1
fi
"$CONTAINER_RUNTIME" exec tools/asvflow-dashboard.sif \
    python3 test/dashboard/test_output_availability.py
"$CONTAINER_RUNTIME" exec tools/asvflow-dashboard.sif \
    python3 test/dashboard/test_phylogeny.py
