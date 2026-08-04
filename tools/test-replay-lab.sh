#!/bin/bash
# Isolated controls for the real-ticket replay laboratory.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Git exports the caller's repository variables to hooks. The fixture repos
# below must discover themselves from -C/cwd instead of inheriting that state.
unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE GIT_OBJECT_DIRECTORY \
  GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_NAMESPACE \
  GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
PY="$ROOT/tools/replay-ticket.py"
CASE="$ROOT/evals/cases/att-4845-pre-comment"
READY_CASE="$ROOT/evals/cases/requirement-closure-ready-control"
LAB_SKILL="$ROOT/evals/skills/recon-replay-lab/SKILL.md"
HANDOFFS="$ROOT/evals/skills/recon-replay-lab/references/handoffs.md"
INTERPRETATION="$ROOT/evals/skills/recon-replay-lab/references/interpretation.md"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/recon-replay-lab.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

fail() {
  echo "replay-lab test failed: $1" >&2
  exit 1
}

assert_has() {
  local file="$1" text="$2"
  grep -qF -- "$text" "$file" || fail "expected '$text' in $file"
}

file_hash() {
  python3 - "$1" <<'PY'
import hashlib
import pathlib
import sys

print(hashlib.sha256(pathlib.Path(sys.argv[1]).read_bytes()).hexdigest())
PY
}

assert_has "$LAB_SKILL" "retained files as state"
assert_has "$LAB_SKILL" "in the operator context"
assert_has "$LAB_SKILL" "verify-submission.py"
assert_has "$HANDOFFS" "--- fresh-context prompt ---"
assert_has "$HANDOFFS" "The run directory is the only"
assert_has "$HANDOFFS" "STOP: the operator context must not author the submission"
assert_has "$INTERPRETATION" "After the state rail, the run directory is the single handle"
assert_has "$ROOT/AGENTS.md" "evals/skills/recon-replay-lab/SKILL.md"

python3 "$PY" validate "$CASE" >"$TMP/validate.out"
assert_has "$TMP/validate.out" "3 decision(s), oracle separated"

python3 "$PY" score "$CASE" "$CASE/fixtures/atomic-pass.yaml" >"$TMP/atomic.out"
assert_has "$TMP/atomic.out" "decision coverage: PASS — 3/3 distinct decisions"
assert_has "$TMP/atomic.out" "score: PASS"

python3 "$PY" validate "$READY_CASE" >"$TMP/ready-validate.out"
assert_has "$TMP/ready-validate.out" "0 decision(s), oracle separated"
python3 "$PY" score "$READY_CASE" "$READY_CASE/fixtures/ready-pass.yaml" >"$TMP/ready-score.out"
assert_has "$TMP/ready-score.out" "disposition: PASS — READY"
assert_has "$TMP/ready-score.out" "decision coverage: PASS — 0/0 distinct decisions"
assert_has "$TMP/ready-score.out" "score: PASS"

cp -R "$READY_CASE" "$TMP/blocked-empty-control"
mv "$TMP/blocked-empty-control" "$TMP/requirement-closure-ready-control"
perl -0pi -e 's/"expected_disposition": "READY"/"expected_disposition": "BLOCKED"/' "$TMP/requirement-closure-ready-control/oracle/decisions.json"
set +e
python3 "$PY" validate "$TMP/requirement-closure-ready-control" >"$TMP/blocked-empty.out" 2>&1
blocked_empty_status=$?
set -e
[ "$blocked_empty_status" -eq 2 ] || fail "BLOCKED empty oracle exited $blocked_empty_status, expected 2"
assert_has "$TMP/blocked-empty.out" "may be empty only when expected_disposition is READY"

set +e
python3 "$PY" score "$CASE" "$CASE/fixtures/combined-layout-fail.yaml" >"$TMP/combined.out" 2>&1
combined_status=$?
set -e
[ "$combined_status" -eq 1 ] || fail "combined control exited $combined_status, expected 1"
assert_has "$TMP/combined.out" "decision DEC-3: blocker BLK-2 points to DEC-2"

mkdir -p "$TMP/tampered"
cp -R "$CASE" "$TMP/tampered/att-4845-pre-comment"
printf '\n' >>"$TMP/tampered/att-4845-pre-comment/input/ticket.json"
set +e
python3 "$PY" validate "$TMP/tampered/att-4845-pre-comment" >"$TMP/tampered.out" 2>&1
tampered_status=$?
set -e
[ "$tampered_status" -eq 2 ] || fail "tampered case exited $tampered_status, expected 2"
assert_has "$TMP/tampered.out" "input hash drift"

TARGET="$TMP/target"
mkdir -p "$TARGET"
git -C "$TARGET" init -q
git -C "$TARGET" config user.name "Recon Replay Lab"
git -C "$TARGET" config user.email "replay@example.invalid"
printf 'frozen target\n' >"$TARGET/README.md"
git -C "$TARGET" add README.md
git -C "$TARGET" commit -q -m "test: freeze target"
target_commit="$(git -C "$TARGET" rev-parse HEAD)"

SYNTHETIC="$TMP/synthetic-prepare"
mkdir -p "$SYNTHETIC/input" "$SYNTHETIC/oracle"
printf '%s\n' \
  '{' \
  '  "id": "LAB-1",' \
  '  "key": "LAB-1",' \
  '  "fields": {' \
  '    "summary": "Synthetic replay",' \
  '    "description": "Frozen synthetic input",' \
  '    "comment": {"total": 0, "comments": []}' \
  '  }' \
  '}' >"$SYNTHETIC/input/ticket.json"
ticket_hash="$(file_hash "$SYNTHETIC/input/ticket.json")"
printf '%s\n' \
  '{' \
  '  "schema_version": 1,' \
  '  "expected_disposition": "BLOCKED",' \
  '  "required_decisions": [' \
  '    {' \
  '      "id": "synthetic-decision-secret",' \
  '      "label": "Synthetic oracle secret",' \
  '      "signals": [["synthetic"], ["secret"]]' \
  '    }' \
  '  ]' \
  '}' >"$SYNTHETIC/oracle/decisions.json"
printf '%s\n' \
  '{' \
  '  "schema_version": 1,' \
  '  "id": "synthetic-prepare",' \
  '  "task_class": "test",' \
  '  "source": {' \
  '    "ticket": "LAB-1",' \
  '    "snapshot_at": "2026-08-04T00:00:00Z",' \
  '    "cutoff": "Synthetic test cutoff",' \
  '    "human_comments": 0' \
  '  },' \
  '  "input": {' \
  '    "ticket": "input/ticket.json",' \
  "    \"sha256\": \"$ticket_hash\"" \
  '  },' \
  '  "repository": {' \
  '    "name": "synthetic-target",' \
  "    \"commit\": \"$target_commit\"" \
  '  },' \
  '  "oracle": "oracle/decisions.json"' \
  '}' >"$SYNTHETIC/case.json"

PREPARED="$TMP/prepared"
python3 "$PY" prepare "$SYNTHETIC" --repo "$TARGET" --out "$PREPARED" >"$TMP/prepare.out"
assert_has "$TMP/prepare.out" "oracle excluded"
[ "$(<"$PREPARED/target-repo/README.md")" = "frozen target" ] || fail "prepared target bytes drifted"
[ -f "$PREPARED/workspace/LAB-1/triage/ticket.json" ] || fail "prepared ticket missing"
[ -f "$PREPARED/skill/recon-triage/SKILL.md" ] || fail "prepared skill snapshot missing"
[ -x "$PREPARED/verifier/verify-submission.py" ] || fail "prepared verifier is not executable"
[ -f "$PREPARED/verifier/replay-owner-identities.json" ] || fail "prepared owner identities missing"
assert_has "$PREPARED/REPLAY.md" "python3 verifier/verify-submission.py"
if rg -q "synthetic-decision-secret|Synthetic oracle secret" "$PREPARED"; then
  fail "prepared directory leaked oracle content"
fi
if find "$PREPARED" -type f | rg '/(oracle|fixtures)/'; then
  fail "prepared directory copied oracle or fixture paths"
fi

python3 "$PY" state "$PREPARED" --case "$SYNTHETIC" >"$TMP/state-prepared.out"
assert_has "$TMP/state-prepared.out" "state: PREPARED — synthetic-prepare"
assert_has "$TMP/state-prepared.out" "launch a fresh LLM context"

printf '%s\n' \
  'recon: triage' \
  'ticket: LAB-1' \
  'title: "Synthetic replay"' \
  'task_class: capability-change' \
  'disposition: BLOCKED' \
  'outcome_decidable: partial' \
  'evidence_ok: true' \
  'product_decision_open: true' \
  'design_dependency: false' \
  'backend_dependency: false' \
  'blockers:' \
  '  - title: "Synthetic secret"' \
  '    id: BLK-1' \
  '    decision_id: DEC-1' \
  '    owner: product' \
  '    owner_account_id: "replay-owner:product"' \
  '    ask: "Which synthetic secret outcome should the implementation use?"' \
  'conflicts: []' \
  'requirement_coverage:' \
  '  normative_requirements: true' \
  '  identity_mapping: true' \
  '  context_mapping_exhaustive: true' \
  '  ownership_update_path: true' \
  '  threshold_completeness: true' \
  '  ordering_completeness: true' \
  'decision_audit:' \
  '  - id: DEC-1' \
  '    requirement: "Frozen synthetic input"' \
  '    requirement_source: description' \
  '    surface: direct_obligation' \
  '    status: OPEN' \
  '    check: product_decision_open' \
  '    blocking: true' \
  '    blocker_id: BLK-1' \
  '    evidence:' \
  '      - kind: quote' \
  '        text: "Frozen synthetic input"' \
  '        source: description' \
  'evidence:' \
  '  - kind: quote' \
  '    text: "Frozen synthetic input"' \
  '    source: description' >"$PREPARED/submission/triage.yaml"

python3 "$PREPARED/verifier/verify-submission.py" >"$TMP/bundled-pass.out"
assert_has "$TMP/bundled-pass.out" "replay verifier: clean"

for control in disposition missing-owner invalid-owner paraphrased-quote; do
  control_run="$TMP/$control-run"
  python3 "$PY" prepare "$SYNTHETIC" --repo "$TARGET" --out "$control_run" >/dev/null
  cp "$PREPARED/submission/triage.yaml" "$control_run/submission/triage.yaml"
  case "$control" in
    disposition)
      perl -0pi -e 's/disposition: BLOCKED/disposition: NEEDS_INFO/' "$control_run/submission/triage.yaml"
      expected="checks derive BLOCKED"
      ;;
    missing-owner)
      perl -0pi -e 's/owner_account_id: "replay-owner:product"/owner_account_id: ""/' "$control_run/submission/triage.yaml"
      expected="owner_account_id missing — use replay-only identity"
      ;;
    invalid-owner)
      perl -0pi -e 's/owner_account_id: "replay-owner:product"/owner_account_id: "jira:guessed"/' "$control_run/submission/triage.yaml"
      expected="is not the replay-only identity"
      ;;
    paraphrased-quote)
      perl -0pi -e 's/Frozen synthetic input/Frozen input/' "$control_run/submission/triage.yaml"
      expected="requirement is not found verbatim"
      ;;
  esac
  set +e
  python3 "$control_run/verifier/verify-submission.py" >"$TMP/$control.out" 2>&1
  control_status=$?
  set -e
  [ "$control_status" -eq 1 ] || fail "$control verifier exited $control_status, expected 1"
  assert_has "$TMP/$control.out" "$expected"
done

set +e
python3 "$PY" evaluate "$TMP/disposition-run" --case "$SYNTHETIC" >"$TMP/evaluate-verifier-fail.out" 2>&1
verifier_evaluate_status=$?
set -e
[ "$verifier_evaluate_status" -eq 2 ] || fail "verifier-failing evaluate exited $verifier_evaluate_status, expected 2"
assert_has "$TMP/evaluate-verifier-fail.out" "submission verifier failed before evaluation"
[ ! -e "$TMP/disposition-run/evaluation" ] || fail "verifier failure retained evaluation evidence"

python3 "$PY" state "$PREPARED" --case "$SYNTHETIC" >"$TMP/state-submitted.out"
assert_has "$TMP/state-submitted.out" "state: SUBMITTED — synthetic-prepare"
assert_has "$TMP/state-submitted.out" "replay-ticket.py evaluate"

python3 "$PY" evaluate "$PREPARED" --case "$SYNTHETIC" >"$TMP/evaluate-pass.out"
assert_has "$TMP/evaluate-pass.out" "decision coverage: PASS — 1/1 distinct decisions"
assert_has "$TMP/evaluate-pass.out" "evaluate: retained"
[ -f "$PREPARED/evaluation/score.txt" ] || fail "retained score missing"
[ -f "$PREPARED/evaluation/result.json" ] || fail "retained result missing"
python3 "$PY" state "$PREPARED" --case "$SYNTHETIC" >"$TMP/state-scored.out"
assert_has "$TMP/state-scored.out" "state: SCORED — synthetic-prepare"
assert_has "$TMP/state-scored.out" "result: PASS — 1/1 distinct decisions"

result_before="$(file_hash "$PREPARED/evaluation/result.json")"
set +e
python3 "$PY" evaluate "$PREPARED" --case "$SYNTHETIC" >"$TMP/evaluate-overwrite.out" 2>&1
evaluate_overwrite_status=$?
set -e
[ "$evaluate_overwrite_status" -eq 2 ] || fail "evaluate overwrite exited $evaluate_overwrite_status, expected 2"
assert_has "$TMP/evaluate-overwrite.out" "evaluate requires SUBMITTED, found SCORED"
result_after="$(file_hash "$PREPARED/evaluation/result.json")"
[ "$result_before" = "$result_after" ] || fail "evaluate retry changed retained result"

cp "$PREPARED/evaluation/result.json" "$TMP/result-original.json"
perl -0pi -e 's/"matched": 1/"matched": 999/' "$PREPARED/evaluation/result.json"
set +e
python3 "$PY" state "$PREPARED" --case "$SYNTHETIC" >"$TMP/result-drift.out" 2>&1
result_drift_status=$?
set -e
[ "$result_drift_status" -eq 2 ] || fail "result drift exited $result_drift_status, expected 2"
assert_has "$TMP/result-drift.out" "decision_coverage matched is out of range"
cp "$TMP/result-original.json" "$PREPARED/evaluation/result.json"

printf '\n' >>"$PREPARED/submission/triage.yaml"
set +e
python3 "$PY" state "$PREPARED" --case "$SYNTHETIC" >"$TMP/candidate-drift.out" 2>&1
candidate_drift_status=$?
set -e
[ "$candidate_drift_status" -eq 2 ] || fail "candidate drift exited $candidate_drift_status, expected 2"
assert_has "$TMP/candidate-drift.out" "candidate_sha256 mismatch or drift"

SYMLINK_RUN="$TMP/symlink-run"
python3 "$PY" prepare "$SYNTHETIC" --repo "$TARGET" --out "$SYMLINK_RUN" >/dev/null
ln -s "$CASE/fixtures/atomic-pass.yaml" "$SYMLINK_RUN/submission/triage.yaml"
set +e
python3 "$PY" state "$SYMLINK_RUN" --case "$SYNTHETIC" >"$TMP/symlink.out" 2>&1
symlink_status=$?
set -e
[ "$symlink_status" -eq 2 ] || fail "symlink submission exited $symlink_status, expected 2"
assert_has "$TMP/symlink.out" "submission must not be a symlink"

MISMATCH_RUN="$TMP/mismatch-run"
python3 "$PY" prepare "$SYNTHETIC" --repo "$TARGET" --out "$MISMATCH_RUN" >/dev/null
perl -0pi -e 's/"case_id": "synthetic-prepare"/"case_id": "wrong-case"/' "$MISMATCH_RUN/receipt.json"
set +e
python3 "$PY" state "$MISMATCH_RUN" --case "$SYNTHETIC" >"$TMP/receipt-mismatch.out" 2>&1
receipt_mismatch_status=$?
set -e
[ "$receipt_mismatch_status" -eq 2 ] || fail "receipt mismatch exited $receipt_mismatch_status, expected 2"
assert_has "$TMP/receipt-mismatch.out" "receipt case_id mismatch"

INCONSISTENT_RUN="$TMP/inconsistent-run"
python3 "$PY" prepare "$SYNTHETIC" --repo "$TARGET" --out "$INCONSISTENT_RUN" >/dev/null
cp "$CASE/fixtures/atomic-pass.yaml" "$INCONSISTENT_RUN/submission/triage.yaml"
mkdir "$INCONSISTENT_RUN/evaluation"
printf 'partial\n' >"$INCONSISTENT_RUN/evaluation/score.txt"
set +e
python3 "$PY" state "$INCONSISTENT_RUN" --case "$SYNTHETIC" >"$TMP/inconsistent.out" 2>&1
inconsistent_status=$?
set -e
[ "$inconsistent_status" -eq 2 ] || fail "inconsistent evaluation exited $inconsistent_status, expected 2"
assert_has "$TMP/inconsistent.out" "evaluation result must be a regular file"

REAL_CASE="$TMP/att-4845-pre-comment"
cp -R "$CASE" "$REAL_CASE"
original_commit="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["repository"]["commit"])' "$REAL_CASE/case.json")"
perl -0pi -e "s/$original_commit/$target_commit/g" "$REAL_CASE/case.json"
FAIL_RUN="$TMP/combined-fail-run"
python3 "$PY" prepare "$REAL_CASE" --repo "$TARGET" --out "$FAIL_RUN" >/dev/null
cp "$REAL_CASE/fixtures/combined-layout-fail.yaml" "$FAIL_RUN/submission/triage.yaml"
set +e
python3 "$PY" evaluate "$FAIL_RUN" --case "$REAL_CASE" >"$TMP/evaluate-fail.out" 2>&1
evaluate_fail_status=$?
set -e
[ "$evaluate_fail_status" -eq 2 ] || fail "invalid-atomicity evaluate exited $evaluate_fail_status, expected 2"
assert_has "$TMP/evaluate-fail.out" "submission verifier failed before evaluation"
python3 "$PY" state "$FAIL_RUN" --case "$REAL_CASE" >"$TMP/state-scored-fail.out"
assert_has "$TMP/state-scored-fail.out" "state: SUBMITTED — att-4845-pre-comment"

receipt_before="$(file_hash "$PREPARED/receipt.json")"
set +e
python3 "$PY" prepare "$SYNTHETIC" --repo "$TARGET" --out "$PREPARED" >"$TMP/overwrite.out" 2>&1
overwrite_status=$?
set -e
[ "$overwrite_status" -eq 2 ] || fail "overwrite control exited $overwrite_status, expected 2"
assert_has "$TMP/overwrite.out" "refusing overwrite"
receipt_after="$(file_hash "$PREPARED/receipt.json")"
[ "$receipt_before" = "$receipt_after" ] || fail "overwrite attempt changed prepared receipt"

echo "replay-lab tests: clean — case, scoring, preparation, persisted states, atomic evaluation, drift, isolation, and overwrite controls passed"
