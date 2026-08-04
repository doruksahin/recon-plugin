#!/usr/bin/env bash
# Isolated contract controls for tools/improvement-cycle.py.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYTHON="${PYTHON:-python3}"
TEMP="$(mktemp -d "$ROOT/.improvement-cycle-test.XXXXXX")"
EVIDENCE_ID="improvement-cycle-test-$$"
REJECT_EVIDENCE_ID="improvement-cycle-reject-test-$$"
PROPOSAL="$TEMP/proposal"
REJECT_PROPOSAL="$TEMP/reject-proposal"
BASELINES="$ROOT/evals/evidence/requirement-closure-coverage"

cleanup() {
  rm -rf "$TEMP" "$ROOT/evals/evidence/$EVIDENCE_ID" "$ROOT/evals/evidence/$REJECT_EVIDENCE_ID"
}
trap cleanup EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

expect_failure() {
  local expected_exit="$1"
  shift
  local output
  set +e
  output="$("$@" 2>&1)"
  local status=$?
  set -e
  [[ "$status" -eq "$expected_exit" ]] || fail "expected exit $expected_exit, got $status: $output"
  printf '%s\n' "$output"
}

hash_tree() {
  local root="$1" output="$2"
  find "$root" -type f -print0 | sort -z | xargs -0 shasum -a 256 >"$output"
}

hash_tree "$BASELINES" "$TEMP/baselines.before"

"$PYTHON" - "$ROOT" "$TEMP" "$EVIDENCE_ID" "$REJECT_EVIDENCE_ID" <<'PY'
import copy
import hashlib
import json
import sys
from pathlib import Path

import yaml

root = Path(sys.argv[1])
temp = Path(sys.argv[2])
evidence_id = sys.argv[3]
reject_evidence_id = sys.argv[4]

target = {
    "case_id": "att-4845-pre-comment",
    "ticket": "ATT-4845",
    "ticket_sha256": "6e073fc4fb282f49a671f3518ee6c2917893539dac530f9e93cdc9abfccf1d32",
    "repository": {
        "name": "AdCreative-Frontend-V2",
        "commit": "fa6f2234128fee6a357e8086da385cc11794eb76",
    },
    "scorer_rubric_sha256": hashlib.sha256(
        (root / "evals/cases/att-4845-pre-comment/oracle/decisions.json").read_bytes()
    ).hexdigest(),
    "expected_disposition": "BLOCKED",
    "authored_target": {"numerator": 5, "denominator": 5, "unit": "atomic decisions"},
}
control = {
    "case_id": "requirement-closure-ready-control",
    "ticket": "RCTRL-1",
    "ticket_sha256": "599d0bc15e434d84c3f60554ceadf65c96a92eb5491f6a8d7debd6e890bd569f",
    "repository": {
        "name": "AdCreative-Frontend-V2",
        "commit": "fa6f2234128fee6a357e8086da385cc11794eb76",
    },
    "scorer_rubric_sha256": hashlib.sha256(
        (root / "evals/cases/requirement-closure-ready-control/oracle/decisions.json").read_bytes()
    ).hexdigest(),
    "expected_disposition": "READY",
}
rubric_path = root / "docs/improvement-proposals/0.22.0/requirement-closure-coverage/comparison-rubric.yaml"
rubric_hash = hashlib.sha256(rubric_path.read_bytes()).hexdigest()
brief = "docs/improvement-proposals/0.22.0/requirement-closure-coverage/candidate-implementation-brief.md"

def repo_relative(path):
    return path.relative_to(root).as_posix()

def iteration(proposal, evidence):
    return {
        "schema_version": 2,
        "improvement_id": "test-improvement",
        "evidence_root": f"evals/evidence/{evidence}",
        "artifact_root": repo_relative(proposal / "attempts"),
        "claim": "The declared target changes while its fully specified control remains READY.",
        "non_claims": ["No cross-task claim.", "No cross-model or cross-host claim."],
        "origin": {"ticket": "ATT-4845", "observed_on": "2026-08-04", "statement": "isolated fixture"},
        "experiment": {
            "target": target,
            "negative_control": control,
            "skills": {
                "baseline": {
                    "id": "baseline-skill",
                    "path": "skill/recon-triage/SKILL.md",
                    "sha256": "a" * 64,
                    "source_commit": "1" * 40,
                },
                "candidate": {
                    "id": "candidate-skill",
                    "path": "skill/recon-triage/SKILL.md",
                    "binding": "first-candidate-run-per-attempt",
                    "must_differ_from_baseline": True,
                    "control_must_match": True,
                },
            },
            "comparison_rubric": {
                "id": "requirement-closure-comparison-v1",
                "path": repo_relative(rubric_path),
                "sha256": rubric_hash,
            },
        },
        "thresholds": {
            "baseline_runs": 3,
            "minimum_runs_to_compare": {"candidate": 1, "negative_control": 1},
            "minimum_runs_to_accept": {"candidate": 3, "negative_control": 3},
        },
        "acceptance_criteria": {
            "candidate": {
                "artifact_status": "PASS",
                "artifact_exit": 0,
                "disposition_actual": "BLOCKED",
                "disposition_status": "PASS",
                "score": "PASS",
                "score_exit": 0,
                "decision_coverage_status": "PASS",
            },
            "negative_control": {
                "artifact_status": "PASS",
                "artifact_exit": 0,
                "disposition_actual": "READY",
                "disposition_status": "PASS",
                "score": "PASS",
                "score_exit": 0,
                "decision_coverage_status": "PASS",
            },
        },
        "candidate_implementation_brief": brief,
        "raw_scorer_baseline": {
            "numerator": 1,
            "denominator": 3,
            "score": "FAIL",
            "score_exit": 1,
            "statement": "immutable fixture scorer fact",
        },
        "human_calibration": {
            "numerator": 2,
            "denominator": 5,
            "statement": "authored non-four calibration",
            "owner": "test",
        },
        "captures": [],
        "comparisons": [],
        "reviews": [],
    }

for proposal, evidence in ((temp / "proposal", evidence_id), (temp / "reject-proposal", reject_evidence_id)):
    proposal.mkdir(parents=True)
    (proposal / "iteration.yaml").write_text(
        yaml.safe_dump(iteration(proposal, evidence), sort_keys=False), encoding="utf-8"
    )

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def write_run(name, *, role, skill_hash, skill_path="skill/recon-triage/SKILL.md"):
    case = control if role == "control" else target
    disposition = "READY" if role == "control" else "BLOCKED"
    passed = role != "baseline"
    root_path = temp / name
    (root_path / "submission").mkdir(parents=True)
    (root_path / "evaluation").mkdir()
    receipt = {
        "case_id": case["case_id"],
        "ticket": case["ticket"],
        "ticket_sha256": case["ticket_sha256"],
        "repository": case["repository"],
        "submission": "submission/triage.yaml",
        "skill": {
            "path": skill_path,
            "sha256": skill_hash,
            "source_commit": "2" * 40 if role != "baseline" else "1" * 40,
            "source_dirty": False,
        },
    }
    (root_path / "receipt.json").write_text(json.dumps(receipt), encoding="utf-8")
    submission = root_path / "submission/triage.yaml"
    submission.write_text(f"recon: triage\ndisposition: {disposition}\n", encoding="utf-8")
    score = root_path / "evaluation/score.txt"
    score.write_text(f"score: {'PASS' if passed else 'FAIL'}\n", encoding="utf-8")
    total = 0 if role == "control" else 3
    matched = total if passed else 1
    result = {
        "case_id": case["case_id"],
        "ticket": case["ticket"],
        "submission": "submission/triage.yaml",
        "candidate_sha256": digest(submission),
        "score_sha256": digest(score),
        "score": "PASS" if passed else "FAIL",
        "score_exit": 0 if passed else 1,
        "artifact": {"status": "PASS", "verifier_exit": 0},
        "disposition": {"actual": disposition, "expected": disposition, "status": "PASS"},
        "decision_coverage": {
            "matched": matched,
            "total": total,
            "missed": [] if passed else ["missing-one", "missing-two"],
            "overloaded": [],
            "status": "PASS" if passed else "FAIL",
        },
    }
    (root_path / "evaluation/result.json").write_text(json.dumps(result), encoding="utf-8")
    return root_path

for name in ("baseline-one", "baseline-two", "baseline-three"):
    write_run(name, role="baseline", skill_hash="a" * 64)
write_run("candidate", role="candidate", skill_hash="b" * 64)
write_run("wrong-skill", role="candidate", skill_hash="c" * 64, skill_path="skill/other/SKILL.md")
write_run("baseline-as-candidate", role="candidate", skill_hash="a" * 64)
write_run("control", role="control", skill_hash="b" * 64)
write_run("wrong-control-skill", role="control", skill_hash="c" * 64)

def clone_run(source, name):
    destination = temp / name
    import shutil
    shutil.copytree(temp / source, destination)
    return destination

wrong_case = clone_run("candidate", "wrong-case")
receipt = json.loads((wrong_case / "receipt.json").read_text())
result = json.loads((wrong_case / "evaluation/result.json").read_text())
receipt["case_id"] = result["case_id"] = "wrong-target-case"
(wrong_case / "receipt.json").write_text(json.dumps(receipt))
(wrong_case / "evaluation/result.json").write_text(json.dumps(result))

wrong_commit = clone_run("candidate", "wrong-commit")
receipt = json.loads((wrong_commit / "receipt.json").read_text())
receipt["repository"]["commit"] = "f" * 40
(wrong_commit / "receipt.json").write_text(json.dumps(receipt))

wrong_rubric = clone_run("candidate", "wrong-rubric")
result = json.loads((wrong_rubric / "evaluation/result.json").read_text())
result["disposition"] = {"actual": "BLOCKED", "expected": "NEEDS_INFO", "status": "FAIL"}
result["score"] = "FAIL"
result["score_exit"] = 1
(wrong_rubric / "evaluation/result.json").write_text(json.dumps(result))

bad_score_exit = clone_run("candidate", "bad-score-exit")
result = json.loads((bad_score_exit / "evaluation/result.json").read_text())
result["score_exit"] = 1
(bad_score_exit / "evaluation/result.json").write_text(json.dumps(result))

disagreement = clone_run("candidate", "receipt-result-disagreement")
result = json.loads((disagreement / "evaluation/result.json").read_text())
result["ticket"] = "OTHER-1"
(disagreement / "evaluation/result.json").write_text(json.dumps(result))

invalid_control = clone_run("control", "invalid-control")
result = json.loads((invalid_control / "evaluation/result.json").read_text())
result["disposition"] = {"actual": "BLOCKED", "expected": "READY", "status": "FAIL"}
result["score"] = "FAIL"
result["score_exit"] = 1
(invalid_control / "evaluation/result.json").write_text(json.dumps(result))
PY

rail=("$PYTHON" "$ROOT/tools/improvement-cycle.py")

capture_baselines() {
  local proposal="$1"
  "${rail[@]}" capture "$proposal" --role baseline --id baseline-one --from "$TEMP/baseline-one" >/dev/null
  "${rail[@]}" capture "$proposal" --role baseline --id baseline-two --from "$TEMP/baseline-two" >/dev/null
  "${rail[@]}" capture "$proposal" --role baseline --id baseline-three --from "$TEMP/baseline-three" >/dev/null
}

capture_baselines "$PROPOSAL"
state="$("${rail[@]}" state "$PROPOSAL")"
[[ "$state" == *"state: AWAITING_CANDIDATE"* ]] || fail "candidate state was not derived"
[[ "$state" == *"candidate-implementation-brief.md"* ]] || fail "candidate brief was not named"

expect_failure 2 "${rail[@]}" capture "$PROPOSAL" --role baseline --id baseline-four --from "$TEMP/baseline-one" | grep -q "role baseline cannot be captured"
expect_failure 2 "${rail[@]}" capture "$PROPOSAL" --role candidate --id wrong-case --from "$TEMP/wrong-case" | grep -q "declared case/ticket/commit"
expect_failure 2 "${rail[@]}" capture "$PROPOSAL" --role candidate --id wrong-commit --from "$TEMP/wrong-commit" | grep -q "declared case/ticket/commit"
expect_failure 2 "${rail[@]}" capture "$PROPOSAL" --role candidate --id wrong-skill --from "$TEMP/wrong-skill" | grep -q "wrong candidate skill path"
expect_failure 2 "${rail[@]}" capture "$PROPOSAL" --role candidate --id baseline-skill --from "$TEMP/baseline-as-candidate" | grep -q "reuses the baseline skill"
expect_failure 2 "${rail[@]}" capture "$PROPOSAL" --role candidate --id wrong-rubric --from "$TEMP/wrong-rubric" | grep -q "wrong scorer rubric"
expect_failure 2 "${rail[@]}" capture "$PROPOSAL" --role candidate --id bad-score-exit --from "$TEMP/bad-score-exit" | grep -q "score disagrees with score_exit"
expect_failure 2 "${rail[@]}" capture "$PROPOSAL" --role candidate --id disagreement --from "$TEMP/receipt-result-disagreement" | grep -q "receipt/result disagreement"

cp -R "$TEMP/candidate" "$TEMP/symlink-leaf"
mv "$TEMP/symlink-leaf/evaluation/score.txt" "$TEMP/score-real.txt"
ln -s "$TEMP/score-real.txt" "$TEMP/symlink-leaf/evaluation/score.txt"
expect_failure 2 "${rail[@]}" capture "$PROPOSAL" --role candidate --id symlink-leaf --from "$TEMP/symlink-leaf" | grep -q "symlink ancestor or leaf"
ln -s "$TEMP/candidate" "$TEMP/symlink-ancestor"
expect_failure 2 "${rail[@]}" capture "$PROPOSAL" --role candidate --id symlink-ancestor --from "$TEMP/symlink-ancestor" | grep -q "symlink ancestor or leaf"

"${rail[@]}" capture "$PROPOSAL" --role candidate --id candidate-one --from "$TEMP/candidate" >/dev/null
expect_failure 2 "${rail[@]}" capture "$PROPOSAL" --role candidate --id candidate-one --from "$TEMP/candidate" | grep -q "already retained"
expect_failure 2 "${rail[@]}" capture "$PROPOSAL" --role candidate --id candidate-two-early --from "$TEMP/candidate" | grep -q "role candidate cannot be captured"
expect_failure 2 "${rail[@]}" capture "$PROPOSAL" --role negative-control --id invalid-ready --from "$TEMP/invalid-control" | grep -q "artifact PASS, READY/PASS"
expect_failure 2 "${rail[@]}" capture "$PROPOSAL" --role negative-control --id wrong-control-skill --from "$TEMP/wrong-control-skill" | grep -q "wrong candidate skill identity"
"${rail[@]}" capture "$PROPOSAL" --role negative-control --id control-one --from "$TEMP/control" >/dev/null
"${rail[@]}" state "$PROPOSAL" | grep -q "state: READY_TO_COMPARE"

"${rail[@]}" compare "$PROPOSAL" >"$TEMP/compare-one.out"
grep -q "comparison: retained" "$TEMP/compare-one.out" || fail "comparison was not persisted"
grep -q "mechanical_acceptance: FAIL" "$TEMP/compare-one.out" || fail "learning comparison incorrectly passed acceptance"
"${rail[@]}" state "$PROPOSAL" | grep -q "state: AWAITING_REVIEW"
expect_failure 2 "${rail[@]}" compare "$PROPOSAL" | grep -q "AWAITING_REVIEW"
expect_failure 2 "${rail[@]}" review "$PROPOSAL" --decision accept --reviewer tester --reasoning "premature" | grep -q "accept fails closed"

comparison="$PROPOSAL/attempts/attempt-001/comparison.json"
cp "$comparison" "$TEMP/comparison-original.json"
printf ' \n' >>"$comparison"
expect_failure 2 "${rail[@]}" state "$PROPOSAL" | grep -q "comparison hash was tampered"
cp "$TEMP/comparison-original.json" "$comparison"

"${rail[@]}" review "$PROPOSAL" --decision iterate --reviewer tester --reasoning "Learning sample requires a fresh acceptance attempt." >"$TEMP/iterate.out"
grep -q "decision: ITERATE" "$TEMP/iterate.out" || fail "iterate decision was not retained"
grep -q "state: AWAITING_CANDIDATE" "$TEMP/iterate.out" || fail "retry did not route to candidate"
"${rail[@]}" state "$PROPOSAL" | grep -q "capture 3 fresh candidate run(s) for attempt 2"

for n in one two three; do
  "${rail[@]}" capture "$PROPOSAL" --role candidate --id "candidate-two-$n" --from "$TEMP/candidate" >/dev/null
done
"${rail[@]}" state "$PROPOSAL" | grep -q "capture 3 fresh READY/PASS negative-control run(s) for attempt 2"
for n in one two three; do
  "${rail[@]}" capture "$PROPOSAL" --role negative-control --id "control-two-$n" --from "$TEMP/control" >/dev/null
done
"${rail[@]}" compare "$PROPOSAL" >"$TEMP/compare-two.out"
grep -q "mechanical_acceptance: PASS" "$TEMP/compare-two.out" || fail "acceptance comparison did not pass"
"${rail[@]}" review "$PROPOSAL" --decision accept --reviewer tester --reasoning "The bounded semantic target and READY control are satisfied." >"$TEMP/accept.out"
grep -q "decision: ACCEPT" "$TEMP/accept.out" || fail "accept was not retained"
grep -q "state: ACCEPTED" "$TEMP/accept.out" || fail "accepted terminal state was not derived"

"${rail[@]}" report "$PROPOSAL" >/dev/null
"${rail[@]}" report "$PROPOSAL" --check >/dev/null
grep -q "5/5 atomic decisions" "$PROPOSAL/improvement-report.html" || fail "generic non-four target was not rendered"
grep -q "2/5" "$PROPOSAL/improvement-report.html" || fail "generic authored calibration was not rendered"
grep -q "Raw scorer facts" "$PROPOSAL/improvement-report.html" || fail "raw facts section missing"
grep -q "Authored calibration" "$PROPOSAL/improvement-report.html" || fail "calibration section missing"
grep -q "Machine-derived comparison" "$PROPOSAL/improvement-report.html" || fail "comparison section missing"
grep -q "Explicit review decision" "$PROPOSAL/improvement-report.html" || fail "review section missing"
if grep -q "ATT-4845\|/4" "$ROOT/tools/improvement-cycle.py"; then
  fail "renderer contains ATT-specific or hardcoded /4 prose"
fi
printf 'drift' >>"$PROPOSAL/improvement-report.html"
expect_failure 1 "${rail[@]}" report "$PROPOSAL" --check | grep -q "report drift"

capture_baselines "$REJECT_PROPOSAL"
"${rail[@]}" capture "$REJECT_PROPOSAL" --role candidate --id candidate-reject --from "$TEMP/candidate" >/dev/null
"${rail[@]}" capture "$REJECT_PROPOSAL" --role negative-control --id control-reject --from "$TEMP/control" >/dev/null
"${rail[@]}" compare "$REJECT_PROPOSAL" >/dev/null
"${rail[@]}" review "$REJECT_PROPOSAL" --decision reject --reviewer tester --reasoning "The hypothesis is not worth another attempt." >"$TEMP/reject.out"
grep -q "decision: REJECT" "$TEMP/reject.out" || fail "reject was not retained"
grep -q "state: REJECTED" "$TEMP/reject.out" || fail "rejected terminal state was not derived"

cp "$PROPOSAL/iteration.yaml" "$TEMP/bad-rubric-iteration.yaml"
perl -0pi -e 's/fc8bb60c95f51b1232662d13ddc9ca72a4452905ba66751def02813a5cc96c0a/ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff/' "$PROPOSAL/iteration.yaml"
expect_failure 2 "${rail[@]}" state "$PROPOSAL" | grep -q "comparison rubric hash was tampered"
cp "$TEMP/bad-rubric-iteration.yaml" "$PROPOSAL/iteration.yaml"

skill="$ROOT/evals/skills/recon-improvement-loop/SKILL.md"
first_command="$(rg -n "tools/improvement-cycle.py (state|capture|compare|review)" "$skill" | head -1)"
[[ "$first_command" == *"state"* ]] || fail "improvement skill does not route state first"

hash_tree "$BASELINES" "$TEMP/baselines.after"
diff -u "$TEMP/baselines.before" "$TEMP/baselines.after" >/dev/null || fail "retained ATT-4845 baselines changed"
"${rail[@]}" state "$ROOT/docs/improvement-proposals/0.22.0/requirement-closure-coverage" | grep -q "state: ACCEPTED"

echo "improvement-cycle controls: PASS"
