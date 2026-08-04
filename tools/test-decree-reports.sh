#!/usr/bin/env bash
# Isolated complete-drift controls for generated Decree completion reports.
set -euo pipefail

ROOT="${RECON_PLUGIN:-$(cd "$(dirname "$0")/.." && pwd)}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/recon-decree-reports.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
clean_git() {
  env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_PREFIX \
    -u GIT_COMMON_DIR -u GIT_OBJECT_DIRECTORY -u GIT_ALTERNATE_OBJECT_DIRECTORIES \
    git "$@"
}

cp "$ROOT/decree.toml" "$TMP/decree.toml"
mkdir -p "$TMP/decree/spec/reliability" "$TMP/decree/spec/reports"
cat >"$TMP/decree/spec/reliability/spec-01kz0000000000000000000000-portable-report.md" <<'SPEC'
---
date: '2026-08-05'
governs: []
id: SPEC-01KZ0000000000000000000000
references: []
status: implemented
---

# SPEC-01KZ0000000000000000000000 Portable Report

## Overview

Exercise complete generated-report drift checking.

## Technical Design

Generate one deterministic completion report.

## Testing Strategy

Mutate one report field at a time.

## Acceptance Criteria

- [x] Original acceptance body is retained.
SPEC
printf '%s\n' 'tracked placeholder' >"$TMP/decree/spec/reports/SPEC-01KZ0000000000000000000000.md"
clean_git -C "$TMP" init -q
clean_git -C "$TMP" add decree.toml decree

python3 "$ROOT/tools/render-decree-reports.py" --root "$TMP" >/dev/null
REPORT="$TMP/decree/spec/reports/SPEC-01KZ0000000000000000000000.md"
cp "$REPORT" "$TMP/clean-report.md"
CHECKSUM_BEFORE="$(shasum -a 256 "$REPORT")"
python3 "$ROOT/tools/render-decree-reports.py" --check --root "$TMP" >/dev/null
[ "$(shasum -a 256 "$REPORT")" = "$CHECKSUM_BEFORE" ] || { echo "FAIL: --check mutated the tracked report" >&2; exit 1; }

perl -0pi -e 's/^\*\*Generated\*\*: .*$/\*\*Generated\*\*: 1999-01-01T00:00:00Z/m' "$REPORT"
python3 "$ROOT/tools/render-decree-reports.py" --check --root "$TMP" >/dev/null
cp "$TMP/clean-report.md" "$REPORT"

perl -0pi -e 's/Original acceptance body is retained/Mutated acceptance body/' "$REPORT"
if python3 "$ROOT/tools/render-decree-reports.py" --check --root "$TMP" >"$TMP/body.out" 2>&1; then
  echo "FAIL: body-only report mutation passed" >&2
  exit 1
fi
grep -Fq 'complete report content drift' "$TMP/body.out" || { cat "$TMP/body.out" >&2; exit 1; }
cp "$TMP/clean-report.md" "$REPORT"

perl -0pi -e 's#\*\*Document\*\*: `[^`]+`#**Document**: `/Users/example/private/repo/decree/spec/reliability/spec-01kz0000000000000000000000-portable-report.md`#' "$REPORT"
if python3 "$ROOT/tools/render-decree-reports.py" --check --root "$TMP" >"$TMP/document.out" 2>&1; then
  echo "FAIL: Document-path report mutation passed" >&2
  exit 1
fi
grep -Fq 'absolute host path' "$TMP/document.out" || { cat "$TMP/document.out" >&2; exit 1; }
cp "$TMP/clean-report.md" "$REPORT"

rm "$REPORT"
if python3 "$ROOT/tools/render-decree-reports.py" --check --root "$TMP" >"$TMP/missing.out" 2>&1; then
  echo "FAIL: missing expected report passed" >&2
  exit 1
fi
grep -Fq 'missing expected report' "$TMP/missing.out" || { cat "$TMP/missing.out" >&2; exit 1; }
cp "$TMP/clean-report.md" "$REPORT"

cp "$TMP/clean-report.md" "$TMP/decree/spec/reports/SPEC-EXTRA.md"
if python3 "$ROOT/tools/render-decree-reports.py" --check --root "$TMP" >"$TMP/extra.out" 2>&1; then
  echo "FAIL: extra report passed" >&2
  exit 1
fi
grep -Fq 'extra report' "$TMP/extra.out" || { cat "$TMP/extra.out" >&2; exit 1; }
rm "$TMP/decree/spec/reports/SPEC-EXTRA.md"

python3 "$ROOT/tools/render-decree-reports.py" --root "$TMP" >/dev/null
perl -0pi -e 's/^\*\*Generated\*\*: .*$/\*\*Generated\*\*: <volatile>/m' "$REPORT" "$TMP/clean-report.md"
cmp "$TMP/clean-report.md" "$REPORT"

echo 'decree report controls: clean — body, Document, missing, and extra drift rejected; timestamp-only drift accepted'
