#!/bin/bash
# Isolated fixtures for the rendered Jira comment rails. Proves the BLOCKED
# progressive-disclosure shape and the approved READY Discovery delivery shape.
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
RENDER="$ROOT/recon/scripts/render-comment.sh"
SHAPE="$ROOT/recon/scripts/verify-comment-shape.sh"
BASE_TMP="${TMPDIR:-/tmp}"
BASE_TMP="${BASE_TMP%/}"
FIXTURE="$(mktemp -d "$BASE_TMP/recon-comment-rendering.XXXXXX")"

cleanup() {
  case "$FIXTURE" in
    "$BASE_TMP"/recon-comment-rendering.*) rm -rf "$FIXTURE" ;;
    *) echo "comment rendering: refusing unexpected fixture path" >&2 ;;
  esac
}
trap cleanup EXIT

fail() { echo "comment rendering: FAIL — $1" >&2; exit 1; }

write_meta() {
  local ws="$1" ticket="$2"
  mkdir -p "$ws"
  printf '%s\n' \
    'plugin_version: test' \
    'started: 2026-08-02T12:00:00Z' \
    "ticket: $ticket" \
    >"$ws/meta.yaml"
}

blocked="$FIXTURE/blocked/TEST-1"
write_meta "$blocked" TEST-1
mkdir -p "$blocked/triage"
printf '%s\n' \
  'recon: triage' \
  'ticket: TEST-1' \
  'title: "Blocked ticket"' \
  'task_class: defect' \
  'disposition: BLOCKED' \
  'outcome_decidable: true' \
  'evidence_ok: false' \
  'product_decision_open: false' \
  'design_dependency: false' \
  'backend_dependency: false' \
  'blockers:' \
  '  - title: "Missing evidence"' \
  '    owner: tester' \
  '    owner_account_id: "acct-1"' \
  '    ask: "provide the missing evidence?"' \
  '    detail:' \
  '      state: "waiting"' \
  '      options: []' \
  '      evidence: []' \
  'conflicts: []' \
  'evidence:' \
  '  - kind: note' \
  '    text: "fixture"' \
  >"$blocked/triage/triage.yaml"
RECON_ROOT="$FIXTURE/blocked" bash "$RENDER" TEST-1 >/dev/null
RECON_ROOT="$FIXTURE/blocked" bash "$SHAPE" TEST-1 >/dev/null || fail "BLOCKED shape"

ready="$FIXTURE/ready/TEST-2"
write_meta "$ready" TEST-2
mkdir -p "$ready/triage" "$ready/discovery" "$ready/route"
printf '%s\n' \
  'recon: triage' \
  'ticket: TEST-2' \
  'title: "Ready ticket"' \
  'task_class: defect' \
  'disposition: READY' \
  'outcome_decidable: true' \
  'evidence_ok: true' \
  'product_decision_open: false' \
  'design_dependency: false' \
  'backend_dependency: false' \
  'blockers: []' \
  'conflicts: []' \
  'evidence:' \
  '  - kind: note' \
  '    text: "fixture"' \
  >"$ready/triage/triage.yaml"
printf '%s\n' \
  'gate:' \
  '  approved: true' \
  '  date: 2026-08-02' \
  '  open_scenario_resolutions:' \
  '    OPEN-1: "The hidden row does nothing."' \
  >"$ready/discovery/gate.yaml"
printf '%s\n' \
  'routing:' \
  '  route: new-spec' \
  '  matched_rule: 2' \
  >"$ready/route/routing.yaml"
RECON_ROOT="$FIXTURE/ready" bash "$RENDER" TEST-2 >/dev/null
RECON_ROOT="$FIXTURE/ready" bash "$SHAPE" TEST-2 >/dev/null || fail "READY shape"
grep -q '^\*Approval:\* Discovery package approved; 1 open decision(s) recorded\.$' "$ready/triage/jira/comment.txt" \
  || fail "READY approval decision count"

printf '%s\n' \
  'gate:' \
  '  approved: false' \
  '  date: 2026-08-02' \
  '  open_scenario_resolutions:' \
  '    OPEN-1: "The hidden row does nothing."' \
  >"$ready/discovery/gate.yaml"
if RECON_ROOT="$FIXTURE/ready" bash "$RENDER" TEST-2 >/dev/null 2>&1; then
  fail "READY render accepted an unapproved Discovery package"
fi

echo "comment rendering: PASS — BLOCKED and READY shapes; unapproved READY rejected"
