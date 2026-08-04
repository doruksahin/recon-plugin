#!/usr/bin/env bash
# Isolated controls for the generic decision-closure triage verifier.
set -euo pipefail

ROOT="${RECON_PLUGIN:-$(cd "$(dirname "$0")/.." && pwd)}"
VERIFY="$ROOT/recon/scripts/verify-triage.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/recon-triage-verify.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
expect_pass() { "$@" >"$TMP/pass.out" 2>&1 || { cat "$TMP/pass.out" >&2; fail "$1"; }; }
expect_fail() {
  local expected="$1"; shift
  set +e
  "$@" >"$TMP/fail.out" 2>&1
  local status=$?
  set -e
  [ "$status" -eq 1 ] || { cat "$TMP/fail.out" >&2; fail "expected exit 1"; }
  grep -Fq "$expected" "$TMP/fail.out" || { cat "$TMP/fail.out" >&2; fail "missing diagnostic: $expected"; }
}

make_workspace() {
  local name="$1"
  local ws="$TMP/$name/TEST-1"
  mkdir -p "$ws/triage" "$TMP/$name/source"
  printf 'repository mapping closes this technical choice\n' >"$TMP/$name/source/mapping.txt"
  printf '%s\n' '{"fields":{"summary":"Generic choice","description":"Select one visible result for every context. When no context is supplied, show the fallback result. The standard context shows the primary result. The legacy context is an alias of the standard context and shows the primary result. The dialog shows the chosen result. Optional threshold refinement may be skipped. Either internal ordering algorithm is acceptable.","comment":{"comments":[]}}}' >"$ws/triage/ticket.json"
  printf '%s\n' "$ws"
}

write_blocked() {
  local ws="$1"
  cat >"$ws/triage/triage.yaml" <<'YAML'
recon: triage
ticket: TEST-1
title: "Generic closure control"
task_class: capability-change
disposition: BLOCKED
outcome_decidable: true
evidence_ok: true
product_decision_open: true
design_dependency: false
backend_dependency: false
blockers:
  - title: "Visible result choice"
    id: BLK-1
    decision_id: DEC-1
    owner: product
    owner_account_id: "replay-owner:product"
    ask: "Which visible result should occur?"
    detail:
      evidence: []
conflicts: []
requirement_coverage:
  normative_requirements: true
  identity_mapping: true
  context_mapping_exhaustive: true
  ownership_update_path: true
  threshold_completeness: true
  ordering_completeness: true
decision_audit:
  - id: DEC-1
    requirement: "Select one visible result for every context."
    requirement_source: description
    surface: identity_mapping
    context_kind: named
    context_identity: "each named context"
    observable_result: UNRESOLVED
    status: OPEN
    check: product_decision_open
    blocking: true
    blocker_id: BLK-1
    evidence:
      - kind: quote
        text: "Select one visible result for every context."
        source: description
  - id: DEC-2
    requirement: "The dialog shows the chosen result."
    requirement_source: description
    surface: direct_obligation
    status: CLOSED_BY_TICKET
    check: design_dependency
    blocking: false
    evidence:
      - kind: quote
        text: "The dialog shows the chosen result."
        source: description
  - id: DEC-3
    requirement: "The dialog shows the chosen result."
    requirement_source: description
    surface: ownership_update_path
    status: CLOSED_BY_REPOSITORY
    check: backend_dependency
    blocking: false
    evidence:
      - kind: file
        path: "mapping.txt"
        line: 1
        text: "repository mapping closes this technical choice"
  - id: DEC-4
    requirement: "Optional threshold refinement may be skipped."
    requirement_source: description
    surface: threshold_completeness
    status: OPTIONAL_OUT_OF_SCOPE
    check: product_decision_open
    blocking: false
    evidence:
      - kind: quote
        text: "Optional threshold refinement may be skipped."
        source: description
  - id: DEC-5
    requirement: "Either internal ordering algorithm is acceptable."
    requirement_source: description
    surface: ordering_completeness
    status: IMPLEMENTATION_FREEDOM
    check: design_dependency
    blocking: false
    evidence:
      - kind: quote
        text: "Either internal ordering algorithm is acceptable."
        source: description
  - id: DEC-6
    requirement: "When no context is supplied, show the fallback result."
    requirement_source: description
    surface: identity_mapping
    context_kind: omitted
    context_identity: "no context supplied"
    observable_result: "fallback result"
    status: CLOSED_BY_TICKET
    check: product_decision_open
    blocking: false
    evidence:
      - kind: quote
        text: "When no context is supplied, show the fallback result."
        source: description
  - id: DEC-7
    requirement: "The standard context shows the primary result."
    requirement_source: description
    surface: identity_mapping
    context_kind: default
    context_identity: "standard context"
    observable_result: "primary result"
    status: CLOSED_BY_TICKET
    check: product_decision_open
    blocking: false
    evidence:
      - kind: quote
        text: "The standard context shows the primary result."
        source: description
  - id: DEC-8
    requirement: "The legacy context is an alias of the standard context and shows the primary result."
    requirement_source: description
    surface: identity_mapping
    context_kind: alias
    context_identity: "legacy context"
    observable_result: "primary result"
    status: CLOSED_BY_TICKET
    check: product_decision_open
    blocking: false
    evidence:
      - kind: quote
        text: "The legacy context is an alias of the standard context and shows the primary result."
        source: description
evidence:
  - kind: quote
    text: "Select one visible result for every context."
    source: description
YAML
}

write_ready() {
  local ws="$1"
  cat >"$ws/triage/triage.yaml" <<'YAML'
recon: triage
ticket: TEST-1
title: "Generic ready control"
task_class: capability-change
disposition: READY
outcome_decidable: true
evidence_ok: true
product_decision_open: false
design_dependency: false
backend_dependency: false
blockers: []
conflicts: []
requirement_coverage:
  normative_requirements: true
  identity_mapping: true
  context_mapping_exhaustive: true
  ownership_update_path: true
  threshold_completeness: true
  ordering_completeness: true
decision_audit:
  - id: DEC-1
    requirement: "The dialog shows the chosen result."
    requirement_source: description
    surface: direct_obligation
    status: CLOSED_BY_TICKET
    check: product_decision_open
    blocking: false
    evidence:
      - kind: quote
        text: "The dialog shows the chosen result."
        source: description
evidence:
  - kind: quote
    text: "The dialog shows the chosen result."
    source: description
YAML
}

blocked="$(make_workspace blocked)"
write_blocked "$blocked"
expect_pass env RECON_ROOT="$TMP/blocked" RECON_SOURCE_ROOT="$TMP/blocked/source" bash "$VERIFY" TEST-1
grep -Fq 'verify: clean — disposition BLOCKED' "$TMP/pass.out" || fail "blocked control did not verify"

ready="$(make_workspace ready)"
write_ready "$ready"
expect_pass env RECON_ROOT="$TMP/ready" RECON_SOURCE_ROOT="$TMP/ready/source" bash "$VERIFY" TEST-1
grep -Fq 'verify: clean — disposition READY' "$TMP/pass.out" || fail "READY negative control did not verify"

cp -R "$TMP/blocked" "$TMP/missing-coverage"
perl -0pi -e 's/requirement_coverage:\n  normative_requirements: true\n  identity_mapping: true\n  context_mapping_exhaustive: true\n  ownership_update_path: true\n  threshold_completeness: true\n  ordering_completeness: true\n//' "$TMP/missing-coverage/TEST-1/triage/triage.yaml"
expect_fail "missing required section 'requirement_coverage'" env RECON_ROOT="$TMP/missing-coverage" RECON_SOURCE_ROOT="$TMP/missing-coverage/source" bash "$VERIFY" TEST-1

cp -R "$TMP/blocked" "$TMP/incomplete-coverage"
perl -0pi -e 's/threshold_completeness: true/threshold_completeness: false/' "$TMP/incomplete-coverage/TEST-1/triage/triage.yaml"
expect_fail 'requirement_coverage: threshold_completeness must be true after the audit' env RECON_ROOT="$TMP/incomplete-coverage" RECON_SOURCE_ROOT="$TMP/incomplete-coverage/source" bash "$VERIFY" TEST-1

cp -R "$TMP/blocked" "$TMP/incomplete-context-coverage"
perl -0pi -e 's/context_mapping_exhaustive: true/context_mapping_exhaustive: false/' "$TMP/incomplete-context-coverage/TEST-1/triage/triage.yaml"
expect_fail 'requirement_coverage: context_mapping_exhaustive must be true after the audit' env RECON_ROOT="$TMP/incomplete-context-coverage" RECON_SOURCE_ROOT="$TMP/incomplete-context-coverage/source" bash "$VERIFY" TEST-1

cp -R "$TMP/blocked" "$TMP/missing-surface"
perl -0pi -e 's/    surface: identity_mapping\n//' "$TMP/missing-surface/TEST-1/triage/triage.yaml"
expect_fail 'surface must be one of' env RECON_ROOT="$TMP/missing-surface" RECON_SOURCE_ROOT="$TMP/missing-surface/source" bash "$VERIFY" TEST-1

cp -R "$TMP/blocked" "$TMP/unknown-surface"
perl -0pi -e 's/surface: identity_mapping/surface: unspecified/' "$TMP/unknown-surface/TEST-1/triage/triage.yaml"
expect_fail 'surface must be one of' env RECON_ROOT="$TMP/unknown-surface" RECON_SOURCE_ROOT="$TMP/unknown-surface/source" bash "$VERIFY" TEST-1

cp -R "$TMP/blocked" "$TMP/missing-context-identity"
perl -0pi -e 's/    context_identity: "each named context"\n//' "$TMP/missing-context-identity/TEST-1/triage/triage.yaml"
expect_fail "identity_mapping missing field(s) ['context_identity']" env RECON_ROOT="$TMP/missing-context-identity" RECON_SOURCE_ROOT="$TMP/missing-context-identity/source" bash "$VERIFY" TEST-1

cp -R "$TMP/blocked" "$TMP/unknown-context-kind"
perl -0pi -e 's/context_kind: named/context_kind: implicit/' "$TMP/unknown-context-kind/TEST-1/triage/triage.yaml"
expect_fail 'context_kind must be one of' env RECON_ROOT="$TMP/unknown-context-kind" RECON_SOURCE_ROOT="$TMP/unknown-context-kind/source" bash "$VERIFY" TEST-1

cp -R "$TMP/blocked" "$TMP/mapping-fields-on-direct"
perl -0pi -e 's/surface: identity_mapping/surface: direct_obligation/' "$TMP/mapping-fields-on-direct/TEST-1/triage/triage.yaml"
expect_fail 'context mapping fields are allowed only on identity_mapping' env RECON_ROOT="$TMP/mapping-fields-on-direct" RECON_SOURCE_ROOT="$TMP/mapping-fields-on-direct/source" bash "$VERIFY" TEST-1

cp -R "$TMP/blocked" "$TMP/open-selected-result"
perl -0pi -e 's/observable_result: UNRESOLVED/observable_result: "selected result"/' "$TMP/open-selected-result/TEST-1/triage/triage.yaml"
expect_fail 'OPEN identity_mapping must set observable_result to UNRESOLVED' env RECON_ROOT="$TMP/open-selected-result" RECON_SOURCE_ROOT="$TMP/open-selected-result/source" bash "$VERIFY" TEST-1

cp -R "$TMP/blocked" "$TMP/resolved-without-result"
perl -0pi -e 's/observable_result: "fallback result"/observable_result: UNRESOLVED/' "$TMP/resolved-without-result/TEST-1/triage/triage.yaml"
expect_fail 'resolved identity_mapping must select an observable_result' env RECON_ROOT="$TMP/resolved-without-result" RECON_SOURCE_ROOT="$TMP/resolved-without-result/source" bash "$VERIFY" TEST-1

cp -R "$TMP/blocked" "$TMP/duplicate-context-mapping"
perl -0pi -e 's/context_identity: "legacy context"/context_identity: "standard context"/; s/context_kind: alias/context_kind: default/; s/requirement: "The legacy context is an alias of the standard context and shows the primary result\."/requirement: "The standard context shows the primary result."/; s/text: "The legacy context is an alias of the standard context and shows the primary result\."/text: "The standard context shows the primary result."/' "$TMP/duplicate-context-mapping/TEST-1/triage/triage.yaml"
expect_fail "duplicate context mapping for default 'standard context'" env RECON_ROOT="$TMP/duplicate-context-mapping" RECON_SOURCE_ROOT="$TMP/duplicate-context-mapping/source" bash "$VERIFY" TEST-1

cp -R "$TMP/blocked" "$TMP/duplicate-classification"
perl -0pi -e 's/    status: OPEN/    status: OPEN\n    status: CLOSED_BY_TICKET/' "$TMP/duplicate-classification/TEST-1/triage/triage.yaml"
expect_fail "duplicate decision field 'status'" env RECON_ROOT="$TMP/duplicate-classification" RECON_SOURCE_ROOT="$TMP/duplicate-classification/source" bash "$VERIFY" TEST-1

cp -R "$TMP/blocked" "$TMP/open-without-blocker"
perl -0pi -e 's/    blocker_id: BLK-1\n//' "$TMP/open-without-blocker/TEST-1/triage/triage.yaml"
expect_fail 'blocking OPEN decision needs blocker_id BLK-N' env RECON_ROOT="$TMP/open-without-blocker" RECON_SOURCE_ROOT="$TMP/open-without-blocker/source" bash "$VERIFY" TEST-1

cp -R "$TMP/blocked" "$TMP/bad-join"
perl -0pi -e 's/    decision_id: DEC-1/    decision_id: DEC-2/' "$TMP/bad-join/TEST-1/triage/triage.yaml"
expect_fail 'decision DEC-1: blocker BLK-1 points to DEC-2' env RECON_ROOT="$TMP/bad-join" RECON_SOURCE_ROOT="$TMP/bad-join/source" bash "$VERIFY" TEST-1

cp -R "$TMP/blocked" "$TMP/overloaded-join"
perl -0pi -e 's/  - id: DEC-2/  - id: DEC-9\n    requirement: "Select one visible result for every context."\n    requirement_source: description\n    surface: identity_mapping\n    context_kind: named\n    context_identity: "another named context"\n    observable_result: UNRESOLVED\n    status: OPEN\n    check: product_decision_open\n    blocking: true\n    blocker_id: BLK-1\n    evidence:\n      - kind: quote\n        text: "Select one visible result for every context."\n        source: description\n  - id: DEC-2/' "$TMP/overloaded-join/TEST-1/triage/triage.yaml"
expect_fail 'decision DEC-9: blocker BLK-1 points to DEC-1' env RECON_ROOT="$TMP/overloaded-join" RECON_SOURCE_ROOT="$TMP/overloaded-join/source" bash "$VERIFY" TEST-1

cp -R "$TMP/blocked" "$TMP/closed-blocker"
perl -0pi -e 's/status: OPEN/status: CLOSED_BY_TICKET/' "$TMP/closed-blocker/TEST-1/triage/triage.yaml"
expect_fail 'only OPEN decisions may be blocking' env RECON_ROOT="$TMP/closed-blocker" RECON_SOURCE_ROOT="$TMP/closed-blocker/source" bash "$VERIFY" TEST-1

cp -R "$TMP/blocked" "$TMP/optional-blocker"
perl -0pi -e 's/status: OPTIONAL_OUT_OF_SCOPE\n    check: product_decision_open\n    blocking: false/status: OPTIONAL_OUT_OF_SCOPE\n    check: product_decision_open\n    blocking: true\n    blocker_id: BLK-1/' "$TMP/optional-blocker/TEST-1/triage/triage.yaml"
expect_fail 'only OPEN decisions may be blocking' env RECON_ROOT="$TMP/optional-blocker" RECON_SOURCE_ROOT="$TMP/optional-blocker/source" bash "$VERIFY" TEST-1

cp -R "$TMP/blocked" "$TMP/quote-drift"
perl -0pi -e 's/text: "Select one visible result for every context\."/text: "Changed words."/' "$TMP/quote-drift/TEST-1/triage/triage.yaml"
expect_fail 'quote not found verbatim' env RECON_ROOT="$TMP/quote-drift" RECON_SOURCE_ROOT="$TMP/quote-drift/source" bash "$VERIFY" TEST-1

cp -R "$TMP/blocked" "$TMP/requirement-drift"
perl -0pi -e 's/requirement: "Select one visible result for every context\."/requirement: "Changed requirement."/' "$TMP/requirement-drift/TEST-1/triage/triage.yaml"
expect_fail 'requirement is not found verbatim' env RECON_ROOT="$TMP/requirement-drift" RECON_SOURCE_ROOT="$TMP/requirement-drift/source" bash "$VERIFY" TEST-1

cp -R "$TMP/blocked" "$TMP/missing-requirement"
perl -0pi -e 's/    requirement: "Select one visible result for every context\."\n//' "$TMP/missing-requirement/TEST-1/triage/triage.yaml"
expect_fail 'requirement must retain the observable obligation' env RECON_ROOT="$TMP/missing-requirement" RECON_SOURCE_ROOT="$TMP/missing-requirement/source" bash "$VERIFY" TEST-1

cp -R "$TMP/blocked" "$TMP/requirement-source-drift"
perl -0pi -e 's/requirement_source: description/requirement_source: comment 99/' "$TMP/requirement-source-drift/TEST-1/triage/triage.yaml"
expect_fail "requirement_source 'comment 99' not in ticket.json" env RECON_ROOT="$TMP/requirement-source-drift" RECON_SOURCE_ROOT="$TMP/requirement-source-drift/source" bash "$VERIFY" TEST-1

cp -R "$TMP/blocked" "$TMP/file-drift"
printf 'changed source line\n' >"$TMP/file-drift/source/mapping.txt"
expect_fail 'file evidence drift at mapping.txt:1' env RECON_ROOT="$TMP/file-drift" RECON_SOURCE_ROOT="$TMP/file-drift/source" bash "$VERIFY" TEST-1

cp -R "$TMP/blocked" "$TMP/repository-without-file"
perl -0pi -e 's/      - kind: file\n        path: "mapping.txt"\n        line: 1\n        text: "repository mapping closes this technical choice"/      - kind: note\n        text: "repository search suggested a likely mapping"/' "$TMP/repository-without-file/TEST-1/triage/triage.yaml"
expect_fail 'CLOSED_BY_REPOSITORY requires cited file evidence' env RECON_ROOT="$TMP/repository-without-file" RECON_SOURCE_ROOT="$TMP/repository-without-file/source" bash "$VERIFY" TEST-1

cp -R "$TMP/blocked" "$TMP/ready-with-open"
perl -0pi -e 's/disposition: BLOCKED/disposition: READY/' "$TMP/ready-with-open/TEST-1/triage/triage.yaml"
expect_fail 'checks derive BLOCKED' env RECON_ROOT="$TMP/ready-with-open" RECON_SOURCE_ROOT="$TMP/ready-with-open/source" bash "$VERIFY" TEST-1

cp -R "$TMP/ready" "$TMP/blocked-without-open"
perl -0pi -e 's/disposition: READY/disposition: BLOCKED/' "$TMP/blocked-without-open/TEST-1/triage/triage.yaml"
expect_fail 'checks derive READY' env RECON_ROOT="$TMP/blocked-without-open" RECON_SOURCE_ROOT="$TMP/blocked-without-open/source" bash "$VERIFY" TEST-1

if rg -ni --glob 'SKILL.md' --glob 'triage-tools.py' 'ATT-4845|stock image|product photo ads|brand[- ]seed|intro-layout|keyword-presentation' "$ROOT/recon/skills/recon-triage" "$ROOT/recon/scripts/triage-tools.py"; then
  fail "case-specific oracle vocabulary leaked into shipped triage assets"
fi

echo 'triage verifier controls: clean'
