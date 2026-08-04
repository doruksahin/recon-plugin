#!/usr/bin/env bash
# Isolated portability controls for generated Decree completion reports.
set -euo pipefail

ROOT="${RECON_PLUGIN:-$(cd "$(dirname "$0")/.." && pwd)}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/recon-decree-reports.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/decree/spec/reliability" "$TMP/decree/spec/reports"
printf '%s\n' '# source' >"$TMP/decree/spec/reliability/spec-01test-portable-report.md"
cat >"$TMP/decree/spec/reports/SPEC-01TEST.md" <<'REPORT'
# SPEC-01TEST Completion Report

**Document**: `/Users/example/private/repo/decree/spec/reliability/spec-01test-portable-report.md`
REPORT

if python3 "$ROOT/tools/render-decree-reports.py" --check --root "$TMP" >"$TMP/out" 2>&1; then
  echo "FAIL: absolute report identity passed" >&2
  exit 1
fi
grep -Fq 'absolute host path' "$TMP/out" || { cat "$TMP/out" >&2; exit 1; }

python3 "$ROOT/tools/render-decree-reports.py" --normalize-only --root "$TMP" >/dev/null
python3 "$ROOT/tools/render-decree-reports.py" --check --root "$TMP" >/dev/null
grep -Fq '**Document**: `decree/spec/reliability/spec-01test-portable-report.md`' "$TMP/decree/spec/reports/SPEC-01TEST.md"

echo 'decree report portability controls: clean'
