#!/usr/bin/env bash
# Validate FastTree's Newick structure and ensure its leaf IDs match the alignment.
set -euo pipefail
tree_file=$1
alignment_file=$2
tree_ids=$(mktemp)
alignment_ids=$(mktemp)
trap 'rm -f "$tree_ids" "$alignment_ids"' EXIT

awk '
  NR != 1 { exit 1 }
  {
    if ($0 !~ /;$/ || $0 ~ /\(,|,,|,\)|\(\)/) exit 1
    for (i = 1; i < length($0); i++) {
      char = substr($0, i, 1)
      if (char == "(") { balance++; opens++ }
      if (char == ")") { balance--; if (balance < 0) exit 1 }
      if (char == ",") commas++
    }
  }
  END { if (balance != 0 || opens == 0 || commas == 0) exit 1 }
' "$tree_file" || { echo 'FastTree produced invalid Newick' >&2; exit 1; }

grep -oE 'ASV_[A-Za-z0-9_.-]+' "$tree_file" | sort -u > "$tree_ids"
grep '^>' "$alignment_file" | sed 's/^>//; s/[[:space:]].*//' | sort -u > "$alignment_ids"
diff -u "$alignment_ids" "$tree_ids" || {
  echo 'Newick leaf identifiers do not match aligned ASV identifiers' >&2
  exit 1
}
