#!/bin/bash
# Prove that the commit rail rejects invalid staged content without changing the
# caller's index or worktree.
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)" || exit 2
cd "$ROOT"

TEMP_INDEX="$(mktemp -t recon-pre-commit-index)"
trap 'rm -f "$TEMP_INDEX" "$TEMP_INDEX.lock"' EXIT

cp "$(git rev-parse --git-path index)" "$TEMP_INDEX"
BAD_BLOB="$(printf 'trailing whitespace \n' | git hash-object -w --stdin)"
GIT_INDEX_FILE="$TEMP_INDEX" git update-index --add --cacheinfo \
  "100644,$BAD_BLOB,.pre-commit-guardrail-whitespace"

set +e
OUTPUT="$(GIT_INDEX_FILE="$TEMP_INDEX" bash tools/pre-commit-check.sh 2>&1)"
STATUS=$?
set -e

if [ "$STATUS" -ne 1 ]; then
  printf 'pre-commit guardrail test: expected staged-whitespace rejection (exit 1), got %s\n' "$STATUS" >&2
  printf '%s\n' "$OUTPUT" >&2
  exit 1
fi

if [[ "$OUTPUT" != *".pre-commit-guardrail-whitespace"* ]]; then
  printf 'pre-commit guardrail test: staged whitespace was not reported\n' >&2
  printf '%s\n' "$OUTPUT" >&2
  exit 1
fi

printf 'pre-commit guardrail test: PASS\n'
