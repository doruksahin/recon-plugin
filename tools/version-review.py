#!/usr/bin/env python3
"""Operate private, version-scoped team review cycles for Recon dossiers."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from datetime import UTC, datetime
from pathlib import Path, PurePosixPath
from urllib.parse import urlparse

import yaml


REPO_ROOT = Path(__file__).resolve().parents[1]
CONTRACT_ROOT = REPO_ROOT / "evals/version-reviews"
SOURCE_SCHEMA = CONTRACT_ROOT / "schema.yaml"
SOURCE_TEMPLATES = CONTRACT_ROOT / "templates"
SEMVER = re.compile(
    r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\Z"
)
OBJECT_ID = re.compile(r"[0-9a-f]{40}\Z")
SHA256 = re.compile(r"[0-9a-f]{64}\Z")
SAFE_ID = re.compile(r"[A-Za-z0-9]+(?:[-_.][A-Za-z0-9]+)*\Z")
TICKET_ID = re.compile(r"[A-Za-z][A-Za-z0-9]*-[0-9]+\Z")
FINDING_ID = re.compile(r"[A-Z]+-[0-9]+\Z")
UTC_STAMP = re.compile(r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\Z")
GITHUB_REPOSITORY = re.compile(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\Z")
PUBLIC_PLUGIN_REPOSITORIES = {
    "adcreative-ai/recon-plugin",
    "doruksahin/recon-plugin",
}
GH_COMMAND = os.environ.get("RECON_VERSION_REVIEW_GH", "gh")
GIT_LOCAL_ENVIRONMENT = {
    "GIT_ALTERNATE_OBJECT_DIRECTORIES",
    "GIT_COMMON_DIR",
    "GIT_DIR",
    "GIT_INDEX_FILE",
    "GIT_OBJECT_DIRECTORY",
    "GIT_PREFIX",
    "GIT_WORK_TREE",
}


class ReviewError(Exception):
    """Stable contract failure for a version-review cycle."""


def fail(message: str) -> None:
    raise ReviewError(message)


def now_utc() -> str:
    return datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%SZ")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def absolute_without_resolving(path: Path) -> Path:
    expanded = path.expanduser()
    absolute = expanded if expanded.is_absolute() else Path.cwd() / expanded
    # macOS exposes /tmp, /var, and /etc as root-level compatibility symlinks.
    # Normalize only those operating-system aliases; later path components
    # remain unresolved so caller-controlled symlink ancestors still fail.
    if len(absolute.parts) > 1:
        alias = Path(absolute.anchor) / absolute.parts[1]
        if alias.parent == Path(absolute.anchor) and alias.is_symlink():
            try:
                suffix = absolute.relative_to(alias)
                absolute = alias.resolve(strict=True) / suffix
            except (OSError, ValueError) as exc:
                fail(f"cannot normalize operating-system path alias {alias}: {exc}")
    return absolute


def require_no_symlinks(path: Path, label: str) -> None:
    absolute = absolute_without_resolving(path)
    for component in reversed((absolute, *absolute.parents)):
        try:
            if component.is_symlink():
                fail(f"{label} has a symlink ancestor or leaf: {component}")
        except OSError as exc:
            fail(f"cannot inspect {label}: {exc}")


def require_real_directory(path: Path, label: str) -> Path:
    require_no_symlinks(path, label)
    if not path.is_dir():
        fail(f"{label} must be a real directory: {path}")
    return path.resolve(strict=True)


def require_regular(path: Path, label: str) -> Path:
    require_no_symlinks(path, label)
    if not path.is_file():
        fail(f"{label} must be a regular file: {path}")
    return path


def require_nonempty(value: object, label: str) -> str:
    if not isinstance(value, str) or not value.strip():
        fail(f"{label} must be a non-empty string")
    return value


def require_keys(value: dict, expected: set[str], label: str) -> None:
    missing = sorted(expected - set(value))
    if missing:
        fail(f"{label} missing field(s): {', '.join(missing)}")


def require_exact_keys(value: dict, expected: set[str], label: str) -> None:
    require_keys(value, expected, label)
    extra = sorted(set(value) - expected)
    if extra:
        fail(f"{label} has unknown field(s): {', '.join(extra)}")


def require_semver(value: object, label: str) -> str:
    if not isinstance(value, str) or not SEMVER.fullmatch(value):
        fail(f"{label} must be a stable X.Y.Z version")
    return value


def require_hash(value: object, label: str) -> str:
    if not isinstance(value, str) or not SHA256.fullmatch(value):
        fail(f"{label} must be a lowercase SHA-256")
    return value


def require_object_id(value: object, label: str) -> str:
    if not isinstance(value, str) or not OBJECT_ID.fullmatch(value):
        fail(f"{label} must be a full lowercase 40-character commit")
    return value


def require_timestamp(value: object, label: str) -> str:
    if not isinstance(value, str) or not UTC_STAMP.fullmatch(value):
        fail(f"{label} must be UTC YYYY-MM-DDTHH:MM:SSZ")
    return value


def require_list(value: object, label: str, *, nonempty: bool = False) -> list:
    if not isinstance(value, list) or (nonempty and not value):
        suffix = " non-empty" if nonempty else ""
        fail(f"{label} must be a{suffix} list")
    return value


def read_yaml(path: Path, label: str) -> dict:
    require_regular(path, label)
    try:
        value = yaml.safe_load(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, yaml.YAMLError) as exc:
        fail(f"{label} is not valid UTF-8 YAML: {exc}")
    if not isinstance(value, dict):
        fail(f"{label} must be an object")
    return value


def read_json(path: Path, label: str) -> dict:
    require_regular(path, label)
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        fail(f"{label} is not valid UTF-8 JSON: {exc}")
    if not isinstance(value, dict):
        fail(f"{label} must be an object")
    return value


def yaml_bytes(value: object) -> bytes:
    return yaml.safe_dump(value, sort_keys=False, allow_unicode=True).encode("utf-8")


def write_atomic(path: Path, payload: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    require_no_symlinks(path.parent, f"output parent for {path.name}")
    descriptor, temp_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    temp = Path(temp_name)
    try:
        with os.fdopen(descriptor, "wb") as handle:
            handle.write(payload)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temp, path)
    finally:
        if temp.exists():
            temp.unlink()


def write_yaml(path: Path, value: object) -> None:
    write_atomic(path, yaml_bytes(value))


def write_json(path: Path, value: object) -> None:
    payload = json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False) + "\n"
    write_atomic(path, payload.encode("utf-8"))


def atomic_directory(destination: Path, builder) -> None:
    require_no_symlinks(destination.parent, "destination parent")
    if destination.exists() or destination.is_symlink():
        fail(f"destination already exists: {destination}")
    temp = Path(tempfile.mkdtemp(prefix=f".{destination.name}.", dir=destination.parent))
    try:
        builder(temp)
        os.replace(temp, destination)
    except Exception:
        shutil.rmtree(temp, ignore_errors=True)
        raise


def enum(schema: dict, name: str) -> set[str]:
    values = schema.get("enums", {}).get(name)
    if not isinstance(values, list) or not all(isinstance(item, str) for item in values):
        fail(f"contract enum {name} is invalid")
    return set(values)


def document_keys(schema: dict, name: str) -> set[str]:
    values = schema.get("documents", {}).get(name, {}).get("required")
    if not isinstance(values, list) or not all(isinstance(item, str) for item in values):
        fail(f"contract document {name} is invalid")
    return set(values)


def validate_schema(schema: dict) -> dict:
    if schema.get("schema_version") != 1:
        fail("version-review schema_version must be 1")
    lifecycle = schema.get("lifecycle")
    capture = schema.get("capture_paths")
    if not isinstance(lifecycle, dict) or not isinstance(capture, dict):
        fail("version-review schema lifecycle/capture_paths must be objects")
    states = lifecycle.get("states")
    transitions = lifecycle.get("transitions")
    if states != ["COLLECTING", "REVIEWING", "SYNTHESIZED", "CLOSED"]:
        fail("version-review lifecycle states are invalid")
    if not isinstance(transitions, dict) or set(transitions) != set(states):
        fail("version-review lifecycle transitions are invalid")
    for key in ("required", "optional", "excluded"):
        values = capture.get(key)
        if not isinstance(values, list) or not all(isinstance(item, str) for item in values):
            fail(f"version-review capture_paths.{key} must be a string list")
    for name in (
        "review_overall",
        "finding_category",
        "severity",
        "consensus_decision",
        "proposed_action",
        "theme_decision",
    ):
        enum(schema, name)
    for name in ("review", "consensus", "findings", "themes", "decisions", "closure"):
        document_keys(schema, name)
    return schema


def load_source_schema() -> dict:
    return validate_schema(read_yaml(SOURCE_SCHEMA, "source version-review schema"))


def version_path(review_root: Path, version: str) -> Path:
    return review_root / "versions" / f"v{version}"


def require_review_root(path: Path) -> Path:
    return require_real_directory(path, "review root")


def command_output(command: list[str], label: str, *, environment: dict | None = None) -> str:
    try:
        result = subprocess.run(
            command,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
            env=environment,
        )
    except OSError as exc:
        fail(f"{label} is unavailable: {exc}")
    if result.returncode:
        detail = (result.stderr or result.stdout).strip()
        fail(f"{label} failed" + (f": {detail}" if detail else ""))
    return result.stdout.strip()


def local_git_environment() -> dict:
    environment = os.environ.copy()
    for name in GIT_LOCAL_ENVIRONMENT:
        environment.pop(name, None)
    return environment


def github_repository_from_remote(remote: str) -> str:
    value = remote.strip().rstrip("/")
    path = ""
    if value.startswith("git@github.com:"):
        path = value.removeprefix("git@github.com:")
    else:
        parsed = urlparse(value)
        if parsed.scheme not in {"https", "ssh"} or parsed.hostname != "github.com":
            fail("review root origin must be a GitHub HTTPS or SSH remote")
        path = parsed.path.lstrip("/")
    if path.endswith(".git"):
        path = path[:-4]
    if not GITHUB_REPOSITORY.fullmatch(path):
        fail("review root origin must identify one GitHub owner/repository")
    return path


def local_storage_identity(review_root: Path) -> dict:
    try:
        review_root.relative_to(REPO_ROOT.resolve(strict=True))
    except ValueError:
        pass
    else:
        fail("review root must be outside the Recon plugin repository")
    top_level = command_output(
        ["git", "-C", str(review_root), "rev-parse", "--show-toplevel"],
        "review root Git worktree lookup",
        environment=local_git_environment(),
    )
    try:
        top = Path(top_level).resolve(strict=True)
    except OSError as exc:
        fail(f"review root Git top level is invalid: {exc}")
    if top != review_root:
        fail("review root must be the top level of its Git worktree")
    remote = command_output(
        ["git", "-C", str(review_root), "config", "--get", "remote.origin.url"],
        "review root origin lookup",
        environment=local_git_environment(),
    )
    repository = github_repository_from_remote(remote)
    if repository.casefold() in PUBLIC_PLUGIN_REPOSITORIES:
        fail("public Recon plugin repositories cannot store live review evidence")
    return {"provider": "github", "repository": repository, "remote": remote}


def live_private_storage(review_root: Path, expected: dict | None = None) -> dict:
    local = local_storage_identity(review_root)
    if expected is not None:
        for field in ("provider", "repository", "remote"):
            if local[field] != expected[field]:
                fail(f"review root storage {field} drift")
    raw = command_output(
        [
            GH_COMMAND,
            "repo",
            "view",
            local["repository"],
            "--json",
            "nameWithOwner,visibility,url",
        ],
        "GitHub private-repository lookup",
    )
    try:
        details = json.loads(raw)
    except json.JSONDecodeError as exc:
        fail(f"GitHub private-repository lookup returned invalid JSON: {exc}")
    if not isinstance(details, dict):
        fail("GitHub private-repository lookup must return an object")
    require_exact_keys(details, {"nameWithOwner", "visibility", "url"}, "GitHub repository")
    repository = require_nonempty(details["nameWithOwner"], "GitHub repository nameWithOwner")
    if repository.casefold() != local["repository"].casefold():
        fail("GitHub repository identity disagrees with review root origin")
    if details["visibility"] != "PRIVATE":
        fail("review repository must have PRIVATE GitHub visibility")
    require_nonempty(details["url"], "GitHub repository url")
    return {
        **local,
        "repository": repository,
        "visibility": "PRIVATE",
        "verified_at": now_utc(),
    }


def validate_local_storage(review_root: Path, value: object) -> dict:
    if not isinstance(value, dict):
        fail("version.yaml storage must be an object")
    require_exact_keys(
        value,
        {"provider", "repository", "visibility", "remote", "verified_at"},
        "version.yaml storage",
    )
    if value["provider"] != "github" or value["visibility"] != "PRIVATE":
        fail("version.yaml storage provider/visibility is invalid")
    repository = require_nonempty(value["repository"], "version.yaml storage.repository")
    if not GITHUB_REPOSITORY.fullmatch(repository):
        fail("version.yaml storage.repository must be owner/repository")
    require_nonempty(value["remote"], "version.yaml storage.remote")
    require_timestamp(value["verified_at"], "version.yaml storage.verified_at")
    local = local_storage_identity(review_root)
    for field in ("provider", "repository", "remote"):
        if local[field] != value[field]:
            fail(f"review root storage {field} drift")
    return value


def reverify_mutation_storage(review_root: Path, version_doc: dict) -> None:
    live_private_storage(review_root, version_doc["storage"])


def safe_id(value: object, label: str) -> str:
    if not isinstance(value, str) or not SAFE_ID.fullmatch(value):
        fail(f"{label} must use letters, numbers, dash, underscore, or dot")
    return value


def ticket_id(value: object, label: str = "ticket") -> str:
    if not isinstance(value, str) or not TICKET_ID.fullmatch(value):
        fail(f"{label} must look like ATT-1234")
    return value


def load_cycle(review_root_arg: Path, version_arg: str) -> tuple[Path, dict, dict]:
    review_root = require_review_root(review_root_arg)
    version = require_semver(version_arg, "plugin version")
    directory = version_path(review_root, version)
    require_real_directory(directory, "version directory")
    version_doc = read_yaml(directory / "version.yaml", "version.yaml")
    required = {
        "schema_version",
        "plugin",
        "storage",
        "status",
        "opened_at",
        "closed_at",
        "contract",
        "non_claims",
    }
    require_exact_keys(version_doc, required, "version.yaml")
    if version_doc["schema_version"] != 1:
        fail("version.yaml schema_version must be 1")
    plugin = version_doc["plugin"]
    if not isinstance(plugin, dict):
        fail("version.yaml plugin must be an object")
    require_exact_keys(plugin, {"version", "tag", "commit"}, "version.yaml plugin")
    if require_semver(plugin["version"], "version.yaml plugin.version") != version:
        fail("version directory disagrees with version.yaml plugin.version")
    if plugin["tag"] != f"v{version}":
        fail("version.yaml plugin.tag must match plugin.version")
    require_object_id(plugin["commit"], "version.yaml plugin.commit")
    require_timestamp(version_doc["opened_at"], "version.yaml opened_at")
    if version_doc["closed_at"] is not None:
        require_timestamp(version_doc["closed_at"], "version.yaml closed_at")
    require_list(version_doc["non_claims"], "version.yaml non_claims", nonempty=True)
    validate_local_storage(review_root, version_doc["storage"])
    contract = version_doc["contract"]
    if not isinstance(contract, dict):
        fail("version.yaml contract must be an object")
    require_exact_keys(contract, {"schema_sha256", "templates"}, "version.yaml contract")
    require_hash(contract["schema_sha256"], "version.yaml contract.schema_sha256")
    if not isinstance(contract["templates"], dict) or not contract["templates"]:
        fail("version.yaml contract.templates must be a non-empty object")

    pinned_schema_path = directory / "contract/schema.yaml"
    if sha256(require_regular(pinned_schema_path, "pinned schema")) != contract["schema_sha256"]:
        fail("pinned schema hash drift")
    schema = validate_schema(read_yaml(pinned_schema_path, "pinned schema"))
    template_dir = require_real_directory(directory / "contract/templates", "pinned templates")
    actual_templates = {path.name for path in template_dir.iterdir() if path.is_file()}
    if actual_templates != set(contract["templates"]):
        fail("pinned template set drift")
    for name, expected_hash in contract["templates"].items():
        require_hash(expected_hash, f"template hash for {name}")
        if sha256(require_regular(template_dir / name, f"pinned template {name}")) != expected_hash:
            fail(f"pinned template hash drift: {name}")
    states = schema["lifecycle"]["states"]
    if version_doc["status"] not in states:
        fail("version.yaml status is invalid")
    return directory, version_doc, schema


def repo_proposal_path(raw: object, label: str) -> str:
    value = require_nonempty(raw, label)
    posix = PurePosixPath(value)
    if posix.is_absolute() or ".." in posix.parts or "\\" in value:
        fail(f"{label} must be a repository-relative proposal path")
    if tuple(posix.parts[:2]) != ("docs", "improvement-proposals"):
        fail(f"{label} must stay under docs/improvement-proposals")
    path = REPO_ROOT.joinpath(*posix.parts)
    require_no_symlinks(path, label)
    if not path.is_dir():
        fail(f"{label} does not exist: {value}")
    return value


def receipt_join_value(receipt: dict, field: str) -> object:
    if field == "plugin_version":
        return receipt["plugin"]["version"]
    if field == "report_sha256":
        return receipt["artifacts"]["report/dossier.html"]
    return receipt[field]


def validate_review(value: dict, schema: dict, receipt: dict, label: str) -> dict:
    require_exact_keys(value, document_keys(schema, "review"), label)
    if value["schema_version"] != 1:
        fail(f"{label} schema_version must be 1")
    review_id = safe_id(value["review_id"], f"{label} review_id")
    require_nonempty(value["reviewer"], f"{label} reviewer")
    require_timestamp(value["reviewed_at"], f"{label} reviewed_at")
    for field in ("plugin_version", "ticket", "run_id", "report_sha256"):
        expected = receipt_join_value(receipt, field)
        if value[field] != expected:
            fail(f"{label} {field} disagrees with captured receipt")
    require_hash(value["report_sha256"], f"{label} report_sha256")
    if value["overall"] not in enum(schema, "review_overall"):
        fail(f"{label} overall is invalid")
    findings = require_list(value["findings"], f"{label} findings")
    seen: set[str] = set()
    required_finding = {
        "id",
        "category",
        "artifact_ref",
        "observed",
        "expected",
        "impact",
        "severity",
        "evidence",
    }
    for index, finding in enumerate(findings, 1):
        item_label = f"{label} finding {index}"
        if not isinstance(finding, dict):
            fail(f"{item_label} must be an object")
        require_exact_keys(finding, required_finding, item_label)
        finding_id_value = finding["id"]
        if not isinstance(finding_id_value, str) or not FINDING_ID.fullmatch(finding_id_value):
            fail(f"{item_label} id must look like REV-1")
        if finding_id_value in seen:
            fail(f"{label} duplicates finding id {finding_id_value}")
        seen.add(finding_id_value)
        if finding["category"] not in enum(schema, "finding_category"):
            fail(f"{item_label} category is invalid")
        if finding["severity"] not in enum(schema, "severity"):
            fail(f"{item_label} severity is invalid")
        for key in required_finding - {"id", "category", "severity"}:
            require_nonempty(finding[key], f"{item_label} {key}")
    value["review_id"] = review_id
    return value


def validate_consensus(value: dict, schema: dict, receipt: dict, reviews: dict[str, dict], label: str) -> dict:
    require_exact_keys(value, document_keys(schema, "consensus"), label)
    if value["schema_version"] != 1:
        fail(f"{label} schema_version must be 1")
    for field in ("plugin_version", "ticket", "run_id", "report_sha256"):
        expected = receipt_join_value(receipt, field)
        if value[field] != expected:
            fail(f"{label} {field} disagrees with captured receipt")
    participants = require_list(value["participants"], f"{label} participants", nonempty=True)
    if len(set(participants)) != len(participants) or not all(isinstance(item, str) and item.strip() for item in participants):
        fail(f"{label} participants must be unique non-empty strings")
    if value["decision"] not in enum(schema, "consensus_decision"):
        fail(f"{label} decision is invalid")
    finding_lookup = {
        (review_id, finding["id"])
        for review_id, review in reviews.items()
        for finding in review["findings"]
    }
    seen_refs: set[tuple[str, str]] = set()
    for group in ("accepted_findings", "disputed_findings"):
        entries = require_list(value[group], f"{label} {group}")
        for index, entry in enumerate(entries, 1):
            item_label = f"{label} {group} {index}"
            if not isinstance(entry, dict):
                fail(f"{item_label} must be an object")
            require_exact_keys(entry, {"review_id", "finding_id", "reason"}, item_label)
            reference = (entry["review_id"], entry["finding_id"])
            if reference not in finding_lookup:
                fail(f"{item_label} references an unknown review finding")
            if reference in seen_refs:
                fail(f"{label} repeats review finding reference {reference[0]}/{reference[1]}")
            seen_refs.add(reference)
            require_nonempty(entry["reason"], f"{item_label} reason")
    observations = require_list(value["correct_observations"], f"{label} correct_observations")
    if not all(isinstance(item, str) and item.strip() for item in observations):
        fail(f"{label} correct_observations must contain non-empty strings")
    return value


def validate_run(run_dir: Path, schema: dict) -> dict:
    receipt = read_yaml(run_dir / "receipt.yaml", f"{run_dir.name} receipt")
    required_receipt = {
        "schema_version",
        "ticket",
        "run_id",
        "plugin",
        "source",
        "target",
        "jira_delivery",
        "captured_at",
        "artifacts",
    }
    require_exact_keys(receipt, required_receipt, f"{run_dir.name} receipt")
    if receipt["schema_version"] != 1:
        fail(f"{run_dir.name} receipt schema_version must be 1")
    ticket_id(receipt["ticket"], f"{run_dir.name} receipt ticket")
    safe_id(receipt["run_id"], f"{run_dir.name} receipt run_id")
    if receipt["ticket"] != run_dir.parents[1].name or receipt["run_id"] != run_dir.name:
        fail(f"{run_dir.name} receipt path identity drift")
    plugin = receipt["plugin"]
    if not isinstance(plugin, dict):
        fail(f"{run_dir.name} receipt plugin must be an object")
    require_exact_keys(plugin, {"version", "tag", "commit"}, f"{run_dir.name} receipt plugin")
    version = require_semver(plugin["version"], f"{run_dir.name} receipt plugin.version")
    if plugin["tag"] != f"v{version}":
        fail(f"{run_dir.name} receipt plugin tag drift")
    require_object_id(plugin["commit"], f"{run_dir.name} receipt plugin.commit")
    require_timestamp(receipt["captured_at"], f"{run_dir.name} receipt captured_at")
    for section in ("source", "target", "jira_delivery"):
        if not isinstance(receipt[section], dict):
            fail(f"{run_dir.name} receipt {section} must be an object")
    require_exact_keys(receipt["source"], {"workspace", "started", "host", "surface"}, f"{run_dir.name} receipt source")
    require_exact_keys(receipt["target"], {"repository", "commit"}, f"{run_dir.name} receipt target")
    require_exact_keys(receipt["jira_delivery"], {"outcome", "mutated_jira"}, f"{run_dir.name} receipt jira_delivery")
    require_timestamp(receipt["source"]["started"], f"{run_dir.name} receipt source.started")
    require_nonempty(receipt["source"]["workspace"], f"{run_dir.name} receipt source.workspace")
    require_nonempty(receipt["source"]["host"], f"{run_dir.name} receipt source.host")
    require_nonempty(receipt["source"]["surface"], f"{run_dir.name} receipt source.surface")
    require_nonempty(receipt["target"]["repository"], f"{run_dir.name} receipt target.repository")
    require_object_id(receipt["target"]["commit"], f"{run_dir.name} receipt target.commit")
    if receipt["jira_delivery"]["outcome"] not in {"DECLINED", "NOT_PRESENTED"} or receipt["jira_delivery"]["mutated_jira"] is not False:
        fail(f"{run_dir.name} receipt Jira delivery contract is invalid")
    artifacts = receipt["artifacts"]
    if not isinstance(artifacts, dict) or not artifacts:
        fail(f"{run_dir.name} receipt artifacts must be a non-empty object")
    allowed = set(schema["capture_paths"]["required"] + schema["capture_paths"]["optional"])
    if not set(artifacts).issubset(allowed) or not set(schema["capture_paths"]["required"]).issubset(artifacts):
        fail(f"{run_dir.name} receipt artifacts violate capture allowlist")
    actual_artifacts: set[str] = set()
    artifact_root = require_real_directory(run_dir / "artifacts", f"{run_dir.name} artifacts")
    for path in artifact_root.rglob("*"):
        if path.is_symlink():
            fail(f"{run_dir.name} artifacts contain a symlink: {path}")
        if path.is_file():
            actual_artifacts.add(path.relative_to(artifact_root).as_posix())
    if actual_artifacts != set(artifacts):
        fail(f"{run_dir.name} artifact set drift")
    for relative, expected_hash in artifacts.items():
        require_hash(expected_hash, f"{run_dir.name} artifact hash for {relative}")
        if sha256(require_regular(artifact_root.joinpath(*PurePosixPath(relative).parts), f"{run_dir.name} artifact {relative}")) != expected_hash:
            fail(f"{run_dir.name} artifact hash drift: {relative}")

    manifest = read_json(run_dir / "manifest.json", f"{run_dir.name} manifest")
    require_exact_keys(manifest, {"schema_version", "ticket", "run_id", "files"}, f"{run_dir.name} manifest")
    if manifest["schema_version"] != 1 or manifest["ticket"] != receipt["ticket"] or manifest["run_id"] != receipt["run_id"]:
        fail(f"{run_dir.name} manifest identity drift")
    expected_files = {"receipt.yaml": sha256(run_dir / "receipt.yaml")}
    expected_files.update({f"artifacts/{path}": digest for path, digest in artifacts.items()})
    if manifest["files"] != expected_files:
        fail(f"{run_dir.name} manifest hash drift")

    reviews: dict[str, dict] = {}
    reviews_dir = run_dir / "reviews"
    if reviews_dir.exists() or reviews_dir.is_symlink():
        require_real_directory(reviews_dir, f"{run_dir.name} reviews")
        for path in sorted(reviews_dir.iterdir()):
            if path.suffix != ".yaml" or not path.is_file() or path.is_symlink():
                fail(f"{run_dir.name} reviews contain an unexpected entry: {path.name}")
            review = validate_review(read_yaml(path, f"review {path.name}"), schema, receipt, f"review {path.name}")
            if path.stem != review["review_id"]:
                fail(f"review filename disagrees with review_id: {path.name}")
            reviews[review["review_id"]] = review
    consensus = None
    consensus_path = run_dir / "consensus.yaml"
    if consensus_path.exists() or consensus_path.is_symlink():
        if not reviews:
            fail(f"{run_dir.name} consensus requires at least one review")
        consensus = validate_consensus(
            read_yaml(consensus_path, f"{run_dir.name} consensus"),
            schema,
            receipt,
            reviews,
            f"{run_dir.name} consensus",
        )
    return {"path": run_dir, "receipt": receipt, "reviews": reviews, "consensus": consensus}


def scan_runs(version_dir: Path, schema: dict, *, check_ticket_indexes: bool) -> list[dict]:
    tickets_root = version_dir / "tickets"
    if not tickets_root.exists():
        return []
    require_real_directory(tickets_root, "tickets directory")
    runs: list[dict] = []
    for ticket_dir in sorted(tickets_root.iterdir()):
        if not ticket_dir.is_dir() or ticket_dir.is_symlink() or not TICKET_ID.fullmatch(ticket_dir.name):
            fail(f"tickets directory has an unexpected entry: {ticket_dir.name}")
        runs_dir = require_real_directory(ticket_dir / "runs", f"{ticket_dir.name} runs")
        ticket_runs = []
        for run_dir in sorted(runs_dir.iterdir()):
            if not run_dir.is_dir() or run_dir.is_symlink() or not SAFE_ID.fullmatch(run_dir.name):
                fail(f"{ticket_dir.name} runs has an unexpected entry: {run_dir.name}")
            run = validate_run(run_dir, schema)
            runs.append(run)
            ticket_runs.append(
                {
                    "id": run_dir.name,
                    "receipt_sha256": sha256(run_dir / "receipt.yaml"),
                    "report_sha256": run["receipt"]["artifacts"]["report/dossier.html"],
                }
            )
        expected_ticket = {"schema_version": 1, "ticket": ticket_dir.name, "runs": ticket_runs}
        ticket_path = ticket_dir / "ticket.yaml"
        if check_ticket_indexes:
            if read_yaml(ticket_path, f"{ticket_dir.name} ticket index") != expected_ticket:
                fail(f"{ticket_dir.name} ticket index drift")
        else:
            write_yaml(ticket_path, expected_ticket)
    return runs


def build_manifest(version: str, runs: list[dict], synthesis: bool, closure: bool) -> dict:
    entries = []
    for run in sorted(runs, key=lambda item: (item["receipt"]["ticket"], item["receipt"]["run_id"])):
        receipt = run["receipt"]
        entries.append(
            {
                "ticket": receipt["ticket"],
                "run_id": receipt["run_id"],
                "receipt_sha256": sha256(run["path"] / "receipt.yaml"),
                "report_sha256": receipt["artifacts"]["report/dossier.html"],
                "reviews": len(run["reviews"]),
                "consensus": run["consensus"] is not None,
            }
        )
    return {
        "schema_version": 1,
        "plugin_version": version,
        "runs": entries,
        "synthesis": synthesis,
        "closure": closure,
    }


def validate_synthesis(version_dir: Path, version: str, schema: dict, runs: list[dict]) -> tuple[dict, dict, dict] | None:
    synthesis_dir = version_dir / "synthesis"
    if not synthesis_dir.exists() and not synthesis_dir.is_symlink():
        return None
    require_real_directory(synthesis_dir, "synthesis directory")
    expected_names = {"findings.yaml", "themes.yaml", "decisions.yaml"}
    actual_names = {path.name for path in synthesis_dir.iterdir()}
    if actual_names != expected_names:
        fail("synthesis file set drift")
    findings_doc = read_yaml(synthesis_dir / "findings.yaml", "synthesis findings")
    themes_doc = read_yaml(synthesis_dir / "themes.yaml", "synthesis themes")
    decisions_doc = read_yaml(synthesis_dir / "decisions.yaml", "synthesis decisions")
    validate_synthesis_documents(findings_doc, themes_doc, decisions_doc, version, schema, runs)
    return findings_doc, themes_doc, decisions_doc


def review_lookup(runs: list[dict]) -> dict[tuple[str, str, str, str], dict]:
    return {
        (run["receipt"]["ticket"], run["receipt"]["run_id"], review_id, finding["id"]): finding
        for run in runs
        for review_id, review in run["reviews"].items()
        for finding in review["findings"]
    }


def validate_synthesis_documents(
    findings_doc: dict,
    themes_doc: dict,
    decisions_doc: dict,
    version: str,
    schema: dict,
    runs: list[dict],
) -> None:
    for name, document in (("findings", findings_doc), ("themes", themes_doc), ("decisions", decisions_doc)):
        require_exact_keys(document, document_keys(schema, name), f"synthesis {name}")
        if document["schema_version"] != 1 or document["plugin_version"] != version:
            fail(f"synthesis {name} identity drift")
    known_reviews = review_lookup(runs)
    normalized: dict[str, dict] = {}
    for index, item in enumerate(require_list(findings_doc["findings"], "synthesis findings.findings"), 1):
        label = f"synthesis finding {index}"
        if not isinstance(item, dict):
            fail(f"{label} must be an object")
        require_exact_keys(item, {"id", "category", "pattern", "severity", "occurrences", "count"}, label)
        item_id = item["id"]
        if not isinstance(item_id, str) or not FINDING_ID.fullmatch(item_id) or item_id in normalized:
            fail(f"{label} id is invalid or duplicated")
        if item["category"] not in enum(schema, "finding_category") or item["severity"] not in enum(schema, "severity"):
            fail(f"{label} category or severity is invalid")
        require_nonempty(item["pattern"], f"{label} pattern")
        occurrences = require_list(item["occurrences"], f"{label} occurrences", nonempty=True)
        seen_occurrences = set()
        for occurrence in occurrences:
            if not isinstance(occurrence, dict):
                fail(f"{label} occurrence must be an object")
            require_exact_keys(occurrence, {"ticket", "run_id", "review_id", "finding_id"}, f"{label} occurrence")
            identity = (occurrence["ticket"], occurrence["run_id"], occurrence["review_id"], occurrence["finding_id"])
            if identity not in known_reviews:
                fail(f"{label} occurrence references an unknown retained finding")
            if identity in seen_occurrences:
                fail(f"{label} duplicates an occurrence")
            seen_occurrences.add(identity)
        if item["count"] != len(occurrences):
            fail(f"{label} count disagrees with occurrences")
        normalized[item_id] = item

    themes: dict[str, dict] = {}
    for index, item in enumerate(require_list(themes_doc["themes"], "synthesis themes.themes"), 1):
        label = f"synthesis theme {index}"
        if not isinstance(item, dict):
            fail(f"{label} must be an object")
        require_exact_keys(item, {"id", "title", "finding_ids", "affected_tickets", "proposed_action"}, label)
        item_id = item["id"]
        if not isinstance(item_id, str) or not FINDING_ID.fullmatch(item_id) or item_id in themes:
            fail(f"{label} id is invalid or duplicated")
        require_nonempty(item["title"], f"{label} title")
        finding_ids = require_list(item["finding_ids"], f"{label} finding_ids", nonempty=True)
        if len(set(finding_ids)) != len(finding_ids) or not set(finding_ids).issubset(normalized):
            fail(f"{label} finding_ids are duplicated or unknown")
        expected_tickets = sorted(
            {
                occurrence["ticket"]
                for finding_id_value in finding_ids
                for occurrence in normalized[finding_id_value]["occurrences"]
            }
        )
        if item["affected_tickets"] != expected_tickets:
            fail(f"{label} affected_tickets disagree with finding occurrences")
        if item["proposed_action"] not in enum(schema, "proposed_action"):
            fail(f"{label} proposed_action is invalid")
        themes[item_id] = item

    decisions: dict[str, dict] = {}
    for index, item in enumerate(require_list(decisions_doc["decisions"], "synthesis decisions.decisions"), 1):
        label = f"synthesis decision {index}"
        if not isinstance(item, dict):
            fail(f"{label} must be an object")
        require_exact_keys(item, {"theme_id", "decision", "reason"}, label)
        theme_id_value = item["theme_id"]
        if theme_id_value not in themes or theme_id_value in decisions:
            fail(f"{label} theme_id is unknown or duplicated")
        if item["decision"] not in enum(schema, "theme_decision"):
            fail(f"{label} decision is invalid")
        require_nonempty(item["reason"], f"{label} reason")
        decisions[theme_id_value] = item
    if set(decisions) != set(themes):
        fail("synthesis decisions must cover every theme exactly once")


def validate_closure(
    value: dict,
    version: str,
    schema: dict,
    runs: list[dict],
    synthesis: tuple[dict, dict, dict],
) -> dict:
    require_exact_keys(value, document_keys(schema, "closure"), "closure")
    if value["schema_version"] != 1 or value["plugin_version"] != version or value["status"] != "CLOSED":
        fail("closure identity/status drift")
    require_timestamp(value["closed_at"], "closure closed_at")
    counts = value["counts"]
    if not isinstance(counts, dict):
        fail("closure counts must be an object")
    require_exact_keys(counts, {"tickets", "runs", "reviews", "themes", "decisions"}, "closure counts")
    decision_counts = counts["decisions"]
    if not isinstance(decision_counts, dict):
        fail("closure decision counts must be an object")
    require_exact_keys(decision_counts, enum(schema, "theme_decision"), "closure decision counts")
    _, themes_doc, decisions_doc = synthesis
    expected_counts = {
        "tickets": len({run["receipt"]["ticket"] for run in runs}),
        "runs": len(runs),
        "reviews": sum(len(run["reviews"]) for run in runs),
        "themes": len(themes_doc["themes"]),
        "decisions": {
            decision: sum(1 for item in decisions_doc["decisions"] if item["decision"] == decision)
            for decision in sorted(enum(schema, "theme_decision"))
        },
    }
    if counts != expected_counts:
        fail("closure counts disagree with retained version evidence")
    improvements = require_list(value["accepted_improvements"], "closure accepted_improvements")
    proposed_themes = {item["theme_id"] for item in decisions_doc["decisions"] if item["decision"] == "PROPOSE"}
    seen_themes = set()
    for index, item in enumerate(improvements, 1):
        label = f"closure accepted improvement {index}"
        if not isinstance(item, dict):
            fail(f"{label} must be an object")
        require_exact_keys(item, {"theme_id", "proposal_path"}, label)
        if item["theme_id"] not in proposed_themes or item["theme_id"] in seen_themes:
            fail(f"{label} theme_id is not a unique PROPOSE decision")
        seen_themes.add(item["theme_id"])
        item["proposal_path"] = repo_proposal_path(item["proposal_path"], f"{label} proposal_path")
    if seen_themes != proposed_themes:
        fail("closure accepted_improvements must cover every PROPOSE decision")
    nonclaims = require_list(value["remaining_nonclaims"], "closure remaining_nonclaims", nonempty=True)
    if not all(isinstance(item, str) and item.strip() for item in nonclaims):
        fail("closure remaining_nonclaims must contain non-empty strings")
    return value


def validate_cycle(review_root_arg: Path, version_arg: str) -> dict:
    version_dir, version_doc, schema = load_cycle(review_root_arg, version_arg)
    allowed_entries = {"contract", "manifest.yaml", "tickets", "version.yaml"}
    status = version_doc["status"]
    if status in {"SYNTHESIZED", "CLOSED"}:
        allowed_entries.add("synthesis")
    if status == "CLOSED":
        allowed_entries.update({"closure.yaml", "outcomes"})
    actual_entries = {path.name for path in version_dir.iterdir()}
    if actual_entries != allowed_entries:
        fail("version directory file set drift")
    runs = scan_runs(version_dir, schema, check_ticket_indexes=True)
    synthesis = validate_synthesis(version_dir, version_arg, schema, runs)
    closure_path = version_dir / "closure.yaml"
    closure = None
    if closure_path.exists() or closure_path.is_symlink():
        if synthesis is None:
            fail("closure requires synthesis")
        closure = validate_closure(read_yaml(closure_path, "closure"), version_arg, schema, runs, synthesis)
        links = read_yaml(version_dir / "outcomes/proposal-links.yaml", "proposal links")
        outcomes_entries = {path.name for path in require_real_directory(
            version_dir / "outcomes", "outcomes directory"
        ).iterdir()}
        if outcomes_entries != {"proposal-links.yaml"}:
            fail("outcomes file set drift")
        expected_links = {
            "schema_version": 1,
            "plugin_version": version_arg,
            "proposals": closure["accepted_improvements"],
        }
        if links != expected_links:
            fail("proposal-links drift")
    elif (version_dir / "outcomes").exists() or (version_dir / "outcomes").is_symlink():
        fail("outcomes directory is only valid after closure")

    if status == "COLLECTING" and (synthesis is not None or closure is not None):
        fail("COLLECTING state cannot contain synthesis or closure")
    if status == "REVIEWING" and (synthesis is not None or closure is not None):
        fail("REVIEWING state cannot contain synthesis or closure")
    if status == "SYNTHESIZED" and (synthesis is None or closure is not None):
        fail("SYNTHESIZED state requires synthesis and no closure")
    if status == "CLOSED" and (synthesis is None or closure is None or version_doc["closed_at"] != closure["closed_at"]):
        fail("CLOSED state requires matching synthesis and closure")
    if status != "CLOSED" and version_doc["closed_at"] is not None:
        fail("only CLOSED state may set closed_at")

    expected_manifest = build_manifest(version_arg, runs, synthesis is not None, closure is not None)
    if read_yaml(version_dir / "manifest.yaml", "version manifest") != expected_manifest:
        fail("version manifest drift")
    return {
        "version_dir": version_dir,
        "version": version_doc,
        "schema": schema,
        "runs": runs,
        "synthesis": synthesis,
        "closure": closure,
        "manifest": expected_manifest,
    }


def refresh_indexes(version_dir: Path, version: str, schema: dict) -> list[dict]:
    runs = scan_runs(version_dir, schema, check_ticket_indexes=False)
    synthesis = (version_dir / "synthesis").is_dir()
    closure = (version_dir / "closure.yaml").is_file()
    write_yaml(version_dir / "manifest.yaml", build_manifest(version, runs, synthesis, closure))
    return runs


def command_init(args: argparse.Namespace) -> None:
    review_root = require_review_root(Path(args.review_root))
    version = require_semver(args.plugin_version, "plugin version")
    if args.plugin_tag != f"v{version}":
        fail("plugin tag must equal v<plugin-version>")
    commit = require_object_id(args.plugin_commit, "plugin commit")
    opened_at = require_timestamp(args.opened_at or now_utc(), "opened_at")
    storage = live_private_storage(review_root)
    schema = load_source_schema()
    versions_dir = review_root / "versions"
    require_no_symlinks(versions_dir, "versions directory")
    versions_dir.mkdir(exist_ok=True)
    destination = version_path(review_root, version)

    def build(temp: Path) -> None:
        contract = temp / "contract"
        templates = contract / "templates"
        templates.mkdir(parents=True)
        shutil.copyfile(SOURCE_SCHEMA, contract / "schema.yaml")
        template_hashes = {}
        for source in sorted(SOURCE_TEMPLATES.glob("*.yaml")):
            require_regular(source, f"source template {source.name}")
            destination_template = templates / source.name
            shutil.copyfile(source, destination_template)
            template_hashes[source.name] = sha256(destination_template)
        version_doc = {
            "schema_version": 1,
            "plugin": {"version": version, "tag": args.plugin_tag, "commit": commit},
            "storage": storage,
            "status": "COLLECTING",
            "opened_at": opened_at,
            "closed_at": None,
            "contract": {
                "schema_sha256": sha256(contract / "schema.yaml"),
                "templates": template_hashes,
            },
            "non_claims": [
                "Reviewed tickets do not prove correctness for unreviewed task classes.",
                "Teammate agreement does not replace replay and negative-control evidence.",
                "Report usability feedback does not by itself prove triage quality.",
            ],
        }
        (temp / "tickets").mkdir()
        write_yaml(temp / "version.yaml", version_doc)
        write_yaml(temp / "manifest.yaml", build_manifest(version, [], False, False))

    atomic_directory(destination, build)
    load_cycle(review_root, version)
    print(f"initialized: {destination}")
    print("state: COLLECTING")


def derive_run_id(meta: dict) -> str:
    started = require_timestamp(meta.get("started"), "workspace meta.started")
    return "run-" + re.sub(r"[^0-9]", "", started) + "z"


def parse_post_gate(path: Path) -> str:
    value = read_yaml(path, "workspace post-gate.yaml")
    require_exact_keys(value, {"post_gate"}, "workspace post-gate.yaml")
    gate = value["post_gate"]
    if not isinstance(gate, dict):
        fail("workspace post-gate post_gate must be an object")
    require_exact_keys(gate, {"date", "exchanges"}, "workspace post-gate")
    require_nonempty(gate["date"], "workspace post-gate date")
    exchanges = require_list(gate["exchanges"], "workspace post-gate exchanges", nonempty=True)
    terminal = exchanges[-1]
    if not isinstance(terminal, dict) or terminal.get("outcome") != "declined":
        fail("workspace posting gate must end in declined for version review capture")
    return "DECLINED"


def command_capture(args: argparse.Namespace) -> None:
    version_dir, version_doc, schema = load_cycle(Path(args.review_root), args.plugin_version)
    reverify_mutation_storage(require_review_root(Path(args.review_root)), version_doc)
    if version_doc["status"] != "COLLECTING":
        fail("capture is allowed only while the version cycle is COLLECTING")
    workspace = require_real_directory(Path(args.workspace), "source workspace")
    if workspace == version_dir or workspace in version_dir.parents or version_dir in workspace.parents:
        fail("source workspace and review version directory must not overlap")
    ticket = ticket_id(args.ticket)
    meta = read_yaml(workspace / "meta.yaml", "workspace meta.yaml")
    if meta.get("ticket") != ticket:
        fail("workspace meta ticket disagrees with capture ticket")
    if str(meta.get("plugin_version")) != args.plugin_version:
        fail("workspace plugin_version disagrees with version cycle")
    started = require_timestamp(meta.get("started"), "workspace meta.started")
    host = require_nonempty(meta.get("started_host", "unknown"), "workspace started_host")
    surface = require_nonempty(meta.get("started_surface", "unknown"), "workspace started_surface")
    run_id = safe_id(args.run_id or derive_run_id(meta), "run id")
    target_repository = require_nonempty(args.target_repository, "target repository")
    target_commit = require_object_id(args.target_commit, "target commit")
    captured_at = require_timestamp(args.captured_at or now_utc(), "captured_at")

    for result_name in ("triage/jira/post-result.json", "triage/jira/attach-result.json"):
        result_path = workspace.joinpath(*PurePosixPath(result_name).parts)
        if result_path.exists() or result_path.is_symlink():
            fail(f"workspace contains Jira mutation result: {result_name}")
    gate_path = workspace / "triage/jira/post-gate.yaml"
    jira_outcome = parse_post_gate(gate_path) if gate_path.exists() or gate_path.is_symlink() else "NOT_PRESENTED"

    capture_paths = schema["capture_paths"]
    artifact_sources = {}
    for relative in capture_paths["required"]:
        artifact_sources[relative] = require_regular(
            workspace.joinpath(*PurePosixPath(relative).parts), f"workspace {relative}"
        )
    for relative in capture_paths["optional"]:
        candidate = workspace.joinpath(*PurePosixPath(relative).parts)
        if candidate.exists() or candidate.is_symlink():
            artifact_sources[relative] = require_regular(candidate, f"workspace {relative}")

    ticket_dir = version_dir / "tickets" / ticket
    run_destination = ticket_dir / "runs" / run_id
    if run_destination.exists() or run_destination.is_symlink():
        fail(f"captured run already exists: {ticket}/{run_id}")

    def build_run(temp: Path) -> None:
        artifact_root = temp / "artifacts"
        artifact_hashes = {}
        for relative, source in artifact_sources.items():
            destination = artifact_root.joinpath(*PurePosixPath(relative).parts)
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, destination)
            artifact_hashes[relative] = sha256(destination)
        receipt = {
            "schema_version": 1,
            "ticket": ticket,
            "run_id": run_id,
            "plugin": version_doc["plugin"],
            "source": {
                "workspace": str(workspace),
                "started": started,
                "host": host,
                "surface": surface,
            },
            "target": {"repository": target_repository, "commit": target_commit},
            "jira_delivery": {"outcome": jira_outcome, "mutated_jira": False},
            "captured_at": captured_at,
            "artifacts": artifact_hashes,
        }
        write_yaml(temp / "receipt.yaml", receipt)
        files = {"receipt.yaml": sha256(temp / "receipt.yaml")}
        files.update({f"artifacts/{relative}": digest for relative, digest in artifact_hashes.items()})
        write_json(
            temp / "manifest.json",
            {"schema_version": 1, "ticket": ticket, "run_id": run_id, "files": files},
        )

    if ticket_dir.exists():
        require_real_directory(ticket_dir, f"ticket directory {ticket}")
        runs_dir = require_real_directory(ticket_dir / "runs", f"ticket runs {ticket}")
        atomic_directory(runs_dir / run_id, build_run)
    else:
        def build_ticket(temp_ticket: Path) -> None:
            runs_dir = temp_ticket / "runs"
            runs_dir.mkdir()
            atomic_directory(runs_dir / run_id, build_run)

        atomic_directory(ticket_dir, build_ticket)
    refresh_indexes(version_dir, args.plugin_version, schema)
    validate_cycle(Path(args.review_root), args.plugin_version)
    print(f"captured: {ticket}/{run_id}")
    print(f"report_sha256: {sha256(run_destination / 'artifacts/report/dossier.html')}")


def update_status(version_dir: Path, version_doc: dict, schema: dict, target: str, *, closed_at: str | None = None) -> None:
    current = version_doc["status"]
    allowed = schema["lifecycle"]["transitions"].get(current, [])
    if target not in allowed:
        fail(f"invalid lifecycle transition: {current} -> {target}")
    version_doc["status"] = target
    version_doc["closed_at"] = closed_at
    write_yaml(version_dir / "version.yaml", version_doc)


def command_begin_review(args: argparse.Namespace) -> None:
    state = validate_cycle(Path(args.review_root), args.plugin_version)
    reverify_mutation_storage(require_review_root(Path(args.review_root)), state["version"])
    if state["version"]["status"] != "COLLECTING":
        fail("begin-review requires COLLECTING state")
    if not state["runs"]:
        fail("begin-review requires at least one captured run")
    update_status(state["version_dir"], state["version"], state["schema"], "REVIEWING")
    validate_cycle(Path(args.review_root), args.plugin_version)
    print("state: REVIEWING")


def find_run(state: dict, ticket: str, run_id: str) -> dict:
    for run in state["runs"]:
        if run["receipt"]["ticket"] == ticket and run["receipt"]["run_id"] == run_id:
            return run
    fail(f"unknown captured run: {ticket}/{run_id}")


def command_add_review(args: argparse.Namespace) -> None:
    state = validate_cycle(Path(args.review_root), args.plugin_version)
    reverify_mutation_storage(require_review_root(Path(args.review_root)), state["version"])
    if state["version"]["status"] != "REVIEWING":
        fail("add-review requires REVIEWING state")
    source = read_yaml(Path(args.source), "authored review")
    ticket = ticket_id(source.get("ticket"), "authored review ticket")
    run_id = safe_id(source.get("run_id"), "authored review run_id")
    run = find_run(state, ticket, run_id)
    review = validate_review(source, state["schema"], run["receipt"], "authored review")
    destination = run["path"] / "reviews" / f"{review['review_id']}.yaml"
    if destination.exists() or destination.is_symlink():
        fail(f"review already exists: {review['review_id']}")
    write_yaml(destination, review)
    refresh_indexes(state["version_dir"], args.plugin_version, state["schema"])
    validate_cycle(Path(args.review_root), args.plugin_version)
    print(f"review added: {ticket}/{run_id}/{review['review_id']}")


def command_add_consensus(args: argparse.Namespace) -> None:
    state = validate_cycle(Path(args.review_root), args.plugin_version)
    reverify_mutation_storage(require_review_root(Path(args.review_root)), state["version"])
    if state["version"]["status"] != "REVIEWING":
        fail("add-consensus requires REVIEWING state")
    source = read_yaml(Path(args.source), "authored consensus")
    ticket = ticket_id(source.get("ticket"), "authored consensus ticket")
    run_id = safe_id(source.get("run_id"), "authored consensus run_id")
    run = find_run(state, ticket, run_id)
    if not run["reviews"]:
        fail("consensus requires at least one retained review")
    consensus = validate_consensus(
        source, state["schema"], run["receipt"], run["reviews"], "authored consensus"
    )
    destination = run["path"] / "consensus.yaml"
    if destination.exists() or destination.is_symlink():
        fail(f"consensus already exists: {ticket}/{run_id}")
    write_yaml(destination, consensus)
    refresh_indexes(state["version_dir"], args.plugin_version, state["schema"])
    validate_cycle(Path(args.review_root), args.plugin_version)
    print(f"consensus added: {ticket}/{run_id}")


def command_synthesize(args: argparse.Namespace) -> None:
    state = validate_cycle(Path(args.review_root), args.plugin_version)
    reverify_mutation_storage(require_review_root(Path(args.review_root)), state["version"])
    if state["version"]["status"] != "REVIEWING":
        fail("synthesize requires REVIEWING state")
    if not state["runs"] or any(run["consensus"] is None for run in state["runs"]):
        fail("synthesize requires consensus for every captured run")
    findings = read_yaml(Path(args.findings), "authored findings")
    themes = read_yaml(Path(args.themes), "authored themes")
    decisions = read_yaml(Path(args.decisions), "authored decisions")
    validate_synthesis_documents(
        findings, themes, decisions, args.plugin_version, state["schema"], state["runs"]
    )
    destination = state["version_dir"] / "synthesis"

    def build(temp: Path) -> None:
        write_yaml(temp / "findings.yaml", findings)
        write_yaml(temp / "themes.yaml", themes)
        write_yaml(temp / "decisions.yaml", decisions)

    original_version = yaml_bytes(state["version"])
    original_manifest = (state["version_dir"] / "manifest.yaml").read_bytes()
    atomic_directory(destination, build)
    try:
        update_status(state["version_dir"], state["version"], state["schema"], "SYNTHESIZED")
        refresh_indexes(state["version_dir"], args.plugin_version, state["schema"])
        validate_cycle(Path(args.review_root), args.plugin_version)
    except Exception:
        shutil.rmtree(destination, ignore_errors=True)
        write_atomic(state["version_dir"] / "version.yaml", original_version)
        write_atomic(state["version_dir"] / "manifest.yaml", original_manifest)
        raise
    print("state: SYNTHESIZED")


def command_close(args: argparse.Namespace) -> None:
    state = validate_cycle(Path(args.review_root), args.plugin_version)
    reverify_mutation_storage(require_review_root(Path(args.review_root)), state["version"])
    if state["version"]["status"] != "SYNTHESIZED" or state["synthesis"] is None:
        fail("close requires SYNTHESIZED state")
    closure = validate_closure(
        read_yaml(Path(args.source), "authored closure"),
        args.plugin_version,
        state["schema"],
        state["runs"],
        state["synthesis"],
    )
    outcomes = state["version_dir"] / "outcomes"

    def build_outcomes(temp: Path) -> None:
        write_yaml(
            temp / "proposal-links.yaml",
            {
                "schema_version": 1,
                "plugin_version": args.plugin_version,
                "proposals": closure["accepted_improvements"],
            },
        )

    original_version = yaml_bytes(state["version"])
    original_manifest = (state["version_dir"] / "manifest.yaml").read_bytes()
    closure_path = state["version_dir"] / "closure.yaml"
    atomic_directory(outcomes, build_outcomes)
    try:
        write_yaml(closure_path, closure)
        update_status(
            state["version_dir"],
            state["version"],
            state["schema"],
            "CLOSED",
            closed_at=closure["closed_at"],
        )
        refresh_indexes(state["version_dir"], args.plugin_version, state["schema"])
        validate_cycle(Path(args.review_root), args.plugin_version)
    except Exception:
        shutil.rmtree(outcomes, ignore_errors=True)
        if closure_path.exists() and not closure_path.is_symlink():
            closure_path.unlink()
        write_atomic(state["version_dir"] / "version.yaml", original_version)
        write_atomic(state["version_dir"] / "manifest.yaml", original_manifest)
        raise
    print("state: CLOSED")


def state_lines(state: dict, review_root: Path, version: str) -> list[str]:
    runs = state["runs"]
    review_count = sum(len(run["reviews"]) for run in runs)
    consensus_count = sum(run["consensus"] is not None for run in runs)
    status = state["version"]["status"]
    lines = [
        f"state: {status}",
        f"version_dir: {state['version_dir']}",
        f"runs: {len(runs)}",
        f"reviews: {review_count}",
        f"consensus: {consensus_count}/{len(runs)}",
        f"synthesis: {'present' if state['synthesis'] else 'absent'}",
        f"closure: {'present' if state['closure'] else 'absent'}",
    ]
    base = f"python3 tools/version-review.py"
    root_arg = str(require_review_root(review_root))
    if status == "COLLECTING":
        lines.append(
            f"allowed_action: capture another run, or {base} begin-review {root_arg} --plugin-version {version}"
        )
    elif status == "REVIEWING":
        missing_reviews = [run for run in runs if not run["reviews"]]
        missing_consensus = [run for run in runs if run["reviews"] and run["consensus"] is None]
        if missing_reviews:
            receipt = missing_reviews[0]["receipt"]
            lines.append(f"allowed_action: add-review for {receipt['ticket']}/{receipt['run_id']}")
        elif missing_consensus:
            receipt = missing_consensus[0]["receipt"]
            lines.append(f"allowed_action: add-consensus for {receipt['ticket']}/{receipt['run_id']}")
        else:
            lines.append("allowed_action: synthesize")
    elif status == "SYNTHESIZED":
        lines.append("allowed_action: close with proposal links for every PROPOSE decision")
    else:
        lines.append("allowed_action: none")
    return lines


def command_state(args: argparse.Namespace) -> None:
    state = validate_cycle(Path(args.review_root), args.plugin_version)
    print("\n".join(state_lines(state, Path(args.review_root), args.plugin_version)))


def command_validate(args: argparse.Namespace) -> None:
    state = validate_cycle(Path(args.review_root), args.plugin_version)
    print(
        f"version review: clean — v{args.plugin_version} {state['version']['status']}, "
        f"{len(state['runs'])} run(s), "
        f"{sum(len(run['reviews']) for run in state['runs'])} review(s)"
    )


STRUCTURE = """<review-root>/
  versions/
    vX.Y.Z/
      version.yaml                  # release/lifecycle + verified private-Git storage
      manifest.yaml                 # rail-generated run/review/consensus index
      contract/
        schema.yaml                 # pinned schema snapshot
        templates/*.yaml            # pinned semantic input examples
      tickets/<TICKET>/
        ticket.yaml                 # rail-generated immutable-run index
        runs/<run-id>/
          receipt.yaml              # version/ticket/repository/report identity
          manifest.json             # captured-file hashes
          artifacts/                # allowlisted minimal current-run evidence
          reviews/<review-id>.yaml  # immutable teammate-authored review
          consensus.yaml            # immutable finding resolution
      synthesis/
        findings.yaml               # normalized cross-ticket findings
        themes.yaml                 # finding groups + proposed action
        decisions.yaml              # PROPOSE | MONITOR | REJECT per theme
      outcomes/proposal-links.yaml  # derived links for PROPOSE decisions
      closure.yaml                  # derived-count-checked terminal record
"""


def command_structure(_: argparse.Namespace) -> None:
    print(STRUCTURE, end="")


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(description=__doc__)
    commands = root.add_subparsers(dest="command", required=True)

    structure = commands.add_parser("structure", help="print the external version tree")
    structure.set_defaults(func=command_structure)

    def version_command(name: str, help_text: str) -> argparse.ArgumentParser:
        command = commands.add_parser(name, help=help_text)
        command.add_argument("review_root")
        command.add_argument("--plugin-version", required=True)
        return command

    init = version_command("init", "initialize one published-version review cycle")
    init.add_argument("--plugin-tag", required=True)
    init.add_argument("--plugin-commit", required=True)
    init.add_argument("--opened-at")
    init.set_defaults(func=command_init)

    capture = version_command("capture", "capture one immutable minimal dossier run")
    capture.add_argument("--ticket", required=True)
    capture.add_argument("--workspace", required=True)
    capture.add_argument("--target-repository", required=True)
    capture.add_argument("--target-commit", required=True)
    capture.add_argument("--run-id")
    capture.add_argument("--captured-at")
    capture.set_defaults(func=command_capture)

    begin = version_command("begin-review", "close collection and begin teammate review")
    begin.set_defaults(func=command_begin_review)

    review = version_command("add-review", "validate and import one teammate review")
    review.add_argument("--from", dest="source", required=True)
    review.set_defaults(func=command_add_review)

    consensus = version_command("add-consensus", "validate and import one run consensus")
    consensus.add_argument("--from", dest="source", required=True)
    consensus.set_defaults(func=command_add_consensus)

    synthesis = version_command("synthesize", "validate and atomically import cross-ticket synthesis")
    synthesis.add_argument("--findings", required=True)
    synthesis.add_argument("--themes", required=True)
    synthesis.add_argument("--decisions", required=True)
    synthesis.set_defaults(func=command_synthesize)

    close = version_command("close", "validate proposal links/counts and close the version cycle")
    close.add_argument("--from", dest="source", required=True)
    close.set_defaults(func=command_close)

    state = version_command("state", "derive one validated lifecycle state")
    state.set_defaults(func=command_state)

    validate = version_command("validate", "validate the complete retained version cycle")
    validate.set_defaults(func=command_validate)
    return root


def main() -> int:
    args = parser().parse_args()
    try:
        args.func(args)
        return 0
    except ReviewError as exc:
        print(f"version review: ERROR — {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
