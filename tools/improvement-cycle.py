#!/usr/bin/env python3
"""Retain and derive repository-only, versioned plugin-improvement evidence."""

from __future__ import annotations

import argparse
import hashlib
import html
import json
import os
import re
import shutil
import sys
import tempfile
from datetime import UTC, datetime
from pathlib import Path, PurePosixPath

import yaml


REPO_ROOT = Path(__file__).resolve().parents[1]
ROLES = {"baseline", "candidate", "negative-control"}
DECISIONS = {"accept", "iterate", "reject"}
EVIDENCE_ID = re.compile(r"[a-z0-9]+(?:-[a-z0-9]+)*\Z")
SHA256 = re.compile(r"[0-9a-f]{64}\Z")
OBJECT_ID = re.compile(r"[0-9a-f]{40}\Z")
REQUIRED_FILES = (
    "receipt.json",
    "submission/triage.yaml",
    "evaluation/result.json",
    "evaluation/score.txt",
)
CONTRACT_KEYS = (
    "schema_version",
    "improvement_id",
    "evidence_root",
    "artifact_root",
    "claim",
    "non_claims",
    "origin",
    "experiment",
    "thresholds",
    "acceptance_criteria",
    "candidate_implementation_brief",
    "raw_scorer_baseline",
    "human_calibration",
)


class CycleError(Exception):
    """A stable contract failure for retained improvement evidence."""


def fail(message: str) -> None:
    raise CycleError(message)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def canonical_hash(value: object) -> str:
    payload = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def require_string(value: object, label: str) -> str:
    if not isinstance(value, str) or not value.strip():
        fail(f"{label} must be a non-empty string")
    return value


def require_hash(value: object, label: str) -> str:
    if not isinstance(value, str) or not SHA256.fullmatch(value):
        fail(f"{label} must be a lowercase SHA-256")
    return value


def require_positive(value: object, label: str) -> int:
    if not isinstance(value, int) or isinstance(value, bool) or value < 1:
        fail(f"{label} must be a positive integer")
    return value


def require_keys(value: dict, keys: set[str], label: str) -> None:
    missing = sorted(keys - set(value))
    if missing:
        fail(f"{label} missing field(s): {', '.join(missing)}")


def absolute_without_resolving(path: Path) -> Path:
    return path.expanduser() if path.is_absolute() else Path.cwd() / path.expanduser()


def require_no_symlinks(path: Path, label: str) -> None:
    absolute = absolute_without_resolving(path)
    chain = list(reversed((absolute, *absolute.parents)))
    for component in chain:
        try:
            if component.is_symlink():
                fail(f"{label} has a symlink ancestor or leaf: {component}")
        except OSError as exc:
            fail(f"cannot inspect {label}: {exc}")


def require_regular(path: Path, label: str) -> None:
    require_no_symlinks(path, label)
    if not path.is_file():
        fail(f"{label} must be a regular file")


def require_real_directory(path: Path, label: str) -> Path:
    require_no_symlinks(path, label)
    if not path.is_dir():
        fail(f"{label} must be a real directory")
    return path.resolve(strict=True)


def read_json(path: Path, label: str) -> dict:
    require_regular(path, label)
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        fail(f"{label} is not valid JSON: {exc}")
    if not isinstance(value, dict):
        fail(f"{label} must be a JSON object")
    return value


def read_yaml(path: Path, label: str) -> dict:
    require_regular(path, label)
    try:
        value = yaml.safe_load(path.read_text(encoding="utf-8"))
    except (OSError, yaml.YAMLError) as exc:
        fail(f"{label} is not valid YAML: {exc}")
    if not isinstance(value, dict):
        fail(f"{label} must be an object")
    return value


def relative_repo_path(raw: str, label: str) -> Path:
    require_string(raw, label)
    relative = PurePosixPath(raw)
    if relative.is_absolute() or ".." in relative.parts or "\\" in raw:
        fail(f"{label} must stay inside the repository: {raw}")
    path = REPO_ROOT.joinpath(*relative.parts)
    require_no_symlinks(path, label)
    if REPO_ROOT not in (path, *path.parents):
        fail(f"{label} escapes the repository: {raw}")
    return path


def validate_case_contract(value: object, label: str) -> dict:
    if not isinstance(value, dict):
        fail(f"{label} must be an object")
    require_keys(
        value,
        {
            "case_id",
            "ticket",
            "ticket_sha256",
            "repository",
            "scorer_rubric_sha256",
            "expected_disposition",
        },
        label,
    )
    require_string(value["case_id"], f"{label}.case_id")
    require_string(value["ticket"], f"{label}.ticket")
    require_hash(value["ticket_sha256"], f"{label}.ticket_sha256")
    require_hash(value["scorer_rubric_sha256"], f"{label}.scorer_rubric_sha256")
    repository = value["repository"]
    if not isinstance(repository, dict):
        fail(f"{label}.repository must be an object")
    require_keys(repository, {"name", "commit"}, f"{label}.repository")
    require_string(repository["name"], f"{label}.repository.name")
    if not isinstance(repository["commit"], str) or not OBJECT_ID.fullmatch(repository["commit"]):
        fail(f"{label}.repository.commit must be a full lowercase object ID")
    if value["expected_disposition"] not in {"READY", "BLOCKED", "NEEDS_INFO"}:
        fail(f"{label}.expected_disposition is invalid")
    return value


def validate_declared_case(case: dict, label: str) -> None:
    case_dir = relative_repo_path(f"evals/cases/{case['case_id']}", f"{label} case path")
    manifest = read_json(case_dir / "case.json", f"{label} case.json")
    require_keys(manifest, {"id", "source", "input", "repository", "oracle"}, f"{label} case.json")
    source = manifest["source"]
    input_spec = manifest["input"]
    if not isinstance(source, dict) or not isinstance(input_spec, dict):
        fail(f"{label} case source/input must be objects")
    if manifest["id"] != case["case_id"] or source.get("ticket") != case["ticket"]:
        fail(f"{label} case identity disagrees with iteration contract")
    if input_spec.get("sha256") != case["ticket_sha256"]:
        fail(f"{label} ticket hash disagrees with iteration contract")
    if manifest["repository"] != case["repository"]:
        fail(f"{label} repository disagrees with iteration contract")
    oracle_path = case_dir.joinpath(*PurePosixPath(manifest["oracle"]).parts)
    require_regular(oracle_path, f"{label} scorer rubric")
    if sha256(oracle_path) != case["scorer_rubric_sha256"]:
        fail(f"{label} scorer rubric hash disagrees with iteration contract")
    oracle = read_json(oracle_path, f"{label} scorer rubric")
    if oracle.get("expected_disposition") != case["expected_disposition"]:
        fail(f"{label} expected disposition disagrees with scorer rubric")


def validate_skill_contract(value: object, label: str, *, baseline: bool) -> dict:
    if not isinstance(value, dict):
        fail(f"{label} must be an object")
    if baseline:
        require_keys(value, {"id", "path", "sha256", "source_commit"}, label)
        require_hash(value["sha256"], f"{label}.sha256")
        if not isinstance(value["source_commit"], str) or not OBJECT_ID.fullmatch(value["source_commit"]):
            fail(f"{label}.source_commit must be a full lowercase object ID")
    else:
        require_keys(
            value,
            {"id", "path", "binding", "must_differ_from_baseline", "control_must_match"},
            label,
        )
        if value["binding"] != "first-candidate-run-per-attempt":
            fail(f"{label}.binding must be first-candidate-run-per-attempt")
        if value["must_differ_from_baseline"] is not True or value["control_must_match"] is not True:
            fail(f"{label} must require a distinct candidate and matching control snapshot")
    require_string(value["id"], f"{label}.id")
    require_string(value["path"], f"{label}.path")
    return value


def validate_acceptance(value: object) -> dict:
    if not isinstance(value, dict):
        fail("iteration.yaml acceptance_criteria must be an object")
    expected = {
        "candidate": {
            "artifact_status": "PASS",
            "artifact_exit": 0,
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
    }
    for role, required in expected.items():
        rule = value.get(role)
        if not isinstance(rule, dict):
            fail(f"iteration.yaml acceptance_criteria.{role} must be an object")
        for key, expected_value in required.items():
            if rule.get(key) != expected_value:
                fail(f"iteration.yaml acceptance_criteria.{role}.{key} must be {expected_value!r}")
        if role == "candidate" and rule.get("disposition_actual") not in {"BLOCKED", "NEEDS_INFO"}:
            fail("iteration.yaml candidate acceptance disposition must be BLOCKED or NEEDS_INFO")
    return value


def load_iteration(proposal_dir: Path) -> tuple[Path, dict]:
    proposal = require_real_directory(proposal_dir, "proposal directory")
    path = proposal / "iteration.yaml"
    iteration = read_yaml(path, "iteration.yaml")
    require_keys(iteration, set(CONTRACT_KEYS) | {"captures", "comparisons", "reviews"}, "iteration.yaml")
    if iteration["schema_version"] != 2:
        fail("iteration.yaml schema_version must be 2")
    improvement_id = iteration["improvement_id"]
    if not isinstance(improvement_id, str) or not EVIDENCE_ID.fullmatch(improvement_id):
        fail("iteration.yaml improvement_id must be kebab-case")
    require_string(iteration["claim"], "iteration.yaml claim")
    non_claims = iteration["non_claims"]
    if not isinstance(non_claims, list) or not non_claims:
        fail("iteration.yaml non_claims must be a non-empty list")
    for index, item in enumerate(non_claims, 1):
        require_string(item, f"iteration.yaml non_claims[{index}]")
    for key in ("captures", "comparisons", "reviews"):
        if not isinstance(iteration[key], list):
            fail(f"iteration.yaml {key} must be a list")
    relative_repo_path(iteration["evidence_root"], "iteration evidence_root")
    relative_repo_path(iteration["artifact_root"], "iteration artifact_root")
    brief = relative_repo_path(
        iteration["candidate_implementation_brief"], "candidate implementation brief"
    )
    require_regular(brief, "candidate implementation brief")

    experiment = iteration["experiment"]
    if not isinstance(experiment, dict):
        fail("iteration.yaml experiment must be an object")
    require_keys(
        experiment,
        {"target", "negative_control", "skills", "comparison_rubric"},
        "iteration.yaml experiment",
    )
    target = validate_case_contract(experiment["target"], "iteration target")
    control = validate_case_contract(experiment["negative_control"], "iteration negative_control")
    if target["expected_disposition"] == "READY":
        fail("iteration target must exercise a non-READY disposition")
    if control["expected_disposition"] != "READY":
        fail("iteration negative control must require READY")
    authored = target.get("authored_target")
    if not isinstance(authored, dict):
        fail("iteration target.authored_target must be an object")
    require_keys(authored, {"numerator", "denominator", "unit"}, "iteration target.authored_target")
    require_positive(authored["numerator"], "iteration target authored numerator")
    require_positive(authored["denominator"], "iteration target authored denominator")
    require_string(authored["unit"], "iteration target authored unit")
    validate_declared_case(target, "target")
    validate_declared_case(control, "negative control")

    skills = experiment["skills"]
    if not isinstance(skills, dict):
        fail("iteration.yaml experiment.skills must be an object")
    baseline_skill = validate_skill_contract(skills.get("baseline"), "baseline skill", baseline=True)
    candidate_skill = validate_skill_contract(skills.get("candidate"), "candidate skill", baseline=False)
    if candidate_skill["path"] != baseline_skill["path"]:
        fail("baseline and candidate skill paths must identify the same workflow")

    rubric = experiment["comparison_rubric"]
    if not isinstance(rubric, dict):
        fail("iteration.yaml comparison_rubric must be an object")
    require_keys(rubric, {"id", "path", "sha256"}, "iteration.yaml comparison_rubric")
    require_string(rubric["id"], "iteration.yaml comparison_rubric.id")
    require_hash(rubric["sha256"], "iteration.yaml comparison_rubric.sha256")
    rubric_path = relative_repo_path(rubric["path"], "comparison rubric path")
    rubric_document = read_yaml(rubric_path, "comparison rubric")
    if sha256(rubric_path) != rubric["sha256"]:
        fail("comparison rubric hash was tampered")
    if rubric_document.get("id") != rubric["id"]:
        fail("comparison rubric ID disagrees with iteration contract")

    thresholds = iteration["thresholds"]
    if not isinstance(thresholds, dict):
        fail("iteration.yaml thresholds must be an object")
    require_keys(
        thresholds,
        {"baseline_runs", "minimum_runs_to_compare", "minimum_runs_to_accept"},
        "iteration.yaml thresholds",
    )
    require_positive(thresholds["baseline_runs"], "thresholds.baseline_runs")
    for group in ("minimum_runs_to_compare", "minimum_runs_to_accept"):
        values = thresholds[group]
        if not isinstance(values, dict):
            fail(f"thresholds.{group} must be an object")
        for role in ("candidate", "negative_control"):
            require_positive(values.get(role), f"thresholds.{group}.{role}")
    for role in ("candidate", "negative_control"):
        if thresholds["minimum_runs_to_accept"][role] < thresholds["minimum_runs_to_compare"][role]:
            fail(f"acceptance threshold for {role} must be at least its comparison threshold")
    validate_acceptance(iteration["acceptance_criteria"])

    raw = iteration["raw_scorer_baseline"]
    calibration = iteration["human_calibration"]
    for value, label in ((raw, "raw_scorer_baseline"), (calibration, "human_calibration")):
        if not isinstance(value, dict):
            fail(f"iteration.yaml {label} must be an object")
        require_positive(value.get("numerator"), f"iteration.yaml {label}.numerator")
        require_positive(value.get("denominator"), f"iteration.yaml {label}.denominator")
        require_string(value.get("statement"), f"iteration.yaml {label}.statement")
    if raw.get("score") not in {"PASS", "FAIL"} or raw.get("score_exit") not in {0, 1}:
        fail("iteration.yaml raw_scorer_baseline must retain score and score_exit")
    if (raw["score"] == "PASS") != (raw["score_exit"] == 0):
        fail("iteration.yaml raw scorer score disagrees with exit")
    return path, iteration


def experiment_contract_hash(iteration: dict) -> str:
    return canonical_hash({key: iteration[key] for key in CONTRACT_KEYS})


def validate_scored_run(run_arg: Path) -> dict:
    run = require_real_directory(run_arg, "run directory")
    paths = {name: run.joinpath(*name.split("/")) for name in REQUIRED_FILES}
    for name, path in paths.items():
        require_regular(path, f"run {name}")
    receipt = read_json(paths["receipt.json"], "run receipt.json")
    result = read_json(paths["evaluation/result.json"], "run evaluation/result.json")
    require_keys(
        receipt,
        {"submission", "case_id", "ticket", "ticket_sha256", "repository", "skill"},
        "run receipt.json",
    )
    require_keys(
        result,
        {
            "case_id",
            "ticket",
            "submission",
            "candidate_sha256",
            "score_sha256",
            "score",
            "score_exit",
            "artifact",
            "disposition",
            "decision_coverage",
        },
        "run evaluation/result.json",
    )
    if receipt["submission"] != "submission/triage.yaml":
        fail("run receipt submission must be submission/triage.yaml")
    for field in ("case_id", "ticket", "submission"):
        if result[field] != receipt[field]:
            fail(f"run receipt/result disagreement for {field}")
    repository = receipt["repository"]
    skill = receipt["skill"]
    if not isinstance(repository, dict) or not isinstance(skill, dict):
        fail("run receipt repository and skill must be objects")
    require_keys(repository, {"name", "commit"}, "run receipt repository")
    require_keys(skill, {"path", "sha256", "source_commit", "source_dirty"}, "run receipt skill")
    require_hash(receipt["ticket_sha256"], "run receipt ticket_sha256")
    require_hash(skill["sha256"], "run receipt skill.sha256")
    if not isinstance(repository["commit"], str) or not OBJECT_ID.fullmatch(repository["commit"]):
        fail("run receipt repository.commit must be a full object ID")
    if not isinstance(skill["source_commit"], str) or not OBJECT_ID.fullmatch(skill["source_commit"]):
        fail("run receipt skill.source_commit must be a full object ID")
    if not isinstance(skill["source_dirty"], bool):
        fail("run receipt skill.source_dirty must be boolean")

    for field in ("candidate_sha256", "score_sha256"):
        require_hash(result[field], f"run evaluation/result.json {field}")
    hashes = {name: sha256(path) for name, path in paths.items()}
    if result["candidate_sha256"] != hashes["submission/triage.yaml"]:
        fail("run evaluation result candidate hash does not match submission")
    if result["score_sha256"] != hashes["evaluation/score.txt"]:
        fail("run evaluation result score hash does not match score.txt")

    artifact = result["artifact"]
    disposition = result["disposition"]
    coverage = result["decision_coverage"]
    if not isinstance(artifact, dict) or not isinstance(disposition, dict) or not isinstance(coverage, dict):
        fail("run evaluation result components must be objects")
    require_keys(artifact, {"status", "verifier_exit"}, "run evaluation artifact")
    require_keys(disposition, {"actual", "expected", "status"}, "run evaluation disposition")
    require_keys(
        coverage,
        {"matched", "total", "missed", "overloaded", "status"},
        "run evaluation decision coverage",
    )
    if artifact["status"] not in {"PASS", "FAIL"} or not isinstance(artifact["verifier_exit"], int):
        fail("run evaluation artifact status/exit is invalid")
    if (artifact["status"] == "PASS") != (artifact["verifier_exit"] == 0):
        fail("run evaluation artifact status disagrees with verifier exit")
    if disposition["status"] not in {"PASS", "FAIL", "NOT_EVALUATED"}:
        fail("run evaluation disposition status is invalid")
    if disposition["status"] == "NOT_EVALUATED":
        if artifact["status"] != "FAIL" or disposition["actual"] is not None:
            fail("run evaluation disposition disagrees with artifact failure")
    else:
        if disposition["actual"] not in {"READY", "BLOCKED", "NEEDS_INFO"}:
            fail("run evaluation disposition actual value is invalid")
        if (disposition["actual"] == disposition["expected"]) != (disposition["status"] == "PASS"):
            fail("run evaluation disposition status disagrees with actual/expected")
    if coverage["status"] not in {"PASS", "FAIL", "NOT_EVALUATED"}:
        fail("run evaluation decision coverage status is invalid")
    if not isinstance(coverage["matched"], int) or not isinstance(coverage["total"], int):
        fail("run evaluation decision coverage counts are invalid")
    if not 0 <= coverage["matched"] <= coverage["total"]:
        fail("run evaluation decision coverage matched is out of range")
    if not isinstance(coverage["missed"], list) or not isinstance(coverage["overloaded"], list):
        fail("run evaluation decision coverage lists are invalid")
    if coverage["status"] == "PASS" and (
        coverage["matched"] != coverage["total"] or coverage["missed"]
    ):
        fail("run evaluation decision coverage PASS disagrees with counts")
    if coverage["status"] == "FAIL" and coverage["matched"] == coverage["total"] and not coverage["missed"]:
        fail("run evaluation decision coverage FAIL disagrees with counts")

    if result["score"] not in {"PASS", "FAIL"} or result["score_exit"] not in {0, 1}:
        fail("run evaluation result is not a retained SCORED outcome")
    expected_pass = (
        artifact["status"] == "PASS"
        and disposition["status"] == "PASS"
        and coverage["status"] == "PASS"
    )
    if (result["score"] == "PASS") != (result["score_exit"] == 0):
        fail("run evaluation score disagrees with score_exit")
    if (result["score"] == "PASS") != expected_pass:
        fail("run evaluation score/exit disagrees with component results")
    return {"receipt": receipt, "result": result, "paths": paths, "hashes": hashes}


def capture_entries(iteration: dict) -> list[dict]:
    seen_ids: set[str] = set()
    seen_paths: set[str] = set()
    checked: list[dict] = []
    for index, entry in enumerate(iteration["captures"], 1):
        if not isinstance(entry, dict):
            fail(f"iteration capture {index} must be an object")
        require_keys(entry, {"id", "role", "path", "manifest_sha256"}, f"iteration capture {index}")
        evidence_id = entry["id"]
        role = entry["role"]
        if not isinstance(evidence_id, str) or not EVIDENCE_ID.fullmatch(evidence_id):
            fail(f"iteration capture {index} has invalid id")
        if evidence_id in seen_ids:
            fail(f"iteration capture id is duplicated: {evidence_id}")
        if entry["path"] in seen_paths:
            fail(f"iteration capture path is duplicated: {entry['path']}")
        seen_ids.add(evidence_id)
        seen_paths.add(entry["path"])
        if role not in ROLES:
            fail(f"iteration capture {evidence_id} has invalid role: {role}")
        require_hash(entry["manifest_sha256"], f"iteration capture {evidence_id} manifest hash")
        if role == "baseline":
            if "attempt" in entry:
                fail(f"baseline capture {evidence_id} must not have an attempt")
        elif not isinstance(entry.get("attempt"), int) or entry["attempt"] < 1:
            fail(f"iteration capture {evidence_id} must have a positive attempt")
        checked.append(entry)
    return checked


def identity_matches(receipt: dict, case: dict) -> bool:
    return (
        receipt["case_id"] == case["case_id"]
        and receipt["ticket"] == case["ticket"]
        and receipt["ticket_sha256"] == case["ticket_sha256"]
        and receipt["repository"] == case["repository"]
    )


def validate_capture(iteration: dict, entry: dict) -> dict:
    root = relative_repo_path(iteration["evidence_root"], "iteration evidence_root")
    expected_path = root / entry["id"]
    actual_path = relative_repo_path(entry["path"], f"capture {entry['id']} path")
    if actual_path != expected_path:
        fail(f"capture {entry['id']} path does not match evidence root")
    manifest_path = actual_path / "manifest.json"
    manifest = read_json(manifest_path, f"capture {entry['id']} manifest")
    if sha256(manifest_path) != entry["manifest_sha256"]:
        fail(f"capture {entry['id']} manifest hash was tampered")
    require_keys(manifest, {"schema_version", "evidence_id", "role", "files"}, f"capture {entry['id']} manifest")
    if manifest["evidence_id"] != entry["id"] or manifest["role"] != entry["role"]:
        fail(f"capture {entry['id']} manifest identity does not match iteration")
    if entry["role"] == "baseline":
        if manifest["schema_version"] != 1:
            fail(f"baseline capture {entry['id']} must preserve manifest schema 1")
    else:
        if manifest["schema_version"] != 2:
            fail(f"capture {entry['id']} must use manifest schema 2")
        require_keys(
            manifest,
            {"attempt", "contract_sha256", "comparison_rubric"},
            f"capture {entry['id']} manifest",
        )
        if manifest["attempt"] != entry["attempt"]:
            fail(f"capture {entry['id']} attempt disagrees with manifest")
        if manifest["contract_sha256"] != experiment_contract_hash(iteration):
            fail(f"capture {entry['id']} comparison contract does not match")
        if manifest["comparison_rubric"] != iteration["experiment"]["comparison_rubric"]:
            fail(f"capture {entry['id']} comparison rubric does not match")
    if set(manifest["files"]) != set(REQUIRED_FILES):
        fail(f"capture {entry['id']} manifest must list only the required artifacts")
    for name in REQUIRED_FILES:
        path = actual_path.joinpath(*name.split("/"))
        require_regular(path, f"capture {entry['id']} {name}")
        expected_hash = manifest["files"][name]
        require_hash(expected_hash, f"capture {entry['id']} manifest hash for {name}")
        if sha256(path) != expected_hash:
            fail(f"capture {entry['id']} {name} hash was tampered")
    run = validate_scored_run(actual_path)
    target = iteration["experiment"]["target"]
    control = iteration["experiment"]["negative_control"]
    receipt = run["receipt"]
    result = run["result"]
    if entry["role"] in {"baseline", "candidate"}:
        if not identity_matches(receipt, target):
            fail(f"{entry['role']} {entry['id']} does not match the declared target case/ticket/commit")
        if result["disposition"]["expected"] != target["expected_disposition"]:
            fail(f"{entry['role']} {entry['id']} disposition contract is wrong")
    else:
        if not identity_matches(receipt, control):
            fail(f"negative-control {entry['id']} does not match its declared case/ticket/commit")
        criteria = iteration["acceptance_criteria"]["negative_control"]
        if not result_matches_criteria(result, criteria):
            fail(
                f"negative-control {entry['id']} must retain artifact PASS, READY/PASS, "
                "and score PASS with exit 0"
            )
    if entry["role"] == "baseline":
        baseline = iteration["experiment"]["skills"]["baseline"]
        skill = receipt["skill"]
        if (
            skill["path"] != baseline["path"]
            or skill["sha256"] != baseline["sha256"]
            or skill["source_commit"] != baseline["source_commit"]
        ):
            fail(f"baseline {entry['id']} skill identity does not match the contract")
        raw = iteration["raw_scorer_baseline"]
        coverage = result["decision_coverage"]
        if (
            coverage["matched"] != raw["numerator"]
            or coverage["total"] != raw["denominator"]
            or result["score"] != raw["score"]
            or result["score_exit"] != raw["score_exit"]
        ):
            fail(f"baseline {entry['id']} no longer matches the immutable raw scorer facts")
    else:
        candidate = iteration["experiment"]["skills"]["candidate"]
        if receipt["skill"]["path"] != candidate["path"]:
            fail(f"{entry['role']} {entry['id']} uses the wrong candidate skill path")
        if receipt["skill"]["sha256"] == iteration["experiment"]["skills"]["baseline"]["sha256"]:
            fail(f"{entry['role']} {entry['id']} reuses the baseline skill instead of the candidate")
    return {"entry": entry, **run}


def validated_evidence(iteration: dict) -> list[dict]:
    captures = [validate_capture(iteration, entry) for entry in capture_entries(iteration)]
    by_attempt: dict[int, list[dict]] = {}
    for capture in captures:
        attempt = capture["entry"].get("attempt")
        if attempt is not None:
            by_attempt.setdefault(attempt, []).append(capture)
    for attempt, values in by_attempt.items():
        candidates = [item for item in values if item["entry"]["role"] == "candidate"]
        controls = [item for item in values if item["entry"]["role"] == "negative-control"]
        if controls and not candidates:
            fail(f"attempt {attempt} has a control without a candidate binding")
        if candidates:
            bound = candidates[0]["receipt"]["skill"]
            for item in candidates[1:] + controls:
                if item["receipt"]["skill"] != bound:
                    fail(f"attempt {attempt} candidate/control skill identity disagreement")
    return captures


def result_matches_criteria(result: dict, criteria: dict) -> bool:
    return (
        result["artifact"]["status"] == criteria["artifact_status"]
        and result["artifact"]["verifier_exit"] == criteria["artifact_exit"]
        and result["disposition"]["actual"] == criteria["disposition_actual"]
        and result["disposition"]["status"] == criteria["disposition_status"]
        and result["score"] == criteria["score"]
        and result["score_exit"] == criteria["score_exit"]
        and result["decision_coverage"]["status"] == criteria["decision_coverage_status"]
    )


def artifact_entries(iteration: dict, kind: str) -> list[dict]:
    collection = iteration["comparisons" if kind == "comparison" else "reviews"]
    root = relative_repo_path(iteration["artifact_root"], "iteration artifact_root")
    seen: set[int] = set()
    checked: list[dict] = []
    filename = f"{kind}.json"
    for index, entry in enumerate(collection, 1):
        if not isinstance(entry, dict):
            fail(f"iteration {kind} {index} must be an object")
        require_keys(entry, {"attempt", "path", "sha256"}, f"iteration {kind} {index}")
        attempt = entry["attempt"]
        if not isinstance(attempt, int) or attempt < 1 or attempt in seen:
            fail(f"iteration {kind} attempt is invalid or duplicated: {attempt}")
        seen.add(attempt)
        require_hash(entry["sha256"], f"iteration {kind} {attempt} hash")
        expected = root / f"attempt-{attempt:03d}" / filename
        actual = relative_repo_path(entry["path"], f"iteration {kind} {attempt} path")
        if actual != expected:
            fail(f"iteration {kind} {attempt} path does not match artifact root")
        document = read_json(actual, f"attempt {attempt} {kind}")
        if sha256(actual) != entry["sha256"]:
            fail(f"attempt {attempt} {kind} hash was tampered")
        if document.get("attempt") != attempt or document.get("improvement_id") != iteration["improvement_id"]:
            fail(f"attempt {attempt} {kind} identity disagrees with iteration")
        if document.get("contract_sha256") != experiment_contract_hash(iteration):
            fail(f"attempt {attempt} {kind} comparison contract does not match")
        checked.append({"entry": entry, "document": document})
    return checked


def validated_artifacts(iteration: dict) -> tuple[dict[int, dict], dict[int, dict]]:
    comparisons = {item["entry"]["attempt"]: item for item in artifact_entries(iteration, "comparison")}
    reviews = {item["entry"]["attempt"]: item for item in artifact_entries(iteration, "review")}
    for attempt, review in reviews.items():
        if attempt not in comparisons:
            fail(f"attempt {attempt} review has no comparison")
        document = review["document"]
        if document.get("decision") not in DECISIONS:
            fail(f"attempt {attempt} review decision is invalid")
        if document.get("comparison_sha256") != comparisons[attempt]["entry"]["sha256"]:
            fail(f"attempt {attempt} review disagrees with comparison")
        require_string(document.get("reviewer"), f"attempt {attempt} reviewer")
        require_string(document.get("reasoning"), f"attempt {attempt} reviewer reasoning")
        if document["decision"] == "accept" and not comparisons[attempt]["document"]["mechanical_acceptance"]["satisfied"]:
            fail(f"attempt {attempt} accept decision violates the mechanical acceptance matrix")
    return comparisons, reviews


def attempt_values(captures: list[dict], attempt: int, role: str) -> list[dict]:
    return [
        item
        for item in captures
        if item["entry"].get("attempt") == attempt and item["entry"]["role"] == role
    ]


def current_attempt(reviews: dict[int, dict]) -> tuple[int, str | None]:
    if not reviews:
        return 1, None
    attempts = sorted(reviews)
    if attempts != list(range(1, attempts[-1] + 1)):
        fail("review attempts must be contiguous")
    last = reviews[attempts[-1]]["document"]["decision"]
    return (attempts[-1] + 1, last) if last == "iterate" else (attempts[-1], last)


def derive_state(
    iteration: dict,
    captures: list[dict],
    comparisons: dict[int, dict],
    reviews: dict[int, dict],
) -> dict:
    baselines = [item for item in captures if item["entry"]["role"] == "baseline"]
    baseline_minimum = iteration["thresholds"]["baseline_runs"]
    attempt, last_decision = current_attempt(reviews)
    brief = iteration["candidate_implementation_brief"]
    if len(baselines) < baseline_minimum:
        state = "AWAITING_BASELINES"
        action = f"capture {baseline_minimum - len(baselines)} additional scored baseline run(s)"
    elif last_decision == "accept":
        state, action = "ACCEPTED", "none — the bounded experiment was accepted"
    elif last_decision == "reject":
        state, action = "REJECTED", "none — the bounded experiment was rejected"
    elif attempt in comparisons:
        if attempt in reviews:
            fail(f"attempt {attempt} has a review but did not advance or terminate")
        state = "AWAITING_REVIEW"
        action = (
            f"review attempt {attempt}: run review with accept, iterate, or reject and retained reasoning"
        )
    else:
        threshold_group = "minimum_runs_to_compare" if attempt == 1 else "minimum_runs_to_accept"
        required = iteration["thresholds"][threshold_group]
        candidates = attempt_values(captures, attempt, "candidate")
        controls = attempt_values(captures, attempt, "negative-control")
        if len(candidates) < required["candidate"]:
            missing = required["candidate"] - len(candidates)
            state = "AWAITING_CANDIDATE"
            action = (
                f"implement the candidate from {brief}; then capture {missing} fresh candidate run(s) "
                f"for attempt {attempt}"
            )
        elif len(controls) < required["negative_control"]:
            missing = required["negative_control"] - len(controls)
            state = "AWAITING_NEGATIVE_CONTROL"
            action = (
                f"capture {missing} fresh READY/PASS negative-control run(s) for attempt {attempt} "
                f"using case {iteration['experiment']['negative_control']['case_id']}"
            )
        else:
            state = "READY_TO_COMPARE"
            action = f"run compare for attempt {attempt}; it will retain an immutable comparison artifact"
    counts = {
        "baseline": len(baselines),
        "candidate": len(attempt_values(captures, attempt, "candidate")),
        "negative-control": len(attempt_values(captures, attempt, "negative-control")),
    }
    return {
        "improvement_id": iteration["improvement_id"],
        "state": state,
        "next_action": action,
        "attempt": attempt,
        "last_decision": last_decision,
        "counts": counts,
        "thresholds": iteration["thresholds"],
        "candidate_implementation_brief": brief,
    }


def write_iteration(path: Path, iteration: dict) -> None:
    payload = yaml.safe_dump(iteration, sort_keys=False, allow_unicode=True)
    temporary = path.with_name(f".{path.name}.tmp")
    require_no_symlinks(temporary, "iteration temporary path")
    if temporary.exists():
        fail(f"refusing to reuse iteration temporary path: {temporary.name}")
    temporary.write_text(payload, encoding="utf-8")
    os.replace(temporary, path)


def write_immutable_json(path: Path, document: dict, label: str) -> str:
    require_no_symlinks(path, label)
    if path.exists():
        fail(f"refusing to overwrite retained {label}: {path.relative_to(REPO_ROOT)}")
    path.parent.mkdir(parents=True, exist_ok=True)
    require_no_symlinks(path.parent, f"{label} parent")
    temporary = path.with_name(f".{path.name}.tmp")
    require_no_symlinks(temporary, f"{label} temporary path")
    if temporary.exists():
        fail(f"refusing to reuse {label} temporary path")
    temporary.write_text(json.dumps(document, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    os.replace(temporary, path)
    return sha256(path)


def load_all(iteration: dict) -> tuple[list[dict], dict[int, dict], dict[int, dict]]:
    captures = validated_evidence(iteration)
    comparisons, reviews = validated_artifacts(iteration)
    for attempt in comparisons:
        if not attempt_values(captures, attempt, "candidate") or not attempt_values(
            captures, attempt, "negative-control"
        ):
            fail(f"attempt {attempt} comparison has incomplete capture roles")
    return captures, comparisons, reviews


def command_capture(args: argparse.Namespace) -> int:
    iteration_path, iteration = load_iteration(Path(args.proposal))
    captures, comparisons, reviews = load_all(iteration)
    state = derive_state(iteration, captures, comparisons, reviews)
    if args.role not in ROLES:
        fail(f"invalid role: {args.role}")
    if not EVIDENCE_ID.fullmatch(args.evidence_id):
        fail("evidence id must be kebab-case")
    if any(item["entry"]["id"] == args.evidence_id for item in captures):
        fail(f"evidence id already retained: {args.evidence_id}")
    allowed = {
        "baseline": "AWAITING_BASELINES",
        "candidate": "AWAITING_CANDIDATE",
        "negative-control": "AWAITING_NEGATIVE_CONTROL",
    }
    if state["state"] != allowed[args.role]:
        fail(
            f"role {args.role} cannot be captured while state is {state['state']}: "
            f"{state['next_action']}"
        )
    run = validate_scored_run(Path(args.source))
    role_case = (
        iteration["experiment"]["negative_control"]
        if args.role == "negative-control"
        else iteration["experiment"]["target"]
    )
    if not identity_matches(run["receipt"], role_case):
        fail(f"{args.role} source does not match the declared case/ticket/commit")
    if run["result"]["disposition"]["expected"] != role_case["expected_disposition"]:
        fail(f"{args.role} source uses the wrong scorer rubric/disposition contract")
    if args.role == "baseline":
        baseline = iteration["experiment"]["skills"]["baseline"]
        skill = run["receipt"]["skill"]
        if skill["path"] != baseline["path"] or skill["sha256"] != baseline["sha256"]:
            fail("baseline source uses the wrong baseline skill")
        attempt = None
    else:
        attempt = state["attempt"]
        candidate = iteration["experiment"]["skills"]["candidate"]
        skill = run["receipt"]["skill"]
        if skill["path"] != candidate["path"]:
            fail(f"{args.role} source uses the wrong candidate skill path")
        if skill["sha256"] == iteration["experiment"]["skills"]["baseline"]["sha256"]:
            fail(f"{args.role} source reuses the baseline skill")
        bound = attempt_values(captures, attempt, "candidate")
        if bound and skill != bound[0]["receipt"]["skill"]:
            fail(f"attempt {attempt} source uses the wrong candidate skill identity")
        if args.role == "negative-control":
            criteria = iteration["acceptance_criteria"]["negative_control"]
            if not result_matches_criteria(run["result"], criteria):
                fail(
                    "negative-control source must retain artifact PASS, READY/PASS, "
                    "and score PASS with exit 0"
                )

    root = relative_repo_path(iteration["evidence_root"], "iteration evidence_root")
    destination = root / args.evidence_id
    require_no_symlinks(destination, "retained evidence destination")
    if destination.exists():
        fail(f"refusing to overwrite retained evidence: {destination.relative_to(REPO_ROOT)}")
    root.mkdir(parents=True, exist_ok=True)
    require_no_symlinks(root, "iteration evidence root")
    with tempfile.TemporaryDirectory(prefix=f".{args.evidence_id}-", dir=root) as temporary_name:
        temporary = Path(temporary_name)
        for name in REQUIRED_FILES:
            target = temporary.joinpath(*name.split("/"))
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(run["paths"][name], target)
            if sha256(target) != run["hashes"][name]:
                fail(f"source changed while capturing {name}")
        manifest = {
            "schema_version": 1 if args.role == "baseline" else 2,
            "evidence_id": args.evidence_id,
            "role": args.role,
            "files": run["hashes"],
        }
        if attempt is not None:
            manifest.update(
                {
                    "attempt": attempt,
                    "contract_sha256": experiment_contract_hash(iteration),
                    "comparison_rubric": iteration["experiment"]["comparison_rubric"],
                }
            )
        manifest_path = temporary / "manifest.json"
        manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        os.replace(temporary, destination)
    entry = {
        "id": args.evidence_id,
        "role": args.role,
        "path": str(destination.relative_to(REPO_ROOT)),
        "manifest_sha256": sha256(destination / "manifest.json"),
    }
    if attempt is not None:
        entry["attempt"] = attempt
    iteration["captures"].append(entry)
    write_iteration(iteration_path, iteration)
    print(f"captured: {args.evidence_id} ({args.role})")
    print(f"attempt: {attempt if attempt is not None else 'baseline'}")
    print(f"evidence: {entry['path']}")
    return 0


def command_state(args: argparse.Namespace) -> int:
    _, iteration = load_iteration(Path(args.proposal))
    captures, comparisons, reviews = load_all(iteration)
    state = derive_state(iteration, captures, comparisons, reviews)
    if args.json:
        print(json.dumps(state, indent=2, sort_keys=True))
    else:
        print(f"improvement: {state['improvement_id']}")
        print(f"state: {state['state']}")
        print(f"attempt: {state['attempt']}")
        print("retained: " + ", ".join(f"{role}={state['counts'][role]}" for role in sorted(ROLES)))
        print(f"candidate_brief: {state['candidate_implementation_brief']}")
        print(f"next_action: {state['next_action']}")
    return 0


def comparison_rows(captures: list[dict], attempt: int | None = None) -> list[dict]:
    rows = []
    for capture in captures:
        entry_attempt = capture["entry"].get("attempt")
        if attempt is not None and capture["entry"]["role"] != "baseline" and entry_attempt != attempt:
            continue
        result = capture["result"]
        coverage = result["decision_coverage"]
        disposition = result["disposition"]
        rows.append(
            {
                "id": capture["entry"]["id"],
                "role": capture["entry"]["role"],
                "attempt": entry_attempt,
                "case_id": capture["receipt"]["case_id"],
                "ticket": capture["receipt"]["ticket"],
                "repository_commit": capture["receipt"]["repository"]["commit"],
                "skill_sha256": capture["receipt"]["skill"]["sha256"],
                "artifact": result["artifact"]["status"],
                "disposition_actual": disposition.get("actual"),
                "disposition_status": disposition.get("status"),
                "score": result["score"],
                "score_exit": result["score_exit"],
                "coverage_matched": coverage["matched"],
                "coverage_total": coverage["total"],
                "coverage_status": coverage["status"],
                "missed": coverage.get("missed", []),
                "path": capture["entry"]["path"],
            }
        )
    return rows


def mechanical_matrix(iteration: dict, captures: list[dict], attempt: int) -> dict:
    candidates = attempt_values(captures, attempt, "candidate")
    controls = attempt_values(captures, attempt, "negative-control")
    thresholds = iteration["thresholds"]["minimum_runs_to_accept"]
    criteria = iteration["acceptance_criteria"]
    checks = {
        "candidate_run_count": len(candidates) >= thresholds["candidate"],
        "negative_control_run_count": len(controls) >= thresholds["negative_control"],
        "candidate_results": bool(candidates)
        and all(result_matches_criteria(item["result"], criteria["candidate"]) for item in candidates),
        "negative_control_results": bool(controls)
        and all(result_matches_criteria(item["result"], criteria["negative_control"]) for item in controls),
    }
    return {
        "required_runs": thresholds,
        "observed_runs": {"candidate": len(candidates), "negative_control": len(controls)},
        "checks": checks,
        "satisfied": all(checks.values()),
    }


def command_compare(args: argparse.Namespace) -> int:
    iteration_path, iteration = load_iteration(Path(args.proposal))
    captures, comparisons, reviews = load_all(iteration)
    state = derive_state(iteration, captures, comparisons, reviews)
    if state["state"] != "READY_TO_COMPARE":
        fail(f"cannot compare while state is {state['state']}: {state['next_action']}")
    attempt = state["attempt"]
    matrix = mechanical_matrix(iteration, captures, attempt)
    document = {
        "schema_version": 1,
        "improvement_id": iteration["improvement_id"],
        "attempt": attempt,
        "created_at": datetime.now(UTC).isoformat(),
        "contract_sha256": experiment_contract_hash(iteration),
        "comparison_rubric": iteration["experiment"]["comparison_rubric"],
        "minimum_runs_to_compare": iteration["thresholds"]["minimum_runs_to_compare"],
        "runs": comparison_rows(captures, attempt),
        "mechanical_acceptance": matrix,
        "semantic_review_required": True,
    }
    root = relative_repo_path(iteration["artifact_root"], "iteration artifact_root")
    path = root / f"attempt-{attempt:03d}" / "comparison.json"
    digest = write_immutable_json(path, document, f"attempt {attempt} comparison")
    entry = {"attempt": attempt, "path": str(path.relative_to(REPO_ROOT)), "sha256": digest}
    iteration["comparisons"].append(entry)
    write_iteration(iteration_path, iteration)
    print(f"comparison: retained — {entry['path']}")
    print(f"sha256: {digest}")
    print(f"mechanical_acceptance: {'PASS' if matrix['satisfied'] else 'FAIL'}")
    print("next_action: record an explicit semantic review decision")
    return 0


def command_review(args: argparse.Namespace) -> int:
    iteration_path, iteration = load_iteration(Path(args.proposal))
    captures, comparisons, reviews = load_all(iteration)
    state = derive_state(iteration, captures, comparisons, reviews)
    if state["state"] != "AWAITING_REVIEW":
        fail(f"cannot review while state is {state['state']}: {state['next_action']}")
    decision = args.decision.casefold()
    if decision not in DECISIONS:
        fail(f"review decision must be one of: {', '.join(sorted(DECISIONS))}")
    reviewer = require_string(args.reviewer, "reviewer")
    reasoning = require_string(args.reasoning, "reviewer reasoning")
    attempt = state["attempt"]
    comparison = comparisons[attempt]
    mechanical = comparison["document"]["mechanical_acceptance"]
    if decision == "accept" and not mechanical["satisfied"]:
        failed = ", ".join(name for name, passed in mechanical["checks"].items() if not passed)
        fail(f"accept fails closed because the mechanical acceptance matrix is not satisfied: {failed}")
    document = {
        "schema_version": 1,
        "improvement_id": iteration["improvement_id"],
        "attempt": attempt,
        "created_at": datetime.now(UTC).isoformat(),
        "contract_sha256": experiment_contract_hash(iteration),
        "comparison_sha256": comparison["entry"]["sha256"],
        "decision": decision,
        "reviewer": reviewer,
        "reasoning": reasoning,
        "mechanical_acceptance_satisfied": mechanical["satisfied"],
    }
    root = relative_repo_path(iteration["artifact_root"], "iteration artifact_root")
    path = root / f"attempt-{attempt:03d}" / "review.json"
    digest = write_immutable_json(path, document, f"attempt {attempt} review")
    entry = {"attempt": attempt, "path": str(path.relative_to(REPO_ROOT)), "sha256": digest}
    iteration["reviews"].append(entry)
    write_iteration(iteration_path, iteration)
    captures, comparisons, reviews = load_all(iteration)
    next_state = derive_state(iteration, captures, comparisons, reviews)
    print(f"review: retained — {entry['path']}")
    print(f"decision: {decision.upper()}")
    print(f"state: {next_state['state']}")
    print(f"next_action: {next_state['next_action']}")
    return 0


def fraction(value: dict) -> str:
    return f"{value['numerator']}/{value['denominator']}"


def report_link(proposal: Path, repository_relative: str) -> str:
    return Path(os.path.relpath(REPO_ROOT / repository_relative, proposal)).as_posix()


def render_report(
    proposal: Path,
    iteration: dict,
    captures: list[dict],
    comparisons: dict[int, dict],
    reviews: dict[int, dict],
) -> str:
    state = derive_state(iteration, captures, comparisons, reviews)
    rows = comparison_rows(captures)
    evidence_rows = "\n".join(
        "<tr>"
        + "".join(
            f"<td>{html.escape(str(row[key]) if row[key] is not None else '—')}</td>"
            for key in (
                "id",
                "role",
                "attempt",
                "case_id",
                "ticket",
                "artifact",
                "disposition_actual",
                "disposition_status",
                "score",
                "score_exit",
            )
        )
        + f"<td>{row['coverage_matched']}/{row['coverage_total']} ({html.escape(row['coverage_status'])})</td>"
        + f"<td>{html.escape(', '.join(row['missed']) or '—')}</td>"
        + f"<td><a href=\"{html.escape(report_link(proposal, row['path']))}/manifest.json\">manifest</a></td>"
        + "</tr>"
        for row in rows
    ) or "<tr><td colspan=\"13\">No retained evidence.</td></tr>"

    attempts = sorted(
        {state["attempt"]}
        | {item["entry"].get("attempt") for item in captures if item["entry"].get("attempt")}
        | set(comparisons)
        | set(reviews)
    )
    attempt_rows = []
    for attempt in attempts:
        candidate_count = len(attempt_values(captures, attempt, "candidate"))
        control_count = len(attempt_values(captures, attempt, "negative-control"))
        comparison = comparisons.get(attempt)
        review = reviews.get(attempt)
        comparison_text = "not retained"
        if comparison:
            matrix = comparison["document"]["mechanical_acceptance"]
            comparison_text = "PASS" if matrix["satisfied"] else "FAIL"
        decision_text = "—"
        reasoning = "—"
        if review:
            decision_text = review["document"]["decision"].upper()
            reasoning = review["document"]["reasoning"]
        attempt_rows.append(
            "<tr>"
            f"<td>{attempt}</td><td>{candidate_count}</td><td>{control_count}</td>"
            f"<td>{html.escape(comparison_text)}</td><td>{html.escape(decision_text)}</td>"
            f"<td>{html.escape(reasoning)}</td></tr>"
        )

    non_claims = "".join(f"<li>{html.escape(item)}</li>" for item in iteration["non_claims"])
    target = iteration["experiment"]["target"]
    control = iteration["experiment"]["negative_control"]
    rubric = iteration["experiment"]["comparison_rubric"]
    thresholds = iteration["thresholds"]
    calibration = iteration["human_calibration"]
    raw = iteration["raw_scorer_baseline"]
    brief_link = report_link(proposal, iteration["candidate_implementation_brief"])
    return f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><title>{html.escape(iteration['improvement_id'])} improvement loop</title>
<style>body{{font:16px system-ui,sans-serif;line-height:1.45;margin:2rem;max-width:1200px}}table{{border-collapse:collapse;width:100%}}th,td{{border:1px solid #bbb;padding:.45rem;text-align:left;vertical-align:top}}th{{background:#eee}}code{{background:#f4f4f4;padding:.1rem .25rem}}.state{{padding:.75rem;background:#eef6ff;border-left:4px solid #2470b8}}.fact{{border-left:4px solid #555;padding-left:1rem}}.authored{{border-left:4px solid #9a6700;padding-left:1rem}}</style></head>
<body><h1>Improvement loop: {html.escape(iteration['improvement_id'])}</h1>
<p><strong>Generated view owner:</strong> <code>tools/improvement-cycle.py</code>. Do not edit this file.</p>
<h2>Claim and non-claims (authored)</h2><p>{html.escape(iteration['claim'])}</p><ul>{non_claims}</ul>
<h2>Fixed experiment contract</h2>
<table><tbody>
<tr><th>Target</th><td>{html.escape(target['case_id'])} / {html.escape(target['ticket'])} at <code>{html.escape(target['repository']['commit'])}</code></td></tr>
<tr><th>Authored target</th><td>{html.escape(fraction(target['authored_target']))} {html.escape(target['authored_target']['unit'])}</td></tr>
<tr><th>Negative control</th><td>{html.escape(control['case_id'])} / {html.escape(control['ticket'])}; expected {html.escape(control['expected_disposition'])}</td></tr>
<tr><th>Comparison rubric</th><td>{html.escape(rubric['id'])} / <code>{html.escape(rubric['sha256'])}</code></td></tr>
<tr><th>Runs to compare</th><td>candidate {thresholds['minimum_runs_to_compare']['candidate']}; READY control {thresholds['minimum_runs_to_compare']['negative_control']}</td></tr>
<tr><th>Runs to accept</th><td>candidate {thresholds['minimum_runs_to_accept']['candidate']}; READY control {thresholds['minimum_runs_to_accept']['negative_control']}</td></tr>
<tr><th>Candidate brief</th><td><a href="{html.escape(brief_link)}">{html.escape(iteration['candidate_implementation_brief'])}</a></td></tr>
</tbody></table>
<h2>Raw scorer facts</h2><div class="fact"><p>Frozen baseline expectation: {html.escape(fraction(raw))}; score {html.escape(raw['score'])} with exit {raw['score_exit']}. {html.escape(raw['statement'])}</p></div>
<table><thead><tr><th>ID</th><th>Role</th><th>Attempt</th><th>Case</th><th>Ticket</th><th>Artifact</th><th>Disposition</th><th>Disposition verdict</th><th>Score</th><th>Exit</th><th>Raw coverage</th><th>Missed</th><th>Evidence</th></tr></thead><tbody>{evidence_rows}</tbody></table>
<h2>Authored calibration</h2><div class="authored"><p>{html.escape(fraction(calibration))}: {html.escape(calibration['statement'])}</p><p>This is not scorer output and does not replace any raw result.</p></div>
<h2>Machine-derived comparison</h2>
<table><thead><tr><th>Attempt</th><th>Candidate runs</th><th>READY controls</th><th>Mechanical acceptance</th><th>Explicit review decision</th><th>Reviewer reasoning</th></tr></thead><tbody>{''.join(attempt_rows)}</tbody></table>
<p>Mechanical comparison enforces the declared matrix and sample counts. Semantic acceptance remains an explicit retained review.</p>
<h2>Explicit review decision</h2><p>{html.escape(state['last_decision'].upper() if state['last_decision'] else 'No decision retained.')}</p>
<h2>Current state</h2><p class="state"><strong>{html.escape(state['state'])}</strong> — attempt {state['attempt']}<br><strong>Exact next action:</strong> {html.escape(state['next_action'])}</p>
</body></html>
"""


def command_report(args: argparse.Namespace) -> int:
    proposal = require_real_directory(Path(args.proposal), "proposal directory")
    _, iteration = load_iteration(proposal)
    captures, comparisons, reviews = load_all(iteration)
    rendered = render_report(proposal, iteration, captures, comparisons, reviews)
    output = proposal / "improvement-report.html"
    require_no_symlinks(output, "improvement report")
    if args.check:
        if not output.is_file() or output.read_text(encoding="utf-8") != rendered:
            print(f"improvement-cycle: report drift: {output}", file=sys.stderr)
            return 1
        print(f"report: clean — {output.relative_to(REPO_ROOT)}")
        return 0
    output.write_text(rendered, encoding="utf-8")
    print(f"report: rendered — {output.relative_to(REPO_ROOT)}")
    return 0


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(description=__doc__)
    commands = root.add_subparsers(dest="command", required=True)
    capture = commands.add_parser("capture", help="retain one SCORED run as immutable evidence")
    capture.add_argument("proposal")
    capture.add_argument("--role", required=True)
    capture.add_argument("--id", dest="evidence_id", required=True)
    capture.add_argument("--from", dest="source", required=True)
    capture.set_defaults(func=command_capture)
    state = commands.add_parser("state", help="derive state and one next action")
    state.add_argument("proposal")
    state.add_argument("--json", action="store_true")
    state.set_defaults(func=command_state)
    compare = commands.add_parser("compare", help="retain an immutable comparison for the current attempt")
    compare.add_argument("proposal")
    compare.set_defaults(func=command_compare)
    review = commands.add_parser("review", help="retain an explicit accept, iterate, or reject decision")
    review.add_argument("proposal")
    review.add_argument("--decision", required=True)
    review.add_argument("--reviewer", required=True)
    review.add_argument("--reasoning", required=True)
    review.set_defaults(func=command_review)
    report = commands.add_parser("report", help="render or drift-check the generated improvement report")
    report.add_argument("proposal")
    report.add_argument("--check", action="store_true")
    report.set_defaults(func=command_report)
    return root


def main() -> int:
    args = parser().parse_args()
    try:
        return args.func(args)
    except CycleError as exc:
        print(f"improvement-cycle: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
