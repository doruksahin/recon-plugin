#!/usr/bin/env bash
# Isolated complete-drift controls for generated Decree completion reports.
set -euo pipefail

ROOT="${RECON_PLUGIN:-$(cd "$(dirname "$0")/.." && pwd)}"
RENDER="$ROOT/tools/render-decree-reports.py"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/recon-decree-reports.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
[ -x "$RENDER" ] || { echo "FAIL: report owner is not executable" >&2; exit 1; }
[ -x "$ROOT/tools/test-decree-reports.sh" ] || { echo "FAIL: report control is not executable" >&2; exit 1; }
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

"$RENDER" --root "$TMP" >/dev/null
REPORT="$TMP/decree/spec/reports/SPEC-01KZ0000000000000000000000.md"
cp "$REPORT" "$TMP/clean-report.md"
CHECKSUM_BEFORE="$(shasum -a 256 "$REPORT")"
"$RENDER" --check --root "$TMP" >/dev/null
[ "$(shasum -a 256 "$REPORT")" = "$CHECKSUM_BEFORE" ] || { echo "FAIL: --check mutated the tracked report" >&2; exit 1; }

perl -0pi -e 's/^\*\*Generated\*\*: .*$/\*\*Generated\*\*: 1999-01-01T00:00:00Z/m' "$REPORT"
"$RENDER" --check --root "$TMP" >/dev/null
cp "$TMP/clean-report.md" "$REPORT"

perl -0pi -e 's/^(\*\*Transitioned to `[^`]+` on\*\*: )\d{4}-\d{2}-\d{2}$/${1}1999-01-01/m' "$REPORT"
if "$RENDER" --check --root "$TMP" >"$TMP/transition.out" 2>&1; then
  echo "FAIL: transition-date-only report mutation passed" >&2
  exit 1
fi
grep -Fq 'transition identity' "$TMP/transition.out" || { cat "$TMP/transition.out" >&2; exit 1; }
cp "$TMP/clean-report.md" "$REPORT"

perl -0pi -e 's/Original acceptance body is retained/Mutated acceptance body/' "$REPORT"
if "$RENDER" --check --root "$TMP" >"$TMP/body.out" 2>&1; then
  echo "FAIL: body-only report mutation passed" >&2
  exit 1
fi
grep -Fq 'complete report content drift' "$TMP/body.out" || { cat "$TMP/body.out" >&2; exit 1; }
cp "$TMP/clean-report.md" "$REPORT"

perl -0pi -e 's#\*\*Document\*\*: `[^`]+`#**Document**: `/Users/example/private/repo/decree/spec/reliability/spec-01kz0000000000000000000000-portable-report.md`#' "$REPORT"
if "$RENDER" --check --root "$TMP" >"$TMP/document.out" 2>&1; then
  echo "FAIL: Document-path report mutation passed" >&2
  exit 1
fi
grep -Fq 'absolute host path' "$TMP/document.out" || { cat "$TMP/document.out" >&2; exit 1; }
cp "$TMP/clean-report.md" "$REPORT"

rm "$REPORT"
if "$RENDER" --check --root "$TMP" >"$TMP/missing.out" 2>&1; then
  echo "FAIL: missing expected report passed" >&2
  exit 1
fi
grep -Fq 'missing expected report' "$TMP/missing.out" || { cat "$TMP/missing.out" >&2; exit 1; }
cp "$TMP/clean-report.md" "$REPORT"

cp "$TMP/clean-report.md" "$TMP/decree/spec/reports/SPEC-EXTRA.md"
if "$RENDER" --check --root "$TMP" >"$TMP/extra.out" 2>&1; then
  echo "FAIL: extra report passed" >&2
  exit 1
fi
grep -Fq 'extra report' "$TMP/extra.out" || { cat "$TMP/extra.out" >&2; exit 1; }
rm "$TMP/decree/spec/reports/SPEC-EXTRA.md"

mkdir "$TMP/temp-parent"
TEMP_PARENT_BEFORE="$(find "$TMP/temp-parent" -mindepth 1 -maxdepth 1 -print | sort)"
mv "$TMP/decree.toml" "$TMP/decree.toml.saved"
if TMPDIR="$TMP/temp-parent" "$RENDER" --check --root "$TMP" >"$TMP/copy-failure.out" 2>&1; then
  echo "FAIL: missing decree.toml regeneration passed" >&2
  exit 1
fi
grep -Fq 'decree.toml' "$TMP/copy-failure.out" || { cat "$TMP/copy-failure.out" >&2; exit 1; }
TEMP_PARENT_AFTER="$(find "$TMP/temp-parent" -mindepth 1 -maxdepth 1 -print | sort)"
if [ "$TEMP_PARENT_AFTER" != "$TEMP_PARENT_BEFORE" ]; then
  echo "FAIL: exceptional regeneration leaked an owned temporary project" >&2
  find "$TMP/temp-parent" -mindepth 1 -maxdepth 1 >&2
  exit 1
fi
mv "$TMP/decree.toml.saved" "$TMP/decree.toml"

"$RENDER" --root "$TMP" >/dev/null
perl -0pi -e 's/^\*\*Generated\*\*: .*$/\*\*Generated\*\*: <volatile>/m' "$REPORT" "$TMP/clean-report.md"
cmp "$TMP/clean-report.md" "$REPORT"

echo 'decree report controls: clean — transition, body, Document, missing, and extra drift rejected; timestamp-only drift accepted; exceptional temporary project cleaned'
