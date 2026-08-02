#!/bin/bash
# Isolated fixtures for the model-authored repro and Discovery package rails.
# No network, Jira credentials, repository writes, or user interaction.
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
REPRO_VERIFY="$ROOT/recon/scripts/verify-repro.sh"
DISCOVERY_VERIFY="$ROOT/recon/scripts/verify-discovery.sh"
ROUTE_GENERIC="$ROOT/recon/scripts/route-generic.sh"
DERIVE_STATE="$ROOT/recon/scripts/derive-state.sh"
BASE_TMP="${TMPDIR:-/tmp}"
BASE_TMP="${BASE_TMP%/}"
FIXTURE="$(mktemp -d "$BASE_TMP/recon-artifact-verifiers.XXXXXX")"
TICKET="TEST-1"
RUN_STARTED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
TODAY="$(date -u +%Y-%m-%d)"
FIXTURE_COMMIT="0123456789abcdef0123456789abcdef01234567"
PASS_COUNT=0

cleanup() {
  case "$FIXTURE" in
    "$BASE_TMP"/recon-artifact-verifiers.*) rm -rf "$FIXTURE" ;;
    *) echo "refusing to remove unexpected fixture path: $FIXTURE" >&2 ;;
  esac
}
trap cleanup EXIT

fail() { echo "artifact verifiers: FAIL — $1" >&2; exit 1; }

new_workspace() {
  local name="$1"
  CASE_ROOT="$FIXTURE/$name"
  CASE_WS="$CASE_ROOT/$TICKET"
  mkdir -p "$CASE_WS"
  printf 'skill: recon-triage\nplugin_version: test\nstarted: %s\nticket: %s\n' \
    "$RUN_STARTED" "$TICKET" >"$CASE_WS/meta.yaml"
}

make_png() {
  local path="$1"
  mkdir -p "$(dirname "$path")"
  python3 - "$path" <<'PY'
import struct
import sys
import zlib
from pathlib import Path


def chunk(kind, payload):
    return (struct.pack(">I", len(payload)) + kind + payload
            + struct.pack(">I", zlib.crc32(kind + payload) & 0xffffffff))


png = b"\x89PNG\r\n\x1a\n"
png += chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 6, 0, 0, 0))
png += chunk(b"IDAT", zlib.compress(b"\x00\x00\x00\x00\xff"))
png += chunk(b"IEND", b"")
Path(sys.argv[1]).write_bytes(png)
PY
}

make_bad_idat_png() {
  local path="$1"
  mkdir -p "$(dirname "$path")"
  python3 - "$path" <<'PY'
import struct
import sys
import zlib
from pathlib import Path


def chunk(kind, payload):
    return (struct.pack(">I", len(payload)) + kind + payload
            + struct.pack(">I", zlib.crc32(kind + payload) & 0xffffffff))


png = b"\x89PNG\r\n\x1a\n"
png += chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 6, 0, 0, 0))
png += chunk(b"IDAT", b"not-a-zlib-stream")
png += chunk(b"IEND", b"")
Path(sys.argv[1]).write_bytes(png)
PY
}

make_nonconsecutive_idat_png() {
  local path="$1"
  mkdir -p "$(dirname "$path")"
  python3 - "$path" <<'PY'
import struct
import sys
import zlib
from pathlib import Path


def chunk(kind, payload):
    return (struct.pack(">I", len(payload)) + kind + payload
            + struct.pack(">I", zlib.crc32(kind + payload) & 0xffffffff))


compressed = zlib.compress(b"\x00\x00\x00\x00\xff")
split = len(compressed) // 2
png = b"\x89PNG\r\n\x1a\n"
png += chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 6, 0, 0, 0))
png += chunk(b"IDAT", compressed[:split])
png += chunk(b"tEXt", b"gap\x00between-idat")
png += chunk(b"IDAT", compressed[split:])
png += chunk(b"IEND", b"")
Path(sys.argv[1]).write_bytes(png)
PY
}

write_success_repro() {
  local ws="$1"
  mkdir -p "$ws/repro/exhibits"
  printf '%s\n' \
    '---' \
    'recon: repro' \
    "ticket: $TICKET" \
    'reproduced: true' \
    'start_state: npm run dev, /collections, Collection3 is visible' \
    'failure_reason: ""' \
    '---' \
    '' \
    "# Repro — $TICKET: hidden collection" \
    '' \
    '1. Open Collections → Collection3 is visible. [exhibits/1-baseline.png]' \
    '2. Click the eye icon → Collection3 is hidden. [exhibits/2-result.png]' \
    '' \
    '## The question (concrete form)' \
    'Should the hidden collection remain absent after step 2?' \
    >"$ws/repro/repro.md"
  make_png "$ws/repro/exhibits/1-baseline.png"
  make_png "$ws/repro/exhibits/2-result.png"
}

write_failed_repro() {
  local ws="$1"
  mkdir -p "$ws/repro"
  printf '%s\n' \
    '---' \
    'recon: repro' \
    "ticket: $TICKET" \
    'reproduced: false' \
    'start_state: npm run dev, /collections, mock mode' \
    'failure_reason: mock mode has no Collection3 fixture' \
    '---' \
    '' \
    "# Repro — $TICKET: hidden collection" \
    '' \
    'The required entity is absent, so no success sequence was captured.' \
    >"$ws/repro/repro.md"
}

write_contract_all() {
  local ws="$1"
  mkdir -p "$ws/discovery"
  printf '%s\n' \
    "# Discovery — $TICKET" \
    '' \
    '## REQ-1 — hide a collection' \
    'Scenario: Hide a visible collection' \
    'Given Collection3 is visible on the Collections page' \
    'When the user clicks its eye icon' \
    'Then Collection3 is absent from the visible list' \
    '' \
    '## REG-1 — preserve another collection' \
    'Scenario: Keep unrelated collections visible' \
    'Given Collection2 is visible' \
    'When Collection3 is hidden' \
    'Then Collection2 remains visible' \
    '' \
    '## OPEN-1 — selected hidden collection' \
    'Scenario: Hide the selected collection' \
    'Given Collection3 is selected' \
    'When the user hides Collection3' \
    'Then the selected tab follows the approved visible outcome' \
    '' \
    '- A: select Collection2' \
    '- B: show no selected tab' \
    >"$ws/discovery/discovery.md"
}

write_contract_simple() {
  local ws="$1"
  mkdir -p "$ws/discovery"
  printf '%s\n' \
    "# Discovery — $TICKET" \
    '' \
    '## REQ-1 — hide a collection' \
    'Scenario: Hide a visible collection' \
    'Given Collection3 is visible' \
    'When the user clicks its eye icon' \
    'Then Collection3 is absent from the visible list' \
    >"$ws/discovery/discovery.md"
}

write_contract_none() {
  local ws="$1"
  mkdir -p "$ws/discovery"
  printf '%s\n' \
    "# Discovery — $TICKET" \
    '' \
    'No scenarios: the requested copy correction has no behavior change.' \
    >"$ws/discovery/discovery.md"
}

write_route() {
  local ws="$1" route="$2" brief_kind="$3"
  mkdir -p "$ws/route"
  printf '%s\n' \
    'routing:' \
    "  route: $route" \
    '  matched_rule: fixture' \
    '  governance: none' \
    '  governance_source: fixture' \
    "  brief_kind: $brief_kind" \
    '  evidence:' \
    "    repo_commit: $FIXTURE_COMMIT" \
    '  rules_not_matched:' \
    '    fixture-other: fixture route excluded' \
    '  handoff: |' \
    "    → continue from $TICKET in a new implementation session" \
    >"$ws/route/routing.yaml"
}

write_decree_route() {
  local ws="$1"
  mkdir -p "$ws/route"
  printf '%s\n' \
    'routing:' \
    '  route: new-spec' \
    '  matched_rule: 2' \
    '  governance: decree' \
    '  governance_source: repository probe confirmed by developer' \
    '  target: null' \
    '  ddd_entry: phase 3' \
    '  brief_kind: implementation-brief' \
    '  target_governs:' \
    '    - src/collections.ts' \
    '  evidence:' \
    '    intent_check: no active governing document' \
    '    task_class: defect' \
    '    product_decision_open: false' \
    '    reuses_existing_contract: src/collections.ts:40' \
    '    blast_radius: 1 change file + 1 test file' \
    "    repo_commit: $FIXTURE_COMMIT" \
    '  rules_not_matched:' \
    '    rule_0: behavior contract exists' \
    '    rule_1: no governing specification exists' \
    '  handoff: |' \
    "    → create a SPEC for $TICKET from the implementation brief" \
    >"$ws/route/routing.yaml"
}

write_impl_brief() {
  local ws="$1" shape="$2"
  {
    printf '%s\n' \
      "# Implementation brief — $TICKET" \
      '' \
      'Ticket: https://example.invalid/browse/TEST-1' \
      '' \
      '## Overview' \
      'Hide the selected collection without disturbing unrelated rows.' \
      '' \
      '## Acceptance criteria' \
      '- [ ] REQ-1 — a hidden collection leaves the visible list.'
    case "$shape" in
      all | no-manual)
        printf '%s\n' \
          '- [ ] REG-1 — unrelated collections remain visible.' \
          '- [ ] OPEN-1 — apply the approved selected-tab outcome.'
        ;;
      drift)
        printf '%s\n' '- [ ] OPEN-1 — apply the approved selected-tab outcome.'
        ;;
      simple) ;;
      *) fail "unknown implementation brief fixture shape: $shape" ;;
    esac
    printf '%s\n' \
      '' \
      '## Technical design' \
      'Reuse the existing visibility transition in the owning service.' \
      '' \
      '## Integration guardrails' \
      'Keep Collection2 rendering and selection unchanged.' \
      ''
    if [ "$shape" != "no-manual" ]; then
      printf '%s\n' \
        '## Manual verification' \
        'Start state: npm run dev, /collections, Collection3 visible.' \
        '1. Hide Collection3 and confirm the BEFORE state changes to AFTER.'
    fi
  } >"$ws/discovery/spec-draft.md"
}

write_impl_brief_from_repro() {
  local ws="$1"
  write_impl_brief "$ws" simple
  sed '/^## Manual verification/,$d' "$ws/discovery/spec-draft.md" \
    >"$ws/discovery/spec.tmp"
  mv "$ws/discovery/spec.tmp" "$ws/discovery/spec-draft.md"
  printf '%s\n' \
    '## Manual verification' \
    'Start state: npm run dev, /collections, Collection3 is visible' \
    '1. Open Collections → Collection3 is visible. [exhibits/1-baseline.png]' \
    '2. Click the eye icon → Collection3 is hidden. [exhibits/2-result.png]' \
    'BEFORE: Collection3 is visible.' \
    'AFTER: Collection3 is hidden.' \
    >>"$ws/discovery/spec-draft.md"
}

copy_open_resolution_to_brief() {
  local ws="$1"
  sed 's/^- \[ \] OPEN-1 .*/- [ ] OPEN-1 — A — Collection2 becomes selected/' \
    "$ws/discovery/spec-draft.md" >"$ws/discovery/spec.tmp"
  mv "$ws/discovery/spec.tmp" "$ws/discovery/spec-draft.md"
}

copy_open_resolution_to_problem() {
  local ws="$1"
  sed 's/^- OPEN-1 .*/- OPEN-1 — A — Collection2 becomes selected/' \
    "$ws/discovery/spec-draft.md" >"$ws/discovery/spec.tmp"
  mv "$ws/discovery/spec.tmp" "$ws/discovery/spec-draft.md"
}

write_problem_statement() {
  local ws="$1"
  printf '%s\n' \
    "# Problem statement — $TICKET" \
    '' \
    '## Context' \
    'Collection visibility and selection currently overlap.' \
    '' \
    '## Current behavior' \
    'REQ-1: hiding the collection can leave a stale tab.' \
    '' \
    '## Desired outcome' \
    'The visible UI always has a user-understandable selected state.' \
    '' \
    '## Open choices' \
    'Choose whether another collection or no tab becomes selected.' \
    >"$ws/discovery/spec-draft.md"
}

write_problem_statement_all() {
  local ws="$1"
  printf '%s\n' \
    "# Problem statement — $TICKET" \
    '' \
    '## Context' \
    'Collection visibility and selection currently overlap.' \
    '' \
    '## Current behavior' \
    'REQ-1 — hiding the collection can leave a stale tab.' \
    '' \
    '## Desired outcome' \
    'REG-1 — unrelated collections remain visible.' \
    '' \
    '## Open choices' \
    '- OPEN-1 — the selected-tab outcome awaits approval.' \
    >"$ws/discovery/spec-draft.md"
}

write_gate() {
  local ws="$1" shape="$2"
  case "$shape" in
    approved-open)
      printf '%s\n' \
        'gate:' \
        '  approved: true' \
        "  date: $TODAY" \
        '  open_scenario_resolutions:' \
        '    OPEN-1: "A — Collection2 becomes selected"' \
        >"$ws/discovery/gate.yaml"
      ;;
    rejected-open)
      printf '%s\n' \
        'gate:' \
        '  approved: false' \
        "  date: $TODAY" \
        '  open_scenario_resolutions:' \
        '    OPEN-1: "B — no tab remains selected"' \
        '  rejected: confirm the desired tab behavior with Product' \
        >"$ws/discovery/gate.yaml"
      ;;
    approved-none)
      printf '%s\n' \
        'gate:' \
        '  approved: true' \
        "  date: $TODAY" \
        '  open_scenario_resolutions: {}' \
        >"$ws/discovery/gate.yaml"
      ;;
    missing-open)
      printf '%s\n' \
        'gate:' \
        '  approved: true' \
        "  date: $TODAY" \
        '  open_scenario_resolutions: {}' \
        >"$ws/discovery/gate.yaml"
      ;;
    *) fail "unknown gate fixture shape: $shape" ;;
  esac
}

expect_pass() {
  local name="$1"
  shift
  if ! "$@" >"$FIXTURE/result.out" 2>&1; then
    sed 's/^/  /' "$FIXTURE/result.out" >&2
    fail "$name unexpectedly failed"
  fi
  PASS_COUNT=$((PASS_COUNT + 1))
}

expect_violation() {
  local name="$1" expected="$2" rc
  shift 2
  set +e
  "$@" >"$FIXTURE/result.out" 2>&1
  rc=$?
  set -e
  if [ "$rc" -ne 1 ]; then
    sed 's/^/  /' "$FIXTURE/result.out" >&2
    fail "$name expected exit 1, got $rc"
  fi
  if ! grep -Fq -- "$expected" "$FIXTURE/result.out"; then
    sed 's/^/  /' "$FIXTURE/result.out" >&2
    fail "$name returned the wrong violation (missing '$expected')"
  fi
  PASS_COUNT=$((PASS_COUNT + 1))
}

expect_exit_code() {
  local name="$1" expected="$2" expected_rc="$3" rc
  shift 3
  set +e
  "$@" >"$FIXTURE/result.out" 2>&1
  rc=$?
  set -e
  if [ "$rc" -ne "$expected_rc" ]; then
    sed 's/^/  /' "$FIXTURE/result.out" >&2
    fail "$name expected exit $expected_rc, got $rc"
  fi
  if ! grep -Fq -- "$expected" "$FIXTURE/result.out"; then
    sed 's/^/  /' "$FIXTURE/result.out" >&2
    fail "$name returned the wrong diagnostic (missing '$expected')"
  fi
  PASS_COUNT=$((PASS_COUNT + 1))
}

# Repro: valid success and valid honest failure.
new_workspace repro-success
write_success_repro "$CASE_WS"
expect_pass "successful repro" env RECON_ROOT="$CASE_ROOT" bash "$REPRO_VERIFY" "$TICKET"

new_workspace repro-honest-failure
write_failed_repro "$CASE_WS"
expect_pass "honest failed repro" env RECON_ROOT="$CASE_ROOT" bash "$REPRO_VERIFY" "$TICKET"

# Repro: non-contiguous steps, corrupt/stale/orphan exhibits, and fabricated
# evidence on a failure all stop at the verifier.
new_workspace repro-gap
write_success_repro "$CASE_WS"
sed 's/^2\. /3. /' "$CASE_WS/repro/repro.md" >"$CASE_WS/repro/repro.tmp"
mv "$CASE_WS/repro/repro.tmp" "$CASE_WS/repro/repro.md"
expect_violation "non-contiguous repro" "repro steps must be contiguous 1..n in order" \
  env RECON_ROOT="$CASE_ROOT" bash "$REPRO_VERIFY" "$TICKET"

new_workspace repro-corrupt
write_success_repro "$CASE_WS"
printf 'not a png\n' >"$CASE_WS/repro/exhibits/2-result.png"
expect_violation "corrupt PNG" "invalid PNG signature" \
  env RECON_ROOT="$CASE_ROOT" bash "$REPRO_VERIFY" "$TICKET"

new_workspace repro-truncated-chunk
write_success_repro "$CASE_WS"
python3 - "$CASE_WS/repro/exhibits/2-result.png" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
path.write_bytes(path.read_bytes()[:20])
PY
expect_violation "truncated PNG chunk" "truncated IHDR chunk" \
  env RECON_ROOT="$CASE_ROOT" bash "$REPRO_VERIFY" "$TICKET"

new_workspace repro-truncated-chunk-header
write_success_repro "$CASE_WS"
python3 - "$CASE_WS/repro/exhibits/2-result.png" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
path.write_bytes(path.read_bytes()[:10])
PY
expect_violation "truncated PNG chunk header" "truncated PNG chunk header/trailer" \
  env RECON_ROOT="$CASE_ROOT" bash "$REPRO_VERIFY" "$TICKET"

new_workspace repro-crc
write_success_repro "$CASE_WS"
python3 - "$CASE_WS/repro/exhibits/2-result.png" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = bytearray(path.read_bytes())
idat_type = data.index(b"IDAT")
data[idat_type + 4] ^= 1
path.write_bytes(data)
PY
expect_violation "PNG CRC mismatch" "IDAT chunk CRC mismatch" \
  env RECON_ROOT="$CASE_ROOT" bash "$REPRO_VERIFY" "$TICKET"

new_workspace repro-idat
write_success_repro "$CASE_WS"
make_bad_idat_png "$CASE_WS/repro/exhibits/2-result.png"
expect_violation "invalid IDAT zlib stream" "IDAT is not a valid zlib stream" \
  env RECON_ROOT="$CASE_ROOT" bash "$REPRO_VERIFY" "$TICKET"

new_workspace repro-idat-order
write_success_repro "$CASE_WS"
make_nonconsecutive_idat_png "$CASE_WS/repro/exhibits/2-result.png"
expect_violation "nonconsecutive IDAT chunks" "IDAT chunks must be consecutive" \
  env RECON_ROOT="$CASE_ROOT" bash "$REPRO_VERIFY" "$TICKET"

new_workspace repro-trailing-bytes
write_success_repro "$CASE_WS"
printf 'trailing\n' >>"$CASE_WS/repro/exhibits/2-result.png"
expect_violation "bytes after terminal IEND" "trailing bytes or chunks follow terminal IEND" \
  env RECON_ROOT="$CASE_ROOT" bash "$REPRO_VERIFY" "$TICKET"

new_workspace repro-zero-dimensions
write_success_repro "$CASE_WS"
python3 - "$CASE_WS/repro/exhibits/2-result.png" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = bytearray(path.read_bytes())
data[16:20] = b"\x00\x00\x00\x00"
path.write_bytes(data)
PY
expect_violation "zero PNG dimension" "PNG dimensions must both be positive" \
  env RECON_ROOT="$CASE_ROOT" bash "$REPRO_VERIFY" "$TICKET"

new_workspace repro-stale
write_success_repro "$CASE_WS"
touch -t 200001010000 "$CASE_WS/repro/exhibits/1-baseline.png"
expect_violation "stale exhibit" "mtime predates this run" \
  env RECON_ROOT="$CASE_ROOT" bash "$REPRO_VERIFY" "$TICKET"

new_workspace repro-missing
write_success_repro "$CASE_WS"
rm "$CASE_WS/repro/exhibits/2-result.png"
expect_violation "missing referenced exhibit" "missing referenced exhibits: exhibits/2-result.png" \
  env RECON_ROOT="$CASE_ROOT" bash "$REPRO_VERIFY" "$TICKET"

new_workspace repro-orphan
write_success_repro "$CASE_WS"
make_png "$CASE_WS/repro/exhibits/3-orphan.png"
expect_violation "orphan exhibit" \
  "orphan exhibits not referenced by numbered repro steps: exhibits/3-orphan.png" \
  env RECON_ROOT="$CASE_ROOT" bash "$REPRO_VERIFY" "$TICKET"

# A prose/question reference cannot turn an exhibit without a numbered action
# into valid evidence.
new_workspace repro-question-only-exhibit
write_success_repro "$CASE_WS"
make_png "$CASE_WS/repro/exhibits/3-question-only.png"
printf '\nQuestion context: [exhibits/3-question-only.png]\n' \
  >>"$CASE_WS/repro/repro.md"
expect_violation "question-only exhibit" \
  "exhibit reference outside a numbered step: 'exhibits/3-question-only.png'" \
  env RECON_ROOT="$CASE_ROOT" bash "$REPRO_VERIFY" "$TICKET"

# An exhibit token hidden in an HTML comment is not visible evidence for the
# numbered action, even though the referenced PNG remains in the inventory.
new_workspace repro-comment-hidden-exhibit
write_success_repro "$CASE_WS"
sed 's|\[exhibits/1-baseline.png\]|<!-- [exhibits/1-baseline.png] -->|' \
  "$CASE_WS/repro/repro.md" >"$CASE_WS/repro/repro.tmp"
mv "$CASE_WS/repro/repro.tmp" "$CASE_WS/repro/repro.md"
expect_violation "comment-hidden step exhibit" \
  "step 1 must reference exactly one exhibit (got 0)" \
  env RECON_ROOT="$CASE_ROOT" bash "$REPRO_VERIFY" "$TICKET"

new_workspace repro-unsafe-path
write_success_repro "$CASE_WS"
sed 's|exhibits/1-baseline.png|../exhibits/1-baseline.png|' \
  "$CASE_WS/repro/repro.md" >"$CASE_WS/repro/repro.tmp"
mv "$CASE_WS/repro/repro.tmp" "$CASE_WS/repro/repro.md"
expect_violation "unsafe exhibit path" "unsafe exhibit reference '../exhibits/1-baseline.png'" \
  env RECON_ROOT="$CASE_ROOT" bash "$REPRO_VERIFY" "$TICKET"

new_workspace repro-workspace-symlink
write_success_repro "$CASE_WS"
mv "$CASE_WS" "$CASE_ROOT/real-workspace"
ln -s "$CASE_ROOT/real-workspace" "$CASE_WS"
expect_violation "symlinked workspace" "ARTIFACT: workspace symlinks are forbidden" \
  env RECON_ROOT="$CASE_ROOT" bash "$REPRO_VERIFY" "$TICKET"

new_workspace repro-file-symlink
write_success_repro "$CASE_WS"
mv "$CASE_WS/repro/repro.md" "$CASE_ROOT/external-repro.md"
ln -s "$CASE_ROOT/external-repro.md" "$CASE_WS/repro/repro.md"
expect_violation "symlinked repro file" "repro/repro.md: symlinks are forbidden" \
  env RECON_ROOT="$CASE_ROOT" bash "$REPRO_VERIFY" "$TICKET"

new_workspace repro-exhibit-directory-symlink
write_success_repro "$CASE_WS"
mv "$CASE_WS/repro/exhibits" "$CASE_ROOT/external-exhibits"
ln -s "$CASE_ROOT/external-exhibits" "$CASE_WS/repro/exhibits"
expect_violation "symlinked exhibit directory" "repro/exhibits/: symlinks are forbidden" \
  env RECON_ROOT="$CASE_ROOT" bash "$REPRO_VERIFY" "$TICKET"

new_workspace discovery-stage-symlink
write_contract_simple "$CASE_WS"
write_route "$CASE_WS" brief implementation-brief
write_impl_brief "$CASE_WS" simple
mv "$CASE_WS/discovery" "$CASE_ROOT/external-discovery"
ln -s "$CASE_ROOT/external-discovery" "$CASE_WS/discovery"
expect_violation "symlinked Discovery stage" "discovery/: symlinks are forbidden" \
  env RECON_ROOT="$CASE_ROOT" bash "$DISCOVERY_VERIFY" "$TICKET" pre-gate

new_workspace repro-fabricated-failure
write_failed_repro "$CASE_WS"
make_png "$CASE_WS/repro/exhibits/1-invented.png"
expect_violation "failed repro with screenshot" \
  "failed repro must not contain success screenshots" \
  env RECON_ROOT="$CASE_ROOT" bash "$REPRO_VERIFY" "$TICKET"

new_workspace repro-unexpected-file
write_success_repro "$CASE_WS"
printf 'not an exhibit\n' >"$CASE_WS/repro/exhibits/notes.txt"
expect_violation "unexpected exhibit file" "unexpected non-PNG file in exhibits" \
  env RECON_ROOT="$CASE_ROOT" bash "$REPRO_VERIFY" "$TICKET"

# Discovery: a routine READY brief crosses both verification gates.
new_workspace discovery-ready
write_contract_simple "$CASE_WS"
write_route "$CASE_WS" brief implementation-brief
write_impl_brief "$CASE_WS" simple
expect_pass "READY pre-gate" env RECON_ROOT="$CASE_ROOT" bash "$DISCOVERY_VERIFY" "$TICKET" pre-gate
write_gate "$CASE_WS" approved-none
expect_pass "READY post-gate" env RECON_ROOT="$CASE_ROOT" bash "$DISCOVERY_VERIFY" "$TICKET" post-gate

# The stricter route envelope remains governance-neutral: the Decree adapter's
# documented optional fields and richer evidence mapping are valid inputs.
new_workspace discovery-decree-route
write_contract_simple "$CASE_WS"
write_decree_route "$CASE_WS"
write_impl_brief "$CASE_WS" simple
expect_pass "Decree route envelope" env RECON_ROOT="$CASE_ROOT" bash "$DISCOVERY_VERIFY" "$TICKET" pre-gate

# OPEN decisions retain the same key through contract, brief, and gate. Both an
# approved and a rejected complete record are valid terminal gate answers.
new_workspace discovery-open-approved
write_contract_all "$CASE_WS"
write_route "$CASE_WS" brief implementation-brief
write_impl_brief "$CASE_WS" all
write_gate "$CASE_WS" approved-open
copy_open_resolution_to_brief "$CASE_WS"
expect_pass "OPEN approved" env RECON_ROOT="$CASE_ROOT" bash "$DISCOVERY_VERIFY" "$TICKET" post-gate

new_workspace discovery-open-approved-wrong-entry
write_contract_all "$CASE_WS"
write_route "$CASE_WS" brief implementation-brief
write_impl_brief "$CASE_WS" all
sed 's/^- \[ \] REQ-1 .*/- [ ] REQ-1 — A — Collection2 becomes selected/' \
  "$CASE_WS/discovery/spec-draft.md" >"$CASE_WS/discovery/spec.tmp"
mv "$CASE_WS/discovery/spec.tmp" "$CASE_WS/discovery/spec-draft.md"
write_gate "$CASE_WS" approved-open
expect_violation "approved OPEN resolution on wrong checkbox" \
  "approved resolution for OPEN-1 is not copied verbatim into its same-ID brief entry" \
  env RECON_ROOT="$CASE_ROOT" bash "$DISCOVERY_VERIFY" "$TICKET" post-gate

new_workspace discovery-open-rejected
write_contract_all "$CASE_WS"
write_route "$CASE_WS" brief implementation-brief
write_impl_brief "$CASE_WS" all
write_gate "$CASE_WS" rejected-open
expect_pass "OPEN rejected" env RECON_ROOT="$CASE_ROOT" bash "$DISCOVERY_VERIFY" "$TICKET" post-gate

# No-scenario/direct packages have no brief, but still have a verified gate.
new_workspace discovery-no-scenario
write_contract_none "$CASE_WS"
write_route "$CASE_WS" direct none
mkdir -p "$CASE_WS/triage"
printf 'disposition: READY\n' >"$CASE_WS/triage/triage.yaml"
expect_pass "no-scenario no-brief pre-gate" env RECON_ROOT="$CASE_ROOT" bash "$DISCOVERY_VERIFY" "$TICKET" pre-gate
expect_pass "no-brief approval state" env RECON_ROOT="$CASE_ROOT" bash "$DERIVE_STATE" "$TICKET"
grep -Fq 'stop: approval-gate' "$CASE_WS/state/state.yaml" || fail "no-brief route did not reach approval gate"
grep -Fq 'node.brief: not-taken' "$CASE_WS/state/state.yaml" || fail "no-brief route marked brief as required"
write_gate "$CASE_WS" approved-none
expect_pass "no-scenario no-brief route" env RECON_ROOT="$CASE_ROOT" bash "$DISCOVERY_VERIFY" "$TICKET" post-gate
expect_pass "no-brief handed-off state" env RECON_ROOT="$CASE_ROOT" bash "$DERIVE_STATE" "$TICKET"
grep -Fq 'stop: handed-off' "$CASE_WS/state/state.yaml" || fail "no-brief route did not reach handed-off state"
grep -Fq 'node.handoff: done' "$CASE_WS/state/state.yaml" || fail "no-brief route did not complete handoff"

# Problem-statement routing uses its own required section set.
new_workspace discovery-problem
write_contract_simple "$CASE_WS"
write_route "$CASE_WS" prd-chain problem-statement
write_problem_statement "$CASE_WS"
expect_pass "problem statement" env RECON_ROOT="$CASE_ROOT" bash "$DISCOVERY_VERIFY" "$TICKET" pre-gate

new_workspace discovery-problem-id-missing
write_contract_all "$CASE_WS"
write_route "$CASE_WS" prd-chain problem-statement
write_problem_statement "$CASE_WS"
expect_violation "problem statement missing contract IDs" \
  "problem statement missing scenario IDs:" \
  env RECON_ROOT="$CASE_ROOT" bash "$DISCOVERY_VERIFY" "$TICKET" pre-gate

new_workspace discovery-problem-id-unknown
write_contract_simple "$CASE_WS"
write_route "$CASE_WS" prd-chain problem-statement
write_problem_statement "$CASE_WS"
printf '\nREG-99 — this scenario is not in discovery.md.\n' \
  >>"$CASE_WS/discovery/spec-draft.md"
expect_violation "problem statement unknown contract ID" \
  "problem statement has unknown scenario IDs: REG-99" \
  env RECON_ROOT="$CASE_ROOT" bash "$DISCOVERY_VERIFY" "$TICKET" pre-gate

new_workspace discovery-problem-approved
write_contract_all "$CASE_WS"
write_route "$CASE_WS" prd-chain problem-statement
write_problem_statement_all "$CASE_WS"
write_gate "$CASE_WS" approved-open
copy_open_resolution_to_problem "$CASE_WS"
expect_pass "problem statement binds approved OPEN resolution" env RECON_ROOT="$CASE_ROOT" bash "$DISCOVERY_VERIFY" "$TICKET" post-gate

new_workspace discovery-problem-approved-drift
write_contract_all "$CASE_WS"
write_route "$CASE_WS" prd-chain problem-statement
write_problem_statement_all "$CASE_WS"
sed 's/^REG-1 .*/REG-1 — A — Collection2 becomes selected/' \
  "$CASE_WS/discovery/spec-draft.md" >"$CASE_WS/discovery/spec.tmp"
mv "$CASE_WS/discovery/spec.tmp" "$CASE_WS/discovery/spec-draft.md"
write_gate "$CASE_WS" approved-open
expect_violation "problem statement approved OPEN resolution on wrong entry" \
  "approved resolution for OPEN-1 is not copied verbatim into its same-ID brief entry" \
  env RECON_ROOT="$CASE_ROOT" bash "$DISCOVERY_VERIFY" "$TICKET" post-gate

# IDs that exist only in comments or code are not implementation-facing
# entries. In particular, hidden approved text cannot bind an OPEN decision.
new_workspace discovery-problem-hidden-entries
write_contract_all "$CASE_WS"
write_route "$CASE_WS" prd-chain problem-statement
printf '%s\n' \
  "# Problem statement — $TICKET" \
  '' \
  '## Context' \
  'Collection visibility and selection overlap.' \
  '<!-- REQ-1 — hiding the collection can leave a stale tab. -->' \
  '' \
  '## Current behavior' \
  'The selected tab can point at a hidden collection.' \
  '' \
  '## Desired outcome' \
  '```markdown' \
  'REG-1 — unrelated collections remain visible.' \
  '```' \
  '' \
  '## Open choices' \
  'The selected-tab behavior requires a visible decision.' \
  '    OPEN-1 — A — Collection2 becomes selected' \
  >"$CASE_WS/discovery/spec-draft.md"
write_gate "$CASE_WS" approved-open
expect_violation "problem statement hidden scenario entries" \
  "problem statement missing scenario IDs: OPEN-1, REG-1, REQ-1" \
  env RECON_ROOT="$CASE_ROOT" bash "$DISCOVERY_VERIFY" "$TICKET" post-gate

# A brief that consumes repro evidence must copy the verified start state and
# step sequence, and must not predate the evidence it claims to consume.
new_workspace discovery-repro-sync
write_success_repro "$CASE_WS"
write_contract_simple "$CASE_WS"
write_route "$CASE_WS" brief implementation-brief
write_impl_brief_from_repro "$CASE_WS"
expect_pass "brief consumes verified repro" env RECON_ROOT="$CASE_ROOT" bash "$DISCOVERY_VERIFY" "$TICKET" pre-gate

new_workspace discovery-repro-step-drift
write_success_repro "$CASE_WS"
write_contract_simple "$CASE_WS"
write_route "$CASE_WS" brief implementation-brief
write_impl_brief_from_repro "$CASE_WS"
sed '/^2\. Click the eye icon/d' "$CASE_WS/discovery/spec-draft.md" \
  >"$CASE_WS/discovery/spec.tmp"
mv "$CASE_WS/discovery/spec.tmp" "$CASE_WS/discovery/spec-draft.md"
expect_violation "brief repro step drift" \
  "Manual verification does not copy verified repro step 2" \
  env RECON_ROOT="$CASE_ROOT" bash "$DISCOVERY_VERIFY" "$TICKET" pre-gate

new_workspace discovery-repro-order
write_success_repro "$CASE_WS"
write_contract_simple "$CASE_WS"
write_route "$CASE_WS" brief implementation-brief
write_impl_brief_from_repro "$CASE_WS"
touch -t 200001010000 "$CASE_WS/discovery/spec-draft.md"
expect_violation "brief predates repro evidence" \
  "spec-draft.md predates the repro evidence it claims to consume" \
  env RECON_ROOT="$CASE_ROOT" bash "$DISCOVERY_VERIFY" "$TICKET" pre-gate

# Discovery drift cases: missing checkbox, missing Manual verification, missing
# OPEN answer, and a forbidden brief on brief_kind none.
new_workspace discovery-checkbox-drift
write_contract_all "$CASE_WS"
write_route "$CASE_WS" brief implementation-brief
write_impl_brief "$CASE_WS" drift
expect_violation "scenario checkbox drift" \
  "acceptance criteria missing scenario IDs: REG-1" \
  env RECON_ROOT="$CASE_ROOT" bash "$DISCOVERY_VERIFY" "$TICKET" pre-gate

# A checkbox shown only as a fenced example does not satisfy the executable
# acceptance-criteria join. The rendered code still keeps the section non-empty.
new_workspace discovery-checkbox-fenced-code
write_contract_simple "$CASE_WS"
write_route "$CASE_WS" brief implementation-brief
printf '%s\n' \
  "# Implementation brief — $TICKET" \
  '' \
  '## Overview' \
  'Hide the selected collection.' \
  '' \
  '## Acceptance criteria' \
  '```markdown' \
  '- [ ] REQ-1 — example text is not an acceptance entry.' \
  '```' \
  '' \
  '## Technical design' \
  'Reuse the existing visibility transition.' \
  '' \
  '## Integration guardrails' \
  'Keep unrelated rows unchanged.' \
  '' \
  '## Manual verification' \
  'Start from the Collections page and hide Collection3.' \
  >"$CASE_WS/discovery/spec-draft.md"
expect_violation "fenced acceptance checkbox" \
  "acceptance criteria missing scenario IDs: REQ-1" \
  env RECON_ROOT="$CASE_ROOT" bash "$DISCOVERY_VERIFY" "$TICKET" pre-gate

new_workspace discovery-manual-missing
write_contract_all "$CASE_WS"
write_route "$CASE_WS" brief implementation-brief
write_impl_brief "$CASE_WS" no-manual
expect_violation "missing Manual verification" \
  "spec-draft.md missing required section 'Manual verification'" \
  env RECON_ROOT="$CASE_ROOT" bash "$DISCOVERY_VERIFY" "$TICKET" pre-gate

new_workspace discovery-open-drift
write_contract_all "$CASE_WS"
write_route "$CASE_WS" brief implementation-brief
write_impl_brief "$CASE_WS" all
write_gate "$CASE_WS" missing-open
expect_violation "missing OPEN gate key" "gate missing OPEN resolutions: OPEN-1" \
  env RECON_ROOT="$CASE_ROOT" bash "$DISCOVERY_VERIFY" "$TICKET" post-gate

new_workspace discovery-none-with-brief
write_contract_none "$CASE_WS"
write_route "$CASE_WS" direct none
write_impl_brief "$CASE_WS" simple
expect_violation "brief_kind none with brief" \
  "brief_kind none forbids discovery/spec-draft.md" \
  env RECON_ROOT="$CASE_ROOT" bash "$DISCOVERY_VERIFY" "$TICKET" pre-gate

new_workspace discovery-duplicate-id
write_contract_simple "$CASE_WS"
printf '%s\n' \
  '' \
  '## REQ-1 — duplicate' \
  'Scenario: Duplicate contract' \
  'Given the duplicate exists' \
  'When verification runs' \
  'Then the duplicate is rejected' \
  >>"$CASE_WS/discovery/discovery.md"
write_route "$CASE_WS" brief implementation-brief
write_impl_brief "$CASE_WS" simple
expect_violation "duplicate scenario ID" "duplicate scenario ID REQ-1" \
  env RECON_ROOT="$CASE_ROOT" bash "$DISCOVERY_VERIFY" "$TICKET" pre-gate

new_workspace discovery-missing-gherkin
write_contract_simple "$CASE_WS"
sed '/^Then /d' "$CASE_WS/discovery/discovery.md" >"$CASE_WS/discovery/discovery.tmp"
mv "$CASE_WS/discovery/discovery.tmp" "$CASE_WS/discovery/discovery.md"
write_route "$CASE_WS" brief implementation-brief
write_impl_brief "$CASE_WS" simple
expect_violation "missing Gherkin content" "REQ-1: missing Then content" \
  env RECON_ROOT="$CASE_ROOT" bash "$DISCOVERY_VERIFY" "$TICKET" pre-gate

new_workspace discovery-wrong-heading-level
write_contract_simple "$CASE_WS"
sed 's/^## REQ-1/### REQ-1/' "$CASE_WS/discovery/discovery.md" \
  >"$CASE_WS/discovery/discovery.tmp"
mv "$CASE_WS/discovery/discovery.tmp" "$CASE_WS/discovery/discovery.md"
write_route "$CASE_WS" brief implementation-brief
write_impl_brief "$CASE_WS" simple
expect_violation "scenario heading is not H2" "invalid scenario heading 'REQ-1'" \
  env RECON_ROOT="$CASE_ROOT" bash "$DISCOVERY_VERIFY" "$TICKET" pre-gate

# Hidden/example Markdown cannot create a contract scenario. A real visible
# heading may still own a rendered fenced Gherkin block.
new_workspace discovery-comment-hidden-scenario
mkdir -p "$CASE_WS/discovery"
printf '%s\n' \
  "# Discovery — $TICKET" \
  '<!--' \
  '## REQ-1 — hidden contract' \
  'Scenario: Hidden scenario' \
  'Given the content is commented out' \
  'When verification runs' \
  'Then it cannot enter the contract' \
  '-->' \
  >"$CASE_WS/discovery/discovery.md"
write_route "$CASE_WS" brief implementation-brief
write_impl_brief "$CASE_WS" simple
expect_violation "comment-hidden scenario" \
  "discovery.md without scenarios requires exactly one non-empty 'No scenarios:' declaration" \
  env RECON_ROOT="$CASE_ROOT" bash "$DISCOVERY_VERIFY" "$TICKET" pre-gate

new_workspace discovery-fenced-scenario-heading
mkdir -p "$CASE_WS/discovery"
printf '%s\n' \
  "# Discovery — $TICKET" \
  '```gherkin' \
  '## REQ-1 — example contract' \
  'Scenario: Example scenario' \
  'Given the heading is fenced' \
  'When verification runs' \
  'Then it cannot create a contract ID' \
  '```' \
  >"$CASE_WS/discovery/discovery.md"
write_route "$CASE_WS" brief implementation-brief
write_impl_brief "$CASE_WS" simple
expect_violation "fenced scenario heading" \
  "discovery.md has Scenario content without REQ-N/REG-N/OPEN-N headings" \
  env RECON_ROOT="$CASE_ROOT" bash "$DISCOVERY_VERIFY" "$TICKET" pre-gate

new_workspace discovery-visible-heading-fenced-gherkin
mkdir -p "$CASE_WS/discovery"
printf '%s\n' \
  "# Discovery — $TICKET" \
  '' \
  '## REQ-1 — visible contract' \
  '```gherkin' \
  'Scenario: Visible scenario' \
  'Given the contract heading is visible' \
  'When the Gherkin is rendered as code' \
  'Then the scenario remains valid' \
  '```' \
  >"$CASE_WS/discovery/discovery.md"
write_route "$CASE_WS" brief implementation-brief
write_impl_brief "$CASE_WS" simple
expect_pass "visible heading with fenced Gherkin" \
  env RECON_ROOT="$CASE_ROOT" bash "$DISCOVERY_VERIFY" "$TICKET" pre-gate

new_workspace discovery-fenced-no-scenarios
mkdir -p "$CASE_WS/discovery"
printf '%s\n' \
  "# Discovery — $TICKET" \
  '```markdown' \
  'No scenarios: this is example text, not a contract declaration.' \
  '```' \
  >"$CASE_WS/discovery/discovery.md"
write_route "$CASE_WS" direct none
expect_violation "fenced no-scenarios declaration" \
  "discovery.md without scenarios requires exactly one non-empty 'No scenarios:' declaration" \
  env RECON_ROOT="$CASE_ROOT" bash "$DISCOVERY_VERIFY" "$TICKET" pre-gate

new_workspace discovery-no-scenario-declaration-missing
mkdir -p "$CASE_WS/discovery"
printf '# Discovery — %s\n' "$TICKET" >"$CASE_WS/discovery/discovery.md"
write_route "$CASE_WS" direct none
expect_violation "missing no-scenarios declaration" \
  "'No scenarios:' declaration" \
  env RECON_ROOT="$CASE_ROOT" bash "$DISCOVERY_VERIFY" "$TICKET" pre-gate

new_workspace discovery-missing-handoff
write_contract_simple "$CASE_WS"
write_route "$CASE_WS" brief implementation-brief
sed '/^  handoff:/,$d' "$CASE_WS/route/routing.yaml" >"$CASE_WS/route/routing.tmp"
mv "$CASE_WS/route/routing.tmp" "$CASE_WS/route/routing.yaml"
write_impl_brief "$CASE_WS" simple
expect_violation "missing route handoff" "routing.handoff must be non-empty" \
  env RECON_ROOT="$CASE_ROOT" bash "$DISCOVERY_VERIFY" "$TICKET" pre-gate

# The routing producer's complete audit record crosses the same boundary as its
# route choice. Missing, malformed, duplicate, or invented route fields fail
# even when route/brief compatibility and the handoff itself still look valid.
new_workspace discovery-route-matched-rule-missing
write_contract_simple "$CASE_WS"
write_route "$CASE_WS" brief implementation-brief
sed '/^  matched_rule:/d' "$CASE_WS/route/routing.yaml" \
  >"$CASE_WS/route/routing.tmp"
mv "$CASE_WS/route/routing.tmp" "$CASE_WS/route/routing.yaml"
write_impl_brief "$CASE_WS" simple
expect_violation "missing route matched rule" "routing.matched_rule must be non-empty" \
  env RECON_ROOT="$CASE_ROOT" bash "$DISCOVERY_VERIFY" "$TICKET" pre-gate

new_workspace discovery-route-comment-only-rule
write_contract_simple "$CASE_WS"
write_route "$CASE_WS" brief implementation-brief
sed 's/^  matched_rule: fixture$/  matched_rule: # missing/' \
  "$CASE_WS/route/routing.yaml" >"$CASE_WS/route/routing.tmp"
mv "$CASE_WS/route/routing.tmp" "$CASE_WS/route/routing.yaml"
write_impl_brief "$CASE_WS" simple
expect_violation "comment-only matched rule" "routing.matched_rule must be non-empty" \
  env RECON_ROOT="$CASE_ROOT" bash "$DISCOVERY_VERIFY" "$TICKET" pre-gate

new_workspace discovery-route-repo-commit-missing
write_contract_simple "$CASE_WS"
write_route "$CASE_WS" brief implementation-brief
sed '/^    repo_commit:/d' "$CASE_WS/route/routing.yaml" \
  >"$CASE_WS/route/routing.tmp"
mv "$CASE_WS/route/routing.tmp" "$CASE_WS/route/routing.yaml"
write_impl_brief "$CASE_WS" simple
expect_violation "missing route repo commit" \
  "routing.evidence.repo_commit must be non-empty" \
  env RECON_ROOT="$CASE_ROOT" bash "$DISCOVERY_VERIFY" "$TICKET" pre-gate

new_workspace discovery-route-repo-commit-unknown
write_contract_simple "$CASE_WS"
write_route "$CASE_WS" brief implementation-brief
sed "s/$FIXTURE_COMMIT/unknown/" "$CASE_WS/route/routing.yaml" \
  >"$CASE_WS/route/routing.tmp"
mv "$CASE_WS/route/routing.tmp" "$CASE_WS/route/routing.yaml"
write_impl_brief "$CASE_WS" simple
expect_violation "unknown route repo commit" \
  "repo_commit must be a full 40- or 64-character lowercase Git object ID" \
  env RECON_ROOT="$CASE_ROOT" bash "$DISCOVERY_VERIFY" "$TICKET" pre-gate

new_workspace discovery-route-repo-commit-malformed
write_contract_simple "$CASE_WS"
write_route "$CASE_WS" brief implementation-brief
sed "s/$FIXTURE_COMMIT/deadbeef/" "$CASE_WS/route/routing.yaml" \
  >"$CASE_WS/route/routing.tmp"
mv "$CASE_WS/route/routing.tmp" "$CASE_WS/route/routing.yaml"
write_impl_brief "$CASE_WS" simple
expect_violation "malformed route repo commit" \
  "repo_commit must be a full 40- or 64-character lowercase Git object ID" \
  env RECON_ROOT="$CASE_ROOT" bash "$DISCOVERY_VERIFY" "$TICKET" pre-gate

new_workspace discovery-route-producer-without-commit
write_contract_simple "$CASE_WS"
mkdir -p "$CASE_ROOT/empty-target"
git init -q "$CASE_ROOT/empty-target"
expect_exit_code "generic route without Git commit" \
  "current repository has no Git HEAD commit" 2 \
  env RECON_ROOT="$CASE_ROOT" bash -c \
  'cd "$1" && bash "$2" "$3" fixture' \
  _ "$CASE_ROOT/empty-target" "$ROUTE_GENERIC" "$TICKET"
if [ -e "$CASE_WS/route/routing.yaml" ]; then
  fail "generic route wrote an unpinned routing artifact"
fi

new_workspace discovery-route-rules-empty
write_contract_simple "$CASE_WS"
write_route "$CASE_WS" brief implementation-brief
sed -e 's/^  rules_not_matched:$/  rules_not_matched: {}/' \
  -e '/^    fixture-other:/d' "$CASE_WS/route/routing.yaml" \
  >"$CASE_WS/route/routing.tmp"
mv "$CASE_WS/route/routing.tmp" "$CASE_WS/route/routing.yaml"
write_impl_brief "$CASE_WS" simple
expect_violation "empty unmatched-rule trace" \
  "routing.rules_not_matched must be a non-empty mapping" \
  env RECON_ROOT="$CASE_ROOT" bash "$DISCOVERY_VERIFY" "$TICKET" pre-gate

new_workspace discovery-route-evidence-indent
write_contract_simple "$CASE_WS"
write_route "$CASE_WS" brief implementation-brief
sed 's/^    repo_commit:/   repo_commit:/' "$CASE_WS/route/routing.yaml" \
  >"$CASE_WS/route/routing.tmp"
mv "$CASE_WS/route/routing.tmp" "$CASE_WS/route/routing.yaml"
write_impl_brief "$CASE_WS" simple
expect_violation "malformed route evidence indentation" \
  "invalid evidence entry or indentation" \
  env RECON_ROOT="$CASE_ROOT" bash "$DISCOVERY_VERIFY" "$TICKET" pre-gate

new_workspace discovery-route-field-duplicate
write_contract_simple "$CASE_WS"
write_route "$CASE_WS" brief implementation-brief
printf '%s\n' '  governance_source: duplicate' >>"$CASE_WS/route/routing.yaml"
write_impl_brief "$CASE_WS" simple
expect_violation "duplicate route field" "duplicate field 'governance_source'" \
  env RECON_ROOT="$CASE_ROOT" bash "$DISCOVERY_VERIFY" "$TICKET" pre-gate

new_workspace discovery-route-field-unknown
write_contract_simple "$CASE_WS"
write_route "$CASE_WS" brief implementation-brief
printf '%s\n' '  invented_field: surprise' >>"$CASE_WS/route/routing.yaml"
write_impl_brief "$CASE_WS" simple
expect_violation "unknown route field" "unknown routing field 'invented_field'" \
  env RECON_ROOT="$CASE_ROOT" bash "$DISCOVERY_VERIFY" "$TICKET" pre-gate

new_workspace discovery-route-handoff-scalar
write_contract_simple "$CASE_WS"
write_route "$CASE_WS" brief implementation-brief
sed 's/^  handoff: |$/  handoff: continue directly/' \
  "$CASE_WS/route/routing.yaml" >"$CASE_WS/route/routing.tmp"
mv "$CASE_WS/route/routing.tmp" "$CASE_WS/route/routing.yaml"
write_impl_brief "$CASE_WS" simple
expect_violation "scalar route handoff" "handoff must use a YAML block scalar" \
  env RECON_ROOT="$CASE_ROOT" bash "$DISCOVERY_VERIFY" "$TICKET" pre-gate

new_workspace discovery-problem-section-missing
write_contract_simple "$CASE_WS"
write_route "$CASE_WS" prd-chain problem-statement
write_problem_statement "$CASE_WS"
sed '/^## Open choices/,$d' "$CASE_WS/discovery/spec-draft.md" >"$CASE_WS/discovery/spec.tmp"
mv "$CASE_WS/discovery/spec.tmp" "$CASE_WS/discovery/spec-draft.md"
expect_violation "missing problem-statement section" \
  "spec-draft.md missing required section 'Open choices'" \
  env RECON_ROOT="$CASE_ROOT" bash "$DISCOVERY_VERIFY" "$TICKET" pre-gate

new_workspace discovery-rejection-reason-missing
write_contract_all "$CASE_WS"
write_route "$CASE_WS" brief implementation-brief
write_impl_brief "$CASE_WS" all
write_gate "$CASE_WS" rejected-open
sed '/^  rejected:/d' "$CASE_WS/discovery/gate.yaml" >"$CASE_WS/discovery/gate.tmp"
mv "$CASE_WS/discovery/gate.tmp" "$CASE_WS/discovery/gate.yaml"
expect_violation "missing rejection reason" \
  "rejected gate requires a non-empty rejected reason" \
  env RECON_ROOT="$CASE_ROOT" bash "$DISCOVERY_VERIFY" "$TICKET" post-gate

echo "artifact verifiers: PASS — $PASS_COUNT isolated cases"
