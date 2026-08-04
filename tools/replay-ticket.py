#!/usr/bin/env python3
"""Validate, prepare, derive state, evaluate, and score real-ticket replays.

This is repository evaluation tooling, not a shipped Recon runtime command.
The prepared directory deliberately excludes the scoring oracle.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import tarfile
import tempfile
import unicodedata
from datetime import datetime
from pathlib import Path, PurePosixPath


# Loading the production parser must not mutate recon/scripts/ with __pycache__.
sys.dont_write_bytecode = True


REPO_ROOT = Path(__file__).resolve().parents[1]
TRIAGE_TOOLS = REPO_ROOT / "recon" / "scripts" / "triage-tools.py"
TRIAGE_SKILL = REPO_ROOT / "recon" / "skills" / "recon-triage" / "SKILL.md"
CASE_ID = re.compile(r"[a-z0-9]+(?:-[a-z0-9]+)*\Z")
TICKET_ID = re.compile(r"[A-Z][A-Z0-9]+-[1-9][0-9]*\Z")
OBJECT_ID = re.compile(r"[0-9a-f]{40}\Z")
SHA256 = re.compile(r"[0-9a-f]{64}\Z")
DISPOSITIONS = {"READY", "BLOCKED", "NEEDS_INFO"}
RUN_STATES = {"PREPARED", "SUBMITTED", "SCORED"}
EVALUATION_DIR = "evaluation"
REPLAY_OWNER_IDENTITIES = {
    "product": "replay-owner:product",
    "product-design": "replay-owner:product-design",
    "product-backend": "replay-owner:product-backend",
    "design": "replay-owner:design",
    "backend": "replay-owner:backend",
    "engineering": "replay-owner:engineering",
}
REPLAY_VERIFIER = r'''#!/usr/bin/env python3
"""Verify one replay submission without Jira or a scoring oracle."""
import importlib.util
import json
import os
import shutil
import sys
import tempfile
from pathlib import Path


RUN = Path(__file__).resolve().parents[1]
VERIFIER = RUN / "verifier"
CANDIDATE = RUN / "submission" / "triage.yaml"
IDENTITIES = VERIFIER / "replay-owner-identities.json"
TICKET = next((RUN / "workspace").glob("*/triage/ticket.json"), None)
TOOLS = VERIFIER / "triage-tools.py"


def fail(message):
    print(f"REPLAY VERIFY: {message}")
    return 1


def main():
    if CANDIDATE.is_symlink() or not CANDIDATE.is_file():
        return fail("submission/triage.yaml must be a regular file")
    if TICKET is None or TICKET.is_symlink() or not TICKET.is_file():
        return fail("prepared ticket is missing")
    if TOOLS.is_symlink() or not TOOLS.is_file():
        return fail("bundled production triage verifier is missing")
    try:
        identities = json.loads(IDENTITIES.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        return fail(f"replay owner identities are unreadable: {exc}")
    if set(identities) != {"schema_version", "kind", "owners"}:
        return fail("replay owner identities have an invalid schema")
    if identities["schema_version"] != 1 or identities["kind"] != "replay-only":
        return fail("replay owner identities are not replay-only schema version 1")
    owners = identities["owners"]
    if not isinstance(owners, dict) or not owners:
        return fail("replay owner identities have no owners")

    spec = importlib.util.spec_from_file_location("bundled_triage_tools", TOOLS)
    if spec is None or spec.loader is None:
        return fail("cannot load bundled production triage verifier")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    parse_errors = []
    document = module.parse_triage(CANDIDATE, parse_errors)
    if not parse_errors:
        identity_errors = []
        for index, blocker in enumerate(document["blockers"], 1):
            owner = blocker.get("owner", "")
            account_id = blocker.get("owner_account_id", "")
            expected = owners.get(owner)
            if not expected:
                identity_errors.append(
                    f"blocker {index} owner '{owner or 'missing'}' has no replay-only identity"
                )
            elif not account_id:
                identity_errors.append(
                    f"blocker {index} owner_account_id missing — use replay-only identity for {owner}"
                )
            elif account_id != expected:
                identity_errors.append(
                    f"blocker {index} owner_account_id is not the replay-only identity for {owner}"
                )
        if identity_errors:
            for error in identity_errors:
                print(f"REPLAY VERIFY: {error}")
            return 1

    with tempfile.TemporaryDirectory(prefix="recon-replay-verify-") as temp_name:
        workspace = Path(temp_name) / "ticket"
        triage = workspace / "triage"
        triage.mkdir(parents=True)
        shutil.copyfile(TICKET, triage / "ticket.json")
        shutil.copyfile(CANDIDATE, triage / "triage.yaml")
        old_root = os.environ.get("RECON_SOURCE_ROOT")
        os.environ["RECON_SOURCE_ROOT"] = str(RUN / "target-repo")
        try:
            status = module.cmd_verify(workspace)
        finally:
            if old_root is None:
                os.environ.pop("RECON_SOURCE_ROOT", None)
            else:
                os.environ["RECON_SOURCE_ROOT"] = old_root
    if status:
        return status
    print(
        f"replay verifier: clean — {len(document['blockers'])} replay-only owner identity value(s) verified"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
'''


class ReplayError(Exception):
    """A stable, user-actionable laboratory contract violation."""


def require_exact_keys(value, expected, label):
    if not isinstance(value, dict):
        raise ReplayError(f"{label} must be an object")
    actual = set(value)
    missing = sorted(expected - actual)
    unknown = sorted(actual - expected)
    if missing:
        raise ReplayError(f"{label} missing field(s): {', '.join(missing)}")
    if unknown:
        raise ReplayError(f"{label} has unknown field(s): {', '.join(unknown)}")


def read_json(path, label):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except OSError as exc:
        raise ReplayError(f"cannot read {label}: {exc}") from exc
    except json.JSONDecodeError as exc:
        raise ReplayError(f"{label} is not valid JSON: {exc}") from exc


def safe_case_file(case_dir, raw_path, label, required_prefix):
    if not isinstance(raw_path, str) or not raw_path:
        raise ReplayError(f"{label} must be a non-empty relative path")
    relative = PurePosixPath(raw_path)
    if relative.is_absolute() or ".." in relative.parts or "\\" in raw_path:
        raise ReplayError(f"{label} must stay inside the case directory: {raw_path}")
    if not relative.parts or relative.parts[0] != required_prefix:
        raise ReplayError(f"{label} must live under {required_prefix}/: {raw_path}")
    path = case_dir.joinpath(*relative.parts)
    if path.is_symlink() or not path.is_file():
        raise ReplayError(f"{label} must be a regular, non-symlink file: {raw_path}")
    try:
        path.resolve(strict=True).relative_to(case_dir.resolve(strict=True))
    except (OSError, RuntimeError, ValueError) as exc:
        raise ReplayError(f"{label} escapes the case directory: {raw_path}") from exc
    return path


def file_sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def parse_iso8601(value, label):
    if not isinstance(value, str) or not value:
        raise ReplayError(f"{label} must be a non-empty ISO-8601 timestamp")
    try:
        datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise ReplayError(f"{label} is not ISO-8601: {value}") from exc


def validate_case(case_arg):
    case_dir = Path(case_arg).expanduser()
    if case_dir.is_symlink() or not case_dir.is_dir():
        raise ReplayError(f"case directory does not exist or is a symlink: {case_dir}")
    case_dir = case_dir.resolve(strict=True)
    manifest_path = case_dir / "case.json"
    if manifest_path.is_symlink() or not manifest_path.is_file():
        raise ReplayError(f"case manifest is missing or symlinked: {manifest_path}")
    manifest = read_json(manifest_path, "case.json")
    require_exact_keys(
        manifest,
        {"schema_version", "id", "task_class", "source", "input", "repository", "oracle"},
        "case.json",
    )
    if manifest["schema_version"] != 1:
        raise ReplayError(f"unsupported case schema_version: {manifest['schema_version']}")
    if not isinstance(manifest["id"], str) or not CASE_ID.fullmatch(manifest["id"]):
        raise ReplayError(f"invalid case id: {manifest['id']!r}")
    if manifest["id"] != case_dir.name:
        raise ReplayError(
            f"case id '{manifest['id']}' must match directory '{case_dir.name}'"
        )
    if not isinstance(manifest["task_class"], str) or not manifest["task_class"]:
        raise ReplayError("task_class must be a non-empty string")

    source = manifest["source"]
    require_exact_keys(
        source, {"ticket", "snapshot_at", "cutoff", "human_comments"}, "source"
    )
    if not isinstance(source["ticket"], str) or not TICKET_ID.fullmatch(source["ticket"]):
        raise ReplayError(f"invalid source.ticket: {source['ticket']!r}")
    parse_iso8601(source["snapshot_at"], "source.snapshot_at")
    if not isinstance(source["cutoff"], str) or not source["cutoff"]:
        raise ReplayError("source.cutoff must be a non-empty string")
    if not isinstance(source["human_comments"], int) or source["human_comments"] < 0:
        raise ReplayError("source.human_comments must be a non-negative integer")

    input_spec = manifest["input"]
    require_exact_keys(input_spec, {"ticket", "sha256"}, "input")
    if not isinstance(input_spec["sha256"], str) or not SHA256.fullmatch(input_spec["sha256"]):
        raise ReplayError("input.sha256 must be a lowercase 64-character SHA-256")
    ticket_path = safe_case_file(case_dir, input_spec["ticket"], "input.ticket", "input")
    actual_hash = file_sha256(ticket_path)
    if actual_hash != input_spec["sha256"]:
        raise ReplayError(
            f"input hash drift: case.json has {input_spec['sha256']}, ticket is {actual_hash}"
        )
    ticket = read_json(ticket_path, "input ticket")
    if not isinstance(ticket, dict) or ticket.get("key") != source["ticket"]:
        raise ReplayError("input ticket key does not match source.ticket")
    fields = ticket.get("fields")
    if not isinstance(fields, dict):
        raise ReplayError("input ticket fields must be an object")
    comments = (fields.get("comment") or {}).get("comments")
    total = (fields.get("comment") or {}).get("total")
    if not isinstance(comments, list) or total != len(comments):
        raise ReplayError("input ticket comment.total must equal the comments list length")
    if len(comments) != source["human_comments"]:
        raise ReplayError(
            "input ticket human comment count does not match source.human_comments "
            f"({len(comments)} != {source['human_comments']})"
        )

    repository = manifest["repository"]
    require_exact_keys(repository, {"name", "commit"}, "repository")
    if not isinstance(repository["name"], str) or not repository["name"]:
        raise ReplayError("repository.name must be a non-empty string")
    if not isinstance(repository["commit"], str) or not OBJECT_ID.fullmatch(repository["commit"]):
        raise ReplayError("repository.commit must be a full lowercase 40-character object ID")

    oracle_path = safe_case_file(case_dir, manifest["oracle"], "oracle", "oracle")
    oracle = read_json(oracle_path, "oracle")
    if oracle.get("schema_version") == 1:
        require_exact_keys(oracle, {"schema_version", "expected_disposition", "required_decisions"}, "oracle")
    else:
        require_exact_keys(oracle, {"schema_version", "expected_disposition", "required_decisions", "calibration"}, "oracle")
    if oracle["schema_version"] not in {1, 2}:
        raise ReplayError(f"unsupported oracle schema_version: {oracle['schema_version']}")
    if oracle["expected_disposition"] not in DISPOSITIONS:
        raise ReplayError(f"invalid expected_disposition: {oracle['expected_disposition']!r}")
    decisions = oracle["required_decisions"]
    if not isinstance(decisions, list):
        raise ReplayError("oracle.required_decisions must be a list")
    if not decisions and oracle["expected_disposition"] != "READY":
        raise ReplayError(
            "oracle.required_decisions may be empty only when expected_disposition is READY"
        )
    seen_ids = set()
    for index, decision in enumerate(decisions, 1):
        label = f"oracle decision {index}"
        require_exact_keys(decision, {"id", "label", "signals"}, label)
        decision_id = decision["id"]
        if not isinstance(decision_id, str) or not CASE_ID.fullmatch(decision_id):
            raise ReplayError(f"{label} has invalid id: {decision_id!r}")
        if decision_id in seen_ids:
            raise ReplayError(f"oracle has duplicate decision id: {decision_id}")
        seen_ids.add(decision_id)
        if not isinstance(decision["label"], str) or not decision["label"]:
            raise ReplayError(f"{label}.label must be a non-empty string")
        signals = decision["signals"]
        if not isinstance(signals, list) or not signals:
            raise ReplayError(f"{label}.signals must be a non-empty list")
        for group_index, group in enumerate(signals, 1):
            if not isinstance(group, list) or not group:
                raise ReplayError(f"{label}.signals[{group_index}] must be non-empty")
            for signal in group:
                if not isinstance(signal, str) or not signal or signal != signal.casefold():
                    raise ReplayError(
                        f"{label}.signals[{group_index}] entries must be lowercase strings"
                    )
    if oracle["schema_version"] == 1:
        calibration = []
    else:
        calibration = oracle["calibration"]
    if oracle["schema_version"] == 2 and (not isinstance(calibration, list) or len(calibration) != 7):
        raise ReplayError("oracle.calibration must retain seven reviewed decisions")
    reviewed_ids = set()
    allowed_classifications = {
        "approved blocking decision", "closed by ticket", "repository-resolvable",
        "optional/non-blocking", "insufficient frozen evidence",
    }
    for index, item in enumerate(calibration, 1):
        require_exact_keys(item, {"id", "classification", "reason"}, f"oracle calibration {index}")
        if not isinstance(item["id"], str) or not CASE_ID.fullmatch(item["id"]):
            raise ReplayError(f"oracle calibration {index} has invalid id")
        if item["id"] in reviewed_ids:
            raise ReplayError(f"oracle calibration has duplicate id: {item['id']}")
        reviewed_ids.add(item["id"])
        if item["classification"] not in allowed_classifications:
            raise ReplayError(f"oracle calibration {index} has invalid classification")
        if not isinstance(item["reason"], str) or not item["reason"]:
            raise ReplayError(f"oracle calibration {index} needs a retained reason")
    approved = {item["id"] for item in calibration if item["classification"] == "approved blocking decision"}
    if oracle["schema_version"] == 2 and approved != seen_ids:
        raise ReplayError("oracle required_decisions must exactly match approved calibration decisions")

    return {
        "dir": case_dir,
        "manifest": manifest,
        "ticket_path": ticket_path,
        "ticket": ticket,
        "oracle_path": oracle_path,
        "oracle": oracle,
    }


def run_git(args, cwd, *, binary=False):
    try:
        return subprocess.run(
            ["git", "-C", str(cwd), *args],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=not binary,
        )
    except FileNotFoundError as exc:
        raise ReplayError("git is required for replay preparation") from exc
    except subprocess.CalledProcessError as exc:
        stderr = exc.stderr.decode("utf-8", "replace") if binary else exc.stderr
        raise ReplayError(f"git {' '.join(args)} failed: {(stderr or '').strip()}") from exc


def export_commit(repo, commit, destination):
    result = run_git(["archive", "--format=tar", commit], repo, binary=True)
    archive_path = destination.parent / "target-repo.tar"
    archive_path.write_bytes(result.stdout)
    destination.mkdir()
    try:
        with tarfile.open(archive_path, "r:") as archive:
            for member in archive.getmembers():
                relative = PurePosixPath(member.name)
                if relative.is_absolute() or ".." in relative.parts:
                    raise ReplayError(f"target archive contains unsafe path: {member.name}")
                if not (member.isfile() or member.isdir()):
                    raise ReplayError(
                        f"target archive contains unsupported link or special file: {member.name}"
                    )
            archive.extractall(destination)
    finally:
        archive_path.unlink(missing_ok=True)


def git_commit(path):
    return run_git(["rev-parse", "HEAD"], path).stdout.strip()


def git_dirty(path):
    return bool(run_git(["status", "--porcelain"], path).stdout.strip())


def replay_instructions(case):
    ticket = case["manifest"]["source"]["ticket"]
    return f"""# Frozen Recon replay — {case['manifest']['id']}

This directory is the complete replay input. Do not contact Jira, mutate an
external system, inspect the original case directory, or search for an oracle.

1. Read `skill/recon-triage/SKILL.md` as the judgment and artifact contract.
2. Treat `workspace/{ticket}/triage/ticket.json` as the already-fetched Jira
   snapshot. Skip workspace startup, live fetch, posting, and delivery steps.
3. Inspect `target-repo/`, which is exported from the commit in `receipt.json`.
4. Perform the triage checks and write only `submission/triage.yaml`. For every
   BLOCKED or NEEDS_INFO blocker, copy the exact replay-only `owner_account_id`
   for its owner from `verifier/replay-owner-identities.json`; never invent a
   Jira account ID.
5. Run this exact command after every correction, and do not return until it
   exits 0:

   `python3 verifier/verify-submission.py`

   It uses the bundled production parser/verifier and no scoring oracle. Do not
   score the submission or read anything outside this prepared directory.
6. Stop only after clean verification and return this exact handoff, replacing
   `<pwd>` with `pwd -P`:

   Replay submission ready
   Run directory: <pwd>
   Submission: submission/triage.yaml
   Operator next action: derive state and evaluate outside this context

This replay evaluates triage judgment from a frozen post-fetch state. It does
not evaluate skill activation, Jira transport, or delivery rails.
"""


def prepare_case(case, repo_arg, out_arg):
    repo = Path(repo_arg).expanduser()
    if repo.is_symlink() or not repo.is_dir():
        raise ReplayError(f"target repository does not exist or is symlinked: {repo}")
    repo = repo.resolve(strict=True)
    expected_commit = case["manifest"]["repository"]["commit"]
    resolved_commit = run_git(["rev-parse", "--verify", f"{expected_commit}^{{commit}}"], repo).stdout.strip()
    if resolved_commit != expected_commit:
        raise ReplayError(
            f"target commit resolved to {resolved_commit}, expected {expected_commit}"
        )

    out = Path(out_arg).expanduser().absolute()
    if out.exists() or out.is_symlink():
        raise ReplayError(f"output already exists; refusing overwrite: {out}")
    out.parent.mkdir(parents=True, exist_ok=True)
    temp = Path(tempfile.mkdtemp(prefix=f".{out.name}.tmp-", dir=out.parent))
    try:
        ticket = case["manifest"]["source"]["ticket"]
        triage_dir = temp / "workspace" / ticket / "triage"
        triage_dir.mkdir(parents=True)
        shutil.copyfile(case["ticket_path"], triage_dir / "ticket.json")
        skill_dir = temp / "skill" / "recon-triage"
        skill_dir.mkdir(parents=True)
        shutil.copyfile(TRIAGE_SKILL, skill_dir / "SKILL.md")
        verifier_dir = temp / "verifier"
        verifier_dir.mkdir()
        shutil.copyfile(TRIAGE_TOOLS, verifier_dir / "triage-tools.py")
        verifier_path = verifier_dir / "verify-submission.py"
        verifier_path.write_text(REPLAY_VERIFIER, encoding="utf-8")
        verifier_path.chmod(0o755)
        identities_path = verifier_dir / "replay-owner-identities.json"
        identities_path.write_text(
            json.dumps(
                {
                    "schema_version": 1,
                    "kind": "replay-only",
                    "owners": REPLAY_OWNER_IDENTITIES,
                },
                indent=2,
                sort_keys=True,
            )
            + "\n",
            encoding="utf-8",
        )
        (temp / "submission").mkdir()
        export_commit(repo, expected_commit, temp / "target-repo")

        receipt = {
            "schema_version": 2,
            "case_id": case["manifest"]["id"],
            "ticket": ticket,
            "ticket_sha256": case["manifest"]["input"]["sha256"],
            "repository": {
                "name": case["manifest"]["repository"]["name"],
                "commit": expected_commit,
            },
            "skill": {
                "path": "skill/recon-triage/SKILL.md",
                "sha256": file_sha256(TRIAGE_SKILL),
                "source_commit": git_commit(REPO_ROOT),
                "source_dirty": git_dirty(REPO_ROOT),
            },
            "submission": "submission/triage.yaml",
            "verifier": {
                "command": "python3 verifier/verify-submission.py",
                "files": {
                    "verifier/triage-tools.py": file_sha256(verifier_dir / "triage-tools.py"),
                    "verifier/verify-submission.py": file_sha256(verifier_path),
                    "verifier/replay-owner-identities.json": file_sha256(identities_path),
                },
            },
        }
        (temp / "receipt.json").write_text(
            json.dumps(receipt, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
        (temp / "REPLAY.md").write_text(replay_instructions(case), encoding="utf-8")
        if out.exists() or out.is_symlink():
            raise ReplayError(f"output appeared during preparation; refusing overwrite: {out}")
        os.rename(temp, out)
    except Exception:
        if temp.exists():
            shutil.rmtree(temp)
        raise
    return out


def load_triage_module():
    spec = importlib.util.spec_from_file_location("recon_triage_tools", TRIAGE_TOOLS)
    if spec is None or spec.loader is None:
        raise ReplayError(f"cannot load production triage parser: {TRIAGE_TOOLS}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def normalize(value):
    value = unicodedata.normalize("NFKC", value).casefold()
    value = re.sub(r"[^\w]+", " ", value)
    return re.sub(r"\s+", " ", value).strip()


def blocker_text(blocker):
    detail = blocker.get("detail", {})
    values = [blocker.get("title", ""), blocker.get("ask", ""), detail.get("state", "")]
    values.extend(detail.get("options", []))
    return normalize(" ".join(str(value) for value in values if value))


def decision_matches(decision, text):
    return all(any(normalize(signal) in text for signal in group) for group in decision["signals"])


def maximum_matching(edges, blocker_count):
    blocker_to_decision = {}

    def assign(decision_index, seen):
        for blocker_index in edges[decision_index]:
            if blocker_index in seen:
                continue
            seen.add(blocker_index)
            previous = blocker_to_decision.get(blocker_index)
            if previous is None or assign(previous, seen):
                blocker_to_decision[blocker_index] = decision_index
                return True
        return False

    for decision_index in range(len(edges)):
        assign(decision_index, set())
    return {decision: blocker for blocker, decision in blocker_to_decision.items()}


def run_production_verifier(case, candidate):
    with tempfile.TemporaryDirectory(prefix="recon-replay-score-") as temp_name:
        workspace = Path(temp_name) / case["manifest"]["source"]["ticket"]
        triage_dir = workspace / "triage"
        triage_dir.mkdir(parents=True)
        shutil.copyfile(case["ticket_path"], triage_dir / "ticket.json")
        shutil.copyfile(candidate, triage_dir / "triage.yaml")
        return subprocess.run(
            [sys.executable, str(TRIAGE_TOOLS), "verify", str(workspace)],
            capture_output=True,
            text=True,
        )


def run_bundled_verifier(run_dir):
    return subprocess.run(
        [sys.executable, str(run_dir / "verifier" / "verify-submission.py")],
        cwd=run_dir,
        capture_output=True,
        text=True,
    )


def analyze_case(case, candidate_arg, *, run_dir=None):
    candidate = Path(candidate_arg).expanduser()
    if candidate.is_symlink() or not candidate.is_file():
        raise ReplayError(f"candidate must be a regular, non-symlink file: {candidate}")
    candidate = candidate.resolve(strict=True)

    verifier = (
        run_bundled_verifier(run_dir)
        if run_dir is not None
        else run_production_verifier(case, candidate)
    )
    verifier_output = "\n".join(
        part.strip() for part in (verifier.stdout, verifier.stderr) if part.strip()
    )
    if verifier.returncode != 0:
        label = "bundled replay verifier" if run_dir is not None else "production triage verifier"
        lines = [f"artifact: FAIL — {label} exited {verifier.returncode}"]
        if verifier_output:
            lines.append(verifier_output)
        lines.append("decision coverage: NOT_EVALUATED — artifact verification failed")
        lines.append("score: FAIL")
        result = {
            "schema_version": 1,
            "case_id": case["manifest"]["id"],
            "ticket": case["manifest"]["source"]["ticket"],
            "candidate_sha256": file_sha256(candidate),
            "artifact": {"status": "FAIL", "verifier_exit": verifier.returncode},
            "disposition": {
                "status": "NOT_EVALUATED",
                "actual": None,
                "expected": case["oracle"]["expected_disposition"],
            },
            "decision_coverage": {
                "status": "NOT_EVALUATED",
                "matched": 0,
                "total": len(case["oracle"]["required_decisions"]),
                "missed": [],
                "overloaded": [],
            },
            "score": "FAIL",
            "score_exit": 1,
        }
        return result, "\n".join(lines) + "\n"

    lines = ["artifact: PASS — production triage verifier clean"]
    module = load_triage_module()
    parse_errors = []
    document = module.parse_triage(candidate, parse_errors)
    if parse_errors:
        raise ReplayError("production parser disagreed after verification: " + "; ".join(parse_errors))
    actual_disposition = document["scalars"].get("disposition", "")
    expected_disposition = case["oracle"]["expected_disposition"]
    disposition_ok = actual_disposition == expected_disposition
    lines.append(
        f"disposition: {'PASS' if disposition_ok else 'FAIL'} — "
        f"{actual_disposition or '<missing>'}"
        + ("" if disposition_ok else f" (expected {expected_disposition})")
    )

    decisions = case["oracle"]["required_decisions"]
    blockers = document["blockers"]
    texts = [blocker_text(blocker) for blocker in blockers]
    edges = [
        [index for index, text in enumerate(texts) if decision_matches(decision, text)]
        for decision in decisions
    ]
    matching = maximum_matching(edges, len(blockers))
    coverage_ok = len(matching) == len(decisions)
    lines.append(
        f"decision coverage: {'PASS' if coverage_ok else 'FAIL'} — "
        f"{len(matching)}/{len(decisions)} distinct decisions"
    )
    missed = []
    for decision_index, decision in enumerate(decisions):
        if decision_index not in matching:
            missed.append(decision["id"])
            lines.append(f"missed: {decision['id']} — {decision['label']}")
    overloaded = []
    for blocker_index, blocker in enumerate(blockers):
        possible = [
            decisions[decision_index]["id"]
            for decision_index, candidates in enumerate(edges)
            if blocker_index in candidates
        ]
        if len(possible) > 1:
            overloaded.append({"blocker": blocker_index + 1, "decisions": possible})
            lines.append(f"overloaded blocker {blocker_index + 1}: {', '.join(possible)}")

    passed = disposition_ok and coverage_ok
    score_exit = 0 if passed else 1
    lines.append(f"score: {'PASS' if passed else 'FAIL'}")
    result = {
        "schema_version": 1,
        "case_id": case["manifest"]["id"],
        "ticket": case["manifest"]["source"]["ticket"],
        "candidate_sha256": file_sha256(candidate),
        "artifact": {"status": "PASS", "verifier_exit": 0},
        "disposition": {
            "status": "PASS" if disposition_ok else "FAIL",
            "actual": actual_disposition or None,
            "expected": expected_disposition,
        },
        "decision_coverage": {
            "status": "PASS" if coverage_ok else "FAIL",
            "matched": len(matching),
            "total": len(decisions),
            "missed": missed,
            "overloaded": overloaded,
        },
        "score": "PASS" if passed else "FAIL",
        "score_exit": score_exit,
    }
    return result, "\n".join(lines) + "\n"


def score_case(case, candidate_arg):
    result, transcript = analyze_case(case, candidate_arg)
    print(transcript, end="")
    return result["score_exit"]


def safe_run_file(run_dir, relative, label, *, required):
    if not isinstance(relative, str) or not relative:
        raise ReplayError(f"{label} must be a non-empty relative path")
    pure = PurePosixPath(relative)
    if pure.is_absolute() or ".." in pure.parts or "\\" in relative:
        raise ReplayError(f"{label} must stay inside the run directory: {relative}")
    path = run_dir.joinpath(*pure.parts)
    current = run_dir
    for part in pure.parts[:-1]:
        current = current / part
        if current.is_symlink():
            raise ReplayError(f"{label} traverses a symlink: {relative}")
    if path.is_symlink():
        raise ReplayError(f"{label} must not be a symlink: {relative}")
    if required and not path.is_file():
        raise ReplayError(f"{label} must be a regular file: {relative}")
    if not required and path.exists() and not path.is_file():
        raise ReplayError(f"{label} must be a regular file when present: {relative}")
    if path.exists():
        try:
            path.resolve(strict=True).relative_to(run_dir)
        except (OSError, RuntimeError, ValueError) as exc:
            raise ReplayError(f"{label} escapes the run directory: {relative}") from exc
    return path


def validate_receipt(case, run_arg):
    run_dir = Path(run_arg).expanduser()
    if run_dir.is_symlink() or not run_dir.is_dir():
        raise ReplayError(f"run directory does not exist or is a symlink: {run_dir}")
    run_dir = run_dir.resolve(strict=True)
    receipt_path = safe_run_file(run_dir, "receipt.json", "receipt", required=True)
    receipt = read_json(receipt_path, "receipt.json")
    if not isinstance(receipt, dict):
        raise ReplayError("receipt.json must be an object")
    receipt_keys = {
        "schema_version",
        "case_id",
        "ticket",
        "ticket_sha256",
        "repository",
        "skill",
        "submission",
    }
    if receipt.get("schema_version") == 2:
        receipt_keys.add("verifier")
    require_exact_keys(receipt, receipt_keys, "receipt.json")
    if receipt["schema_version"] not in {1, 2}:
        raise ReplayError(f"unsupported receipt schema_version: {receipt['schema_version']}")
    manifest = case["manifest"]
    expected = {
        "case_id": manifest["id"],
        "ticket": manifest["source"]["ticket"],
        "ticket_sha256": manifest["input"]["sha256"],
    }
    for field, expected_value in expected.items():
        if receipt[field] != expected_value:
            raise ReplayError(
                f"receipt {field} mismatch: {receipt[field]!r} != {expected_value!r}"
            )
    require_exact_keys(receipt["repository"], {"name", "commit"}, "receipt.repository")
    if receipt["repository"] != manifest["repository"]:
        raise ReplayError("receipt repository does not match the frozen case")
    require_exact_keys(
        receipt["skill"],
        {"path", "sha256", "source_commit", "source_dirty"},
        "receipt.skill",
    )
    if receipt["skill"]["path"] != "skill/recon-triage/SKILL.md":
        raise ReplayError("receipt skill.path is not the prepared triage skill")
    if not isinstance(receipt["skill"]["sha256"], str) or not SHA256.fullmatch(
        receipt["skill"]["sha256"]
    ):
        raise ReplayError("receipt skill.sha256 must be a lowercase 64-character SHA-256")
    if not isinstance(receipt["skill"]["source_commit"], str) or not OBJECT_ID.fullmatch(
        receipt["skill"]["source_commit"]
    ):
        raise ReplayError("receipt skill.source_commit must be a full object ID")
    if not isinstance(receipt["skill"]["source_dirty"], bool):
        raise ReplayError("receipt skill.source_dirty must be boolean")
    if receipt["submission"] != "submission/triage.yaml":
        raise ReplayError("receipt submission must be submission/triage.yaml")

    if receipt["schema_version"] == 2:
        verifier = receipt["verifier"]
        require_exact_keys(verifier, {"command", "files"}, "receipt.verifier")
        if verifier["command"] != "python3 verifier/verify-submission.py":
            raise ReplayError("receipt verifier command is not the prepared replay verifier")
        expected_files = {
            "verifier/triage-tools.py",
            "verifier/verify-submission.py",
            "verifier/replay-owner-identities.json",
        }
        if not isinstance(verifier["files"], dict) or set(verifier["files"]) != expected_files:
            raise ReplayError("receipt verifier files are incomplete or unknown")
        for relative, digest in verifier["files"].items():
            if not isinstance(digest, str) or not SHA256.fullmatch(digest):
                raise ReplayError(f"receipt verifier hash is invalid: {relative}")
            prepared_file = safe_run_file(run_dir, relative, "prepared verifier", required=True)
            if file_sha256(prepared_file) != digest:
                raise ReplayError(f"prepared verifier hash drift: {relative}")
        if not os.access(run_dir / "verifier" / "verify-submission.py", os.X_OK):
            raise ReplayError("prepared replay verifier is not executable")

    ticket_relative = f"workspace/{receipt['ticket']}/triage/ticket.json"
    ticket_path = safe_run_file(run_dir, ticket_relative, "prepared ticket", required=True)
    if file_sha256(ticket_path) != receipt["ticket_sha256"]:
        raise ReplayError("prepared ticket hash drift")
    skill_path = safe_run_file(run_dir, receipt["skill"]["path"], "prepared skill", required=True)
    if file_sha256(skill_path) != receipt["skill"]["sha256"]:
        raise ReplayError("prepared skill hash drift")
    safe_run_file(run_dir, "REPLAY.md", "replay instructions", required=True)
    target_repo = run_dir / "target-repo"
    if target_repo.is_symlink() or not target_repo.is_dir():
        raise ReplayError("prepared target-repo must be a regular directory")
    return run_dir, receipt


def validate_result(case, run_dir, receipt, candidate, score_path, result_path):
    result = read_json(result_path, "evaluation/result.json")
    require_exact_keys(
        result,
        {
            "schema_version",
            "case_id",
            "ticket",
            "submission",
            "candidate_sha256",
            "score_sha256",
            "artifact",
            "disposition",
            "decision_coverage",
            "score",
            "score_exit",
        },
        "evaluation/result.json",
    )
    if result["schema_version"] != 1:
        raise ReplayError("evaluation/result.json has unsupported schema_version")
    for field, expected in (
        ("case_id", case["manifest"]["id"]),
        ("ticket", case["manifest"]["source"]["ticket"]),
        ("submission", receipt["submission"]),
        ("candidate_sha256", file_sha256(candidate)),
        ("score_sha256", file_sha256(score_path)),
    ):
        if result[field] != expected:
            raise ReplayError(f"evaluation result {field} mismatch or drift")
    if result["score_exit"] not in (0, 1):
        raise ReplayError("evaluation result score_exit must be 0 or 1")
    expected_score = "PASS" if result["score_exit"] == 0 else "FAIL"
    if result["score"] != expected_score:
        raise ReplayError("evaluation result score disagrees with score_exit")

    artifact = result["artifact"]
    require_exact_keys(artifact, {"status", "verifier_exit"}, "evaluation artifact")
    if artifact["status"] not in {"PASS", "FAIL"}:
        raise ReplayError("evaluation artifact status must be PASS or FAIL")
    if not isinstance(artifact["verifier_exit"], int) or artifact["verifier_exit"] < 0:
        raise ReplayError("evaluation artifact verifier_exit must be non-negative")
    if (artifact["verifier_exit"] == 0) != (artifact["status"] == "PASS"):
        raise ReplayError("evaluation artifact status disagrees with verifier_exit")

    disposition = result["disposition"]
    require_exact_keys(
        disposition, {"status", "actual", "expected"}, "evaluation disposition"
    )
    if disposition["expected"] != case["oracle"]["expected_disposition"]:
        raise ReplayError("evaluation disposition expected value drift")
    if disposition["status"] not in {"PASS", "FAIL", "NOT_EVALUATED"}:
        raise ReplayError("evaluation disposition has invalid status")
    if disposition["status"] == "NOT_EVALUATED":
        if artifact["status"] != "FAIL" or disposition["actual"] is not None:
            raise ReplayError("unevaluated disposition disagrees with artifact result")
    elif disposition["actual"] not in DISPOSITIONS:
        raise ReplayError("evaluated disposition actual value is invalid")
    elif (disposition["actual"] == disposition["expected"]) != (
        disposition["status"] == "PASS"
    ):
        raise ReplayError("evaluation disposition status disagrees with values")

    coverage = result["decision_coverage"]
    require_exact_keys(
        coverage,
        {"status", "matched", "total", "missed", "overloaded"},
        "evaluation decision_coverage",
    )
    decision_ids = {item["id"] for item in case["oracle"]["required_decisions"]}
    total = len(decision_ids)
    if coverage["status"] not in {"PASS", "FAIL", "NOT_EVALUATED"}:
        raise ReplayError("evaluation decision_coverage has invalid status")
    if coverage["total"] != total:
        raise ReplayError("evaluation decision_coverage total drift")
    if not isinstance(coverage["matched"], int) or not 0 <= coverage["matched"] <= total:
        raise ReplayError("evaluation decision_coverage matched is out of range")
    if not isinstance(coverage["missed"], list) or any(
        not isinstance(item, str) or item not in decision_ids for item in coverage["missed"]
    ):
        raise ReplayError("evaluation decision_coverage missed contains invalid IDs")
    if len(set(coverage["missed"])) != len(coverage["missed"]):
        raise ReplayError("evaluation decision_coverage missed contains duplicates")
    if not isinstance(coverage["overloaded"], list):
        raise ReplayError("evaluation decision_coverage overloaded must be a list")
    for index, overload in enumerate(coverage["overloaded"], 1):
        require_exact_keys(
            overload, {"blocker", "decisions"}, f"evaluation overload {index}"
        )
        if not isinstance(overload["blocker"], int) or overload["blocker"] < 1:
            raise ReplayError(f"evaluation overload {index} has invalid blocker")
        overload_decisions = overload["decisions"]
        if (
            not isinstance(overload_decisions, list)
            or len(overload_decisions) < 2
            or any(item not in decision_ids for item in overload_decisions)
        ):
            raise ReplayError(f"evaluation overload {index} has invalid decisions")
    if coverage["status"] == "NOT_EVALUATED":
        if artifact["status"] != "FAIL" or coverage["matched"] != 0 or coverage["missed"]:
            raise ReplayError("unevaluated decision coverage disagrees with artifact result")
    else:
        if len(coverage["missed"]) != total - coverage["matched"]:
            raise ReplayError("evaluation decision coverage counts disagree")
        if (coverage["matched"] == total) != (coverage["status"] == "PASS"):
            raise ReplayError("evaluation decision coverage status disagrees with counts")

    passed_components = (
        artifact["status"] == "PASS"
        and disposition["status"] == "PASS"
        and coverage["status"] == "PASS"
    )
    if passed_components != (result["score"] == "PASS"):
        raise ReplayError("evaluation score disagrees with component results")
    score_text = score_path.read_text(encoding="utf-8")
    if not score_text.endswith(f"score: {result['score']}\n"):
        raise ReplayError("evaluation score.txt disagrees with result score")
    return result


def derive_run_state(case, run_arg):
    run_dir, receipt = validate_receipt(case, run_arg)
    candidate = safe_run_file(
        run_dir, receipt["submission"], "submission", required=False
    )
    evaluation = run_dir / EVALUATION_DIR
    if evaluation.is_symlink():
        raise ReplayError("evaluation directory must not be a symlink")
    if evaluation.exists() and not evaluation.is_dir():
        raise ReplayError("evaluation must be a directory when present")

    candidate_present = candidate.is_file()
    evaluation_present = evaluation.is_dir()
    if not candidate_present and not evaluation_present:
        return "PREPARED", run_dir, receipt, None
    if not candidate_present and evaluation_present:
        raise ReplayError("evaluation exists before submission")
    if candidate_present and not evaluation_present:
        return "SUBMITTED", run_dir, receipt, None

    score_path = safe_run_file(
        run_dir, f"{EVALUATION_DIR}/score.txt", "evaluation score", required=True
    )
    result_path = safe_run_file(
        run_dir, f"{EVALUATION_DIR}/result.json", "evaluation result", required=True
    )
    result = validate_result(case, run_dir, receipt, candidate, score_path, result_path)
    return "SCORED", run_dir, receipt, result


def print_run_state(case, run_arg):
    state, run_dir, receipt, result = derive_run_state(case, run_arg)
    print(f"state: {state} — {case['manifest']['id']}; run {run_dir}")
    if state == "PREPARED":
        print(
            f"next: launch a fresh LLM context in {run_dir} and follow REPLAY.md; "
            "return after writing submission/triage.yaml"
        )
    elif state == "SUBMITTED":
        run_path = shlex.quote(str(run_dir))
        canonical_case = REPO_ROOT / "evals" / "cases" / case["manifest"]["id"]
        case_option = ""
        if case["dir"] != canonical_case.resolve():
            case_option = f" --case {shlex.quote(str(case['dir']))}"
        print(f"next: python3 tools/replay-ticket.py evaluate {run_path}{case_option}")
    else:
        print(
            f"result: {result['score']} — {result['decision_coverage']['matched']}/"
            f"{result['decision_coverage']['total']} distinct decisions"
        )
        print("next: read evaluation/result.json and evaluation/score.txt; evaluation is final")
    return 0


def evaluate_run(case, run_arg):
    state, run_dir, receipt, _ = derive_run_state(case, run_arg)
    if state != "SUBMITTED":
        raise ReplayError(f"evaluate requires SUBMITTED, found {state}")
    candidate = safe_run_file(run_dir, receipt["submission"], "submission", required=True)
    if receipt["schema_version"] == 2:
        verifier = run_bundled_verifier(run_dir)
        if verifier.returncode != 0:
            output = "\n".join(
                part.strip() for part in (verifier.stdout, verifier.stderr) if part.strip()
            )
            raise ReplayError(
                "submission verifier failed before evaluation; fix the submission and rerun "
                "the prepared command" + (f"\n{output}" if output else "")
            )
    result, transcript = analyze_case(
        case, candidate, run_dir=run_dir if receipt["schema_version"] == 2 else None
    )
    result["submission"] = receipt["submission"]
    result["score_sha256"] = hashlib.sha256(transcript.encode("utf-8")).hexdigest()

    evaluation = run_dir / EVALUATION_DIR
    temp = Path(tempfile.mkdtemp(prefix=".evaluation.tmp-", dir=run_dir))
    try:
        (temp / "score.txt").write_text(transcript, encoding="utf-8")
        (temp / "result.json").write_text(
            json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
        try:
            evaluation.mkdir()
        except FileExistsError as exc:
            raise ReplayError(f"evaluation already exists; refusing overwrite: {evaluation}") from exc
        try:
            os.rename(temp / "score.txt", evaluation / "score.txt")
            os.rename(temp / "result.json", evaluation / "result.json")
        except Exception:
            shutil.rmtree(evaluation, ignore_errors=True)
            raise
    finally:
        if temp.exists():
            shutil.rmtree(temp)

    print(transcript, end="")
    print(f"evaluate: retained — {evaluation / 'score.txt'}")
    print(f"evaluate: retained — {evaluation / 'result.json'}")
    return result["score_exit"]


def infer_case_dir(run_arg):
    run_dir = Path(run_arg).expanduser()
    if run_dir.is_symlink() or not run_dir.is_dir():
        raise ReplayError(f"run directory does not exist or is a symlink: {run_dir}")
    run_dir = run_dir.resolve(strict=True)
    receipt_path = safe_run_file(run_dir, "receipt.json", "receipt", required=True)
    receipt = read_json(receipt_path, "receipt.json")
    case_id = receipt.get("case_id") if isinstance(receipt, dict) else None
    if not isinstance(case_id, str) or not CASE_ID.fullmatch(case_id):
        raise ReplayError("receipt case_id cannot identify a repository case")
    return REPO_ROOT / "evals" / "cases" / case_id


def build_parser():
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    validate = subparsers.add_parser("validate", help="validate a frozen case")
    validate.add_argument("case_dir")
    prepare = subparsers.add_parser("prepare", help="prepare an oracle-free replay directory")
    prepare.add_argument("case_dir")
    prepare.add_argument("--repo", required=True, help="target repository containing the frozen commit")
    prepare.add_argument("--out", required=True, help="new output directory; overwrite is forbidden")
    score = subparsers.add_parser("score", help="score one retained triage.yaml")
    score.add_argument("case_dir")
    score.add_argument("candidate")
    state = subparsers.add_parser("state", help="derive a prepared run's persisted state")
    state.add_argument("run_dir")
    state.add_argument("--case", dest="case_dir", help="override case path for isolated fixtures")
    evaluate = subparsers.add_parser(
        "evaluate", help="score a submitted run and retain an immutable evaluation"
    )
    evaluate.add_argument("run_dir")
    evaluate.add_argument("--case", dest="case_dir", help="override case path for isolated fixtures")
    return parser


def main(argv=None):
    args = build_parser().parse_args(argv)
    try:
        case_arg = args.case_dir
        if args.command in {"state", "evaluate"} and case_arg is None:
            case_arg = infer_case_dir(args.run_dir)
        case = validate_case(case_arg)
        if args.command == "validate":
            print(
                f"case: clean — {case['manifest']['id']}, ticket "
                f"{case['manifest']['source']['ticket']}, "
                f"{len(case['oracle']['required_decisions'])} decision(s), oracle separated"
            )
            return 0
        if args.command == "prepare":
            out = prepare_case(case, args.repo, args.out)
            print(
                f"prepare: clean — {case['manifest']['id']} at "
                f"{case['manifest']['repository']['commit']}; oracle excluded; wrote {out}"
            )
            return 0
        if args.command == "score":
            return score_case(case, args.candidate)
        if args.command == "state":
            return print_run_state(case, args.run_dir)
        if args.command == "evaluate":
            return evaluate_run(case, args.run_dir)
        raise ReplayError(f"unknown command: {args.command}")
    except ReplayError as exc:
        print(f"REPLAY: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
