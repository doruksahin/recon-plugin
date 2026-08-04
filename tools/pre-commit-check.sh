#!/bin/bash
# Fail-closed local commit gate. Invoked only by .githooks/pre-commit.
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)" || { echo "pre-commit: not a git repository" >&2; exit 2; }
cd "$ROOT"

for command in python3 uv; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "pre-commit: required command is unavailable: $command" >&2
    exit 2
  }
done

if [ -n "$(git ls-files -u)" ]; then
  echo "pre-commit: unresolved index conflicts" >&2
  exit 1
fi

echo "[1/4] staged diff integrity"
if ! STAGED_DIFF_ERRORS="$(git diff --cached --check 2>&1)"; then
  printf '%s\n' "$STAGED_DIFF_ERRORS" >&2
  exit 1
fi

echo "[2/4] local links"
bash tools/check-links.sh

echo "[3/4] repository coherence and universal controls"
bash tools/check-coherence.sh

echo "[4/4] Decree document integrity"
uv run decree lint

echo "pre-commit: PASS — staged diff and repository guardrails are clean"
