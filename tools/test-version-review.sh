#!/usr/bin/env bash
# Isolated lifecycle and fail-closed controls for tools/version-review.py.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYTHON="${PYTHON:-python3}"
export PYTHONDONTWRITEBYTECODE=1

"$PYTHON" - "$ROOT" <<'PY'
import argparse
import hashlib
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import yaml


root = Path(sys.argv[1])
tool = root / "tools/version-review.py"
version = "0.19.0"
plugin_commit = "1" * 40
target_commit = "2" * 40
proposal = "docs/improvement-proposals/0.23.0/version-scoped-team-review"
temp = Path(tempfile.mkdtemp(prefix="recon-version-review-test."))


def fail(message):
    raise AssertionError(message)


def invoke(*arguments, expected=0, contains=None):
    completed = subprocess.run(
        [sys.executable, str(tool), *map(str, arguments)],
        cwd=root,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    if completed.returncode != expected:
        fail(
            f"expected exit {expected}, got {completed.returncode}: "
            f"{' '.join(map(str, arguments))}\n{completed.stdout}"
        )
    if contains and contains not in completed.stdout:
        fail(f"missing diagnostic {contains!r}:\n{completed.stdout}")
    return completed.stdout


def dump(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(yaml.safe_dump(value, sort_keys=False), encoding="utf-8")


def load(path):
    return yaml.safe_load(path.read_text(encoding="utf-8"))


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def init(review_root, *, selected_version=version):
    review_root.mkdir(parents=True)
    invoke(
        "init",
        review_root,
        "--plugin-version",
        selected_version,
        "--plugin-tag",
        f"v{selected_version}",
        "--plugin-commit",
        plugin_commit,
        "--opened-at",
        "2026-08-05T09:00:00Z",
    )


def workspace(name, *, ticket="ATT-1234", selected_version=version, started="2026-08-05T10:00:00Z"):
    directory = temp / "workspaces" / name
    directory.mkdir(parents=True)
    dump(
        directory / "meta.yaml",
        {
            "ticket": ticket,
            "plugin_version": selected_version,
            "started": started,
            "started_host": "codex",
            "started_surface": "desktop",
        },
    )
    dump(directory / "triage/triage.yaml", {"recon": "triage", "disposition": "BLOCKED"})
    report = directory / "report/dossier.html"
    report.parent.mkdir(parents=True)
    report.write_text(f"<!doctype html><title>{ticket} {name}</title>\n", encoding="utf-8")
    (directory / "discovery").mkdir()
    (directory / "discovery/discovery.md").write_text("# Discovery\n", encoding="utf-8")
    (directory / "history.ndjson").write_text('{"private": true}\n', encoding="utf-8")
    dump(directory / "triage/ticket.json", {"private": True})
    dump(directory / "triage/aux-owners.json", {"private": True})
    dump(
        directory / "triage/jira/post-gate.yaml",
        {
            "post_gate": {
                "date": "2026-08-05",
                "exchanges": [
                    {
                        "presented": "post-gate-questions.txt",
                        "answer_verbatim": "Don't post",
                        "outcome": "declined",
                    }
                ],
            }
        },
    )
    (directory / "runs/old").mkdir(parents=True)
    (directory / "runs/old/private.txt").write_text("private\n", encoding="utf-8")
    return directory


def capture(review_root, source, *, run_id, ticket="ATT-1234", expected=0, contains=None):
    return invoke(
        "capture",
        review_root,
        "--plugin-version",
        version,
        "--ticket",
        ticket,
        "--workspace",
        source,
        "--target-repository",
        "AdCreative-Frontend-V2",
        "--target-commit",
        target_commit,
        "--run-id",
        run_id,
        "--captured-at",
        "2026-08-05T11:00:00Z",
        expected=expected,
        contains=contains,
    )


def receipt(review_root, run_id):
    return load(
        review_root
        / f"versions/v{version}/tickets/ATT-1234/runs/{run_id}/receipt.yaml"
    )


def authored_review(review_root, run_id, review_id):
    value = load(root / "evals/version-reviews/templates/review.yaml")
    value.update(
        {
            "review_id": review_id,
            "reviewer": review_id.replace("-", " ").title(),
            "plugin_version": version,
            "ticket": "ATT-1234",
            "run_id": run_id,
            "report_sha256": receipt(review_root, run_id)["artifacts"]["report/dossier.html"],
        }
    )
    path = temp / "authored" / f"{run_id}-{review_id}.yaml"
    dump(path, value)
    return path


def authored_consensus(review_root, run_id, review_id):
    value = load(root / "evals/version-reviews/templates/consensus.yaml")
    value.update(
        {
            "plugin_version": version,
            "ticket": "ATT-1234",
            "run_id": run_id,
            "report_sha256": receipt(review_root, run_id)["artifacts"]["report/dossier.html"],
        }
    )
    value["accepted_findings"][0]["review_id"] = review_id
    path = temp / "authored" / f"{run_id}-consensus.yaml"
    dump(path, value)
    return path


def synthesis_inputs(review_ids):
    findings = load(root / "evals/version-reviews/templates/findings.yaml")
    findings["plugin_version"] = version
    occurrences = []
    for run_id, review_id in review_ids.items():
        occurrences.append(
            {
                "ticket": "ATT-1234",
                "run_id": run_id,
                "review_id": review_id,
                "finding_id": "REV-1",
            }
        )
    findings["findings"][0]["occurrences"] = occurrences
    findings["findings"][0]["count"] = len(occurrences)
    themes = load(root / "evals/version-reviews/templates/themes.yaml")
    themes["plugin_version"] = version
    decisions = load(root / "evals/version-reviews/templates/decisions.yaml")
    decisions["plugin_version"] = version
    authored = temp / "authored"
    paths = (authored / "findings.yaml", authored / "themes.yaml", authored / "decisions.yaml")
    for path, value in zip(paths, (findings, themes, decisions), strict=True):
        dump(path, value)
    return paths


def synthesize(review_root, paths, *, expected=0, contains=None):
    findings, themes, decisions = paths
    return invoke(
        "synthesize",
        review_root,
        "--plugin-version",
        version,
        "--findings",
        findings,
        "--themes",
        themes,
        "--decisions",
        decisions,
        expected=expected,
        contains=contains,
    )


def closure_input(*, runs=2, reviews=2, proposal_path=proposal):
    value = load(root / "evals/version-reviews/templates/closure.yaml")
    value["plugin_version"] = version
    value["counts"]["runs"] = runs
    value["counts"]["reviews"] = reviews
    value["accepted_improvements"][0]["proposal_path"] = proposal_path
    path = temp / "authored/closure.yaml"
    dump(path, value)
    return path


try:
    # Init identity and no-overwrite controls.
    invalid_root = temp / "invalid"
    invalid_root.mkdir()
    invoke(
        "init", invalid_root, "--plugin-version", "0.19", "--plugin-tag", "v0.19",
        "--plugin-commit", plugin_commit, expected=2, contains="stable X.Y.Z",
    )
    invoke(
        "init", invalid_root, "--plugin-version", version, "--plugin-tag", "v0.18.0",
        "--plugin-commit", plugin_commit, expected=2, contains="plugin tag must equal",
    )
    invoke(
        "init", invalid_root, "--plugin-version", version, "--plugin-tag", f"v{version}",
        "--plugin-commit", "short", expected=2, contains="full lowercase 40-character commit",
    )

    review_root = temp / "private-review"
    init(review_root)
    invoke(
        "init", review_root, "--plugin-version", version, "--plugin-tag", f"v{version}",
        "--plugin-commit", plugin_commit, expected=2, contains="destination already exists",
    )
    collecting = invoke("state", review_root, "--plugin-version", version)
    if "state: COLLECTING" not in collecting or "runs: 0" not in collecting:
        fail("COLLECTING state output drift")

    first = workspace("first")
    second = workspace("second", started="2026-08-05T10:30:00Z")

    # Source identity, completeness, Jira, symlink, and overlap controls.
    missing = workspace("missing")
    (missing / "report/dossier.html").unlink()
    capture(review_root, missing, run_id="missing", expected=2, contains="must be a regular file")

    wrong_ticket = workspace("wrong-ticket", ticket="ATT-9999")
    capture(review_root, wrong_ticket, run_id="wrong-ticket", expected=2, contains="meta ticket disagrees")

    wrong_version = workspace("wrong-version", selected_version="0.18.0")
    capture(review_root, wrong_version, run_id="wrong-version", expected=2, contains="plugin_version disagrees")

    posted = workspace("posted")
    dump(posted / "triage/jira/post-result.json", {"status": "posted"})
    capture(review_root, posted, run_id="posted", expected=2, contains="Jira mutation result")

    nondeclined = workspace("nondeclined")
    dump(
        nondeclined / "triage/jira/post-gate.yaml",
        {
            "post_gate": {
                "date": "2026-08-05",
                "exchanges": [
                    {
                        "presented": "post-gate-questions.txt",
                        "answer_verbatim": "Post it",
                        "outcome": "posted",
                    }
                ],
            }
        },
    )
    capture(review_root, nondeclined, run_id="nondeclined", expected=2, contains="must end in declined")

    leaf = workspace("symlink-leaf")
    real_triage = leaf / "triage/real.yaml"
    shutil.move(leaf / "triage/triage.yaml", real_triage)
    os.symlink(real_triage.name, leaf / "triage/triage.yaml")
    capture(review_root, leaf, run_id="symlink-leaf", expected=2, contains="symlink ancestor or leaf")

    ancestor = workspace("symlink-ancestor")
    outside = temp / "outside-triage"
    outside.mkdir()
    dump(outside / "triage.yaml", {"recon": "triage"})
    shutil.rmtree(ancestor / "triage")
    os.symlink(outside, ancestor / "triage")
    capture(review_root, ancestor, run_id="symlink-ancestor", expected=2, contains="symlink ancestor or leaf")

    overlap = review_root / f"versions/v{version}/source-workspace"
    shutil.copytree(first, overlap)
    capture(review_root, overlap, run_id="overlap", expected=2, contains="must not overlap")
    shutil.rmtree(overlap)

    # Two immutable runs for one ticket; excluded private artifacts never cross the boundary.
    capture(review_root, first, run_id="run-one")
    capture(review_root, first, run_id="run-one", expected=2, contains="already exists")
    capture(review_root, second, run_id="run-two")
    version_dir = review_root / f"versions/v{version}"
    run_one = version_dir / "tickets/ATT-1234/runs/run-one"
    actual_artifacts = {
        path.relative_to(run_one / "artifacts").as_posix()
        for path in (run_one / "artifacts").rglob("*") if path.is_file()
    }
    if actual_artifacts != {
        "meta.yaml", "triage/triage.yaml", "report/dossier.html", "discovery/discovery.md"
    }:
        fail(f"capture allowlist drift: {sorted(actual_artifacts)}")
    forbidden = ("ticket.json", "aux-owners.json", "post-gate.yaml", "history.ndjson", "private.txt")
    if any(any(path.name == name for path in run_one.rglob("*")) for name in forbidden):
        fail("excluded private artifacts crossed the capture boundary")
    collecting = invoke("state", review_root, "--plugin-version", version)
    if "state: COLLECTING" not in collecting or "runs: 2" not in collecting:
        fail("multi-run COLLECTING state drift")

    empty_root = temp / "empty-review"
    init(empty_root, selected_version="0.19.1")
    invoke(
        "begin-review", empty_root, "--plugin-version", "0.19.1",
        expected=2, contains="at least one captured run",
    )

    dummy_synthesis = synthesis_inputs({"run-one": "teammate-a", "run-two": "teammate-b"})
    synthesize(review_root, dummy_synthesis, expected=2, contains="requires REVIEWING")
    invoke(
        "close", review_root, "--plugin-version", version, "--from", closure_input(),
        expected=2, contains="requires SYNTHESIZED",
    )

    invoke("begin-review", review_root, "--plugin-version", version)
    reviewing = invoke("state", review_root, "--plugin-version", version)
    if "state: REVIEWING" not in reviewing or "add-review for ATT-1234/run-one" not in reviewing:
        fail("REVIEWING state output drift")
    capture(review_root, first, run_id="late", expected=2, contains="only while")

    review_ids = {"run-one": "teammate-a", "run-two": "teammate-b"}
    review_paths = {}
    for run_id, review_id in review_ids.items():
        path = authored_review(review_root, run_id, review_id)
        review_paths[run_id] = path
        if run_id == "run-one":
            drift = load(path)
            drift["report_sha256"] = "f" * 64
            drift_path = temp / "authored/review-hash-drift.yaml"
            dump(drift_path, drift)
            invoke(
                "add-review", review_root, "--plugin-version", version, "--from", drift_path,
                expected=2, contains="report_sha256 disagrees",
            )
        invoke("add-review", review_root, "--plugin-version", version, "--from", path)
        invoke(
            "add-review", review_root, "--plugin-version", version, "--from", path,
            expected=2, contains="review already exists",
        )

        consensus_path = authored_consensus(review_root, run_id, review_id)
        if run_id == "run-one":
            unknown = load(consensus_path)
            unknown["accepted_findings"][0]["finding_id"] = "REV-999"
            unknown_path = temp / "authored/unknown-consensus.yaml"
            dump(unknown_path, unknown)
            invoke(
                "add-consensus", review_root, "--plugin-version", version, "--from", unknown_path,
                expected=2, contains="unknown review finding",
            )
        invoke("add-consensus", review_root, "--plugin-version", version, "--from", consensus_path)
        invoke(
            "add-consensus", review_root, "--plugin-version", version, "--from", consensus_path,
            expected=2, contains="consensus already exists",
        )

    synthesis_paths = synthesis_inputs(review_ids)
    bad_findings = load(synthesis_paths[0])
    bad_findings["findings"][0]["occurrences"][0]["review_id"] = "unknown"
    bad_findings_path = temp / "authored/bad-findings.yaml"
    dump(bad_findings_path, bad_findings)
    synthesize(
        review_root, (bad_findings_path, synthesis_paths[1], synthesis_paths[2]),
        expected=2, contains="unknown retained finding",
    )

    # A forced post-create exception must restore REVIEWING with no synthesis directory.
    exception_review_root = temp / "exception-review"
    shutil.copytree(review_root, exception_review_root)
    spec = importlib.util.spec_from_file_location("version_review", tool)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    original_update = module.update_status
    module.update_status = lambda *args, **kwargs: (_ for _ in ()).throw(RuntimeError("forced"))
    try:
        module.command_synthesize(
            argparse.Namespace(
                review_root=str(exception_review_root), plugin_version=version,
                findings=str(synthesis_paths[0]), themes=str(synthesis_paths[1]),
                decisions=str(synthesis_paths[2]),
            )
        )
        fail("forced synthesis exception did not propagate")
    except RuntimeError as exc:
        if str(exc) != "forced":
            raise
    finally:
        module.update_status = original_update
    if (exception_review_root / f"versions/v{version}/synthesis").exists():
        fail("failed synthesis left a partial destination")
    invoke("validate", exception_review_root, "--plugin-version", version)

    synthesize(review_root, synthesis_paths)
    synthesized = invoke("state", review_root, "--plugin-version", version)
    if "state: SYNTHESIZED" not in synthesized or "allowed_action: close" not in synthesized:
        fail("SYNTHESIZED state output drift")
    synthesize(review_root, synthesis_paths, expected=2, contains="requires REVIEWING")

    unsafe_closure = closure_input(proposal_path="../../private")
    invoke(
        "close", review_root, "--plugin-version", version, "--from", unsafe_closure,
        expected=2, contains="repository-relative proposal path",
    )
    wrong_counts = closure_input(runs=99)
    invoke(
        "close", review_root, "--plugin-version", version, "--from", wrong_counts,
        expected=2, contains="counts disagree",
    )
    valid_closure = closure_input()

    # A forced close exception must restore SYNTHESIZED and remove both outputs.
    exception_close_root = temp / "exception-close"
    shutil.copytree(review_root, exception_close_root)
    module.update_status = lambda *args, **kwargs: (_ for _ in ()).throw(RuntimeError("forced"))
    try:
        module.command_close(
            argparse.Namespace(
                review_root=str(exception_close_root), plugin_version=version,
                source=str(valid_closure),
            )
        )
        fail("forced close exception did not propagate")
    except RuntimeError as exc:
        if str(exc) != "forced":
            raise
    finally:
        module.update_status = original_update
    close_version = exception_close_root / f"versions/v{version}"
    if (close_version / "outcomes").exists() or (close_version / "closure.yaml").exists():
        fail("failed close left a partial destination")
    invoke("validate", exception_close_root, "--plugin-version", version)

    invoke("close", review_root, "--plugin-version", version, "--from", valid_closure)
    closed = invoke("state", review_root, "--plugin-version", version)
    if "state: CLOSED" not in closed or "allowed_action: none" not in closed:
        fail("CLOSED state output drift")
    invoke("validate", review_root, "--plugin-version", version, contains="version review: clean")
    invoke(
        "close", review_root, "--plugin-version", version, "--from", valid_closure,
        expected=2, contains="requires SYNTHESIZED",
    )

    # Retained hashes, indexes, and root file set all fail closed on drift.
    artifact_tamper = temp / "artifact-tamper"
    shutil.copytree(review_root, artifact_tamper)
    tampered_report = artifact_tamper / f"versions/v{version}/tickets/ATT-1234/runs/run-one/artifacts/report/dossier.html"
    tampered_report.write_text("tampered\n", encoding="utf-8")
    invoke("validate", artifact_tamper, "--plugin-version", version, expected=2, contains="artifact hash drift")

    manifest_tamper = temp / "manifest-tamper"
    shutil.copytree(review_root, manifest_tamper)
    manifest_path = manifest_tamper / f"versions/v{version}/manifest.yaml"
    manifest = load(manifest_path)
    manifest["runs"] = []
    dump(manifest_path, manifest)
    invoke("validate", manifest_tamper, "--plugin-version", version, expected=2, contains="version manifest drift")

    unknown_entry = temp / "unknown-entry"
    shutil.copytree(review_root, unknown_entry)
    (unknown_entry / f"versions/v{version}/notes.txt").write_text("drift\n", encoding="utf-8")
    invoke("validate", unknown_entry, "--plugin-version", version, expected=2, contains="file set drift")

    symlink_root = temp / "review-root-link"
    os.symlink(review_root, symlink_root)
    invoke("state", symlink_root, "--plugin-version", version, expected=2, contains="symlink ancestor or leaf")

    # Every checked-in semantic template participated in the successful lifecycle.
    expected_templates = {"review.yaml", "consensus.yaml", "findings.yaml", "themes.yaml", "decisions.yaml", "closure.yaml"}
    if {path.name for path in (root / "evals/version-reviews/templates").glob("*.yaml")} != expected_templates:
        fail("template set drift")

    print("version-review controls: PASS — lifecycle, privacy, integrity, joins, no-overwrite, and cleanup")
finally:
    shutil.rmtree(temp, ignore_errors=True)
PY
