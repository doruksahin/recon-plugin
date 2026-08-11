#!/bin/bash
# activate-codex-plugin.sh — sync and reinstall Recon from its configured Codex
# marketplace, then attest what Codex actually installed. Never edits Codex
# config directly. If the marketplace is not configured, prints setup commands.
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "not a git repo" >&2; exit 2; }
ROOT="$(cd "$ROOT" && pwd -P)"
MARKETPLACE_JSON="$ROOT/.agents/plugins/marketplace.json"
PLUGIN_JSON="$ROOT/recon/.codex-plugin/plugin.json"
[ -f "$MARKETPLACE_JSON" ] || { echo "missing $MARKETPLACE_JSON" >&2; exit 2; }
[ -f "$PLUGIN_JSON" ] || { echo "missing $PLUGIN_JSON" >&2; exit 2; }
command -v codex >/dev/null 2>&1 || { echo "codex: SKIPPED — Codex CLI is not installed"; exit 0; }

readarray_values="$(python3 - "$MARKETPLACE_JSON" "$PLUGIN_JSON" <<'PY'
import json, sys
marketplace = json.load(open(sys.argv[1]))
plugin = json.load(open(sys.argv[2]))
print(marketplace["name"])
print(plugin["name"])
print(plugin["version"])
PY
)" || { echo "invalid Codex marketplace/plugin JSON" >&2; exit 2; }
MARKETPLACE="$(printf '%s\n' "$readarray_values" | sed -n '1p')"
PLUGIN="$(printf '%s\n' "$readarray_values" | sed -n '2p')"
VERSION="$(printf '%s\n' "$readarray_values" | sed -n '3p')"

refuse() {
  echo "codex: REFUSED — $1" >&2
  exit 1
}

SOURCE_HEAD="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null)" || refuse \
  "source release checkout has no Git HEAD: $ROOT"
[ -z "$(git -C "$ROOT" status --porcelain --untracked-files=all)" ] || refuse \
  "source release checkout is dirty: $ROOT"

# `codex plugin marketplace list` fails wholesale when ANY configured
# marketplace cannot load — e.g. one whose source path no longer exists. It then
# writes nothing to stdout, so piping it straight into json.load buried the real
# cause under a JSONDecodeError traceback. Capture and report the CLI's own words.
marketplace_list=""
if ! marketplace_list="$(codex plugin marketplace list --json 2>&1)"; then
  refuse "codex could not list marketplaces — fix the configured entry it names, then re-run:
$marketplace_list"
fi

configured_info="$(printf '%s' "$marketplace_list" | python3 -c '
import json, sys
name = sys.argv[1]
rows = json.load(sys.stdin).get("marketplaces", [])
matches = [row for row in rows if row.get("name") == name]
if not matches:
    print("no")
elif len(matches) != 1:
    raise SystemExit(f"duplicate configured marketplace: {name}")
else:
    row = matches[0]
    source = row.get("marketplaceSource") or {}
    print("yes")
    print(row.get("root", ""))
    print(source.get("sourceType", "unknown"))
' "$MARKETPLACE")"
configured="$(printf '%s\n' "$configured_info" | sed -n '1p')"

if [ "$configured" != yes ]; then
  echo "codex: SKIPPED — marketplace '$MARKETPLACE' is not configured"
  echo "codex: setup — codex plugin marketplace add $ROOT"
  echo "codex: install — codex plugin add $PLUGIN@$MARKETPLACE"
  exit 0
fi

CONFIGURED_ROOT="$(printf '%s\n' "$configured_info" | sed -n '2p')"
SOURCE_TYPE="$(printf '%s\n' "$configured_info" | sed -n '3p')"
[ -n "$CONFIGURED_ROOT" ] || refuse "marketplace '$MARKETPLACE' has no configured root"
[ -d "$CONFIGURED_ROOT" ] || refuse "configured marketplace root is missing: $CONFIGURED_ROOT"
CONFIGURED_ROOT="$(cd "$CONFIGURED_ROOT" && pwd -P)"

normalize_origin() {
  python3 - "$1" <<'PY'
import re
import sys
from pathlib import Path
from urllib.parse import urlparse

value = sys.argv[1].strip().rstrip("/")
if value.startswith("git@") and ":" in value:
    host, path = value[4:].split(":", 1)
    normalized = f"{host.lower()}/{path}"
elif "://" in value:
    parsed = urlparse(value)
    if parsed.scheme == "file":
        normalized = str(Path(parsed.path).resolve())
    else:
        normalized = f"{(parsed.hostname or '').lower()}/{parsed.path.lstrip('/')}"
else:
    normalized = str(Path(value).resolve())
print(re.sub(r"\.git$", "", normalized).rstrip("/"))
PY
}

attest_plugin_tree() {
  python3 - "$1" "$2" "$3" <<'PY'
import hashlib
import os
import stat
import subprocess
import sys
from pathlib import Path, PurePosixPath


checkout = Path(sys.argv[1]).resolve()
raw_relative = sys.argv[2]
label = sys.argv[3]


def reject(message):
    print(f"{label} plugin tree: {message}", file=sys.stderr)
    raise SystemExit(1)


relative = PurePosixPath(raw_relative)
parts = tuple(part for part in relative.parts if part != ".")
if relative.is_absolute() or not parts or any(part in {"", ".."} for part in parts):
    reject(f"unsafe plugin relative path {raw_relative!r}")
canonical_relative = "/".join(parts)
plugin_root = checkout.joinpath(*parts)
try:
    root_stat = os.lstat(plugin_root)
except OSError as exc:
    reject(f"cannot inspect {canonical_relative}: {exc}")
if not stat.S_ISDIR(root_stat.st_mode) or stat.S_ISLNK(root_stat.st_mode):
    reject(f"plugin root must be a real directory: {canonical_relative}")


def git(*args):
    result = subprocess.run(
        ["git", "-C", str(checkout), *args],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if result.returncode:
        detail = result.stderr.decode("utf-8", "replace").strip()
        reject(f"git {' '.join(args)} failed: {detail or result.returncode}")
    return result.stdout


stage_records = {}
stage_output = git("ls-files", "-z", "--stage", "--", canonical_relative)
for record in stage_output.split(b"\0"):
    if not record:
        continue
    try:
        metadata, path = record.split(b"\t", 1)
        mode, object_id, stage_number = metadata.split()
    except ValueError:
        reject(f"unparseable index entry {record!r}")
    if stage_number != b"0":
        reject(f"unmerged plugin index entry {path!r}")
    if mode not in {b"100644", b"100755", b"120000"}:
        reject(f"special or unsupported tracked entry {path!r} with mode {mode.decode()}")
    stage_records[path] = (mode, object_id)
if not stage_records:
    reject(f"no tracked files under {canonical_relative}")

flagged_paths = set()
flag_output = git("ls-files", "-z", "-v", "--", canonical_relative)
for record in flag_output.split(b"\0"):
    if not record:
        continue
    if len(record) < 3 or record[1:2] != b" ":
        reject(f"unparseable index-flag entry {record!r}")
    tag, path = record[:1], record[2:]
    flagged_paths.add(path)
    if tag != b"H":
        reject(
            f"sparse/assume-unchanged or nonstandard index entry {path!r} "
            f"(git ls-files tag {tag.decode('ascii', 'replace')!r})"
        )
if flagged_paths != set(stage_records):
    reject("index stage and index-flag inventories disagree")

prefix = os.fsencode(canonical_relative) + b"/"
tracked = {}
for repo_path, metadata in stage_records.items():
    if not repo_path.startswith(prefix) or len(repo_path) == len(prefix):
        reject(f"tracked path escapes plugin root: {repo_path!r}")
    tracked[repo_path[len(prefix) :]] = metadata

materialized = {}


def walk(directory, relative_prefix=b""):
    try:
        entries = list(os.scandir(os.fsencode(directory)))
    except OSError as exc:
        reject(f"cannot scan materialized tree: {exc}")
    for entry in sorted(entries, key=lambda item: item.name):
        relative_path = relative_prefix + entry.name
        try:
            entry_stat = entry.stat(follow_symlinks=False)
        except OSError as exc:
            reject(f"cannot stat materialized entry {relative_path!r}: {exc}")
        mode = entry_stat.st_mode
        if stat.S_ISDIR(mode):
            walk(entry.path, relative_path + b"/")
        elif stat.S_ISREG(mode):
            try:
                with open(entry.path, "rb") as handle:
                    payload = handle.read()
            except OSError as exc:
                reject(f"cannot read materialized file {relative_path!r}: {exc}")
            executable = b"1" if mode & 0o111 else b"0"
            materialized[relative_path] = (b"file", executable, payload)
        elif stat.S_ISLNK(mode):
            try:
                target = os.readlink(entry.path)
            except OSError as exc:
                reject(f"cannot read symlink target {relative_path!r}: {exc}")
            if isinstance(target, str):
                target = os.fsencode(target)
            materialized[relative_path] = (b"symlink", b"0", target)
        else:
            reject(f"special filesystem entry is forbidden: {relative_path!r}")


walk(plugin_root)
tracked_paths = set(tracked)
materialized_paths = set(materialized)
missing = sorted(tracked_paths - materialized_paths)
extra = sorted(materialized_paths - tracked_paths)
if missing:
    reject(f"tracked plugin content is not materialized: {missing[0]!r}")
if extra:
    reject(f"materialized plugin content is not tracked: {extra[0]!r}")


def blob_object_id(payload, expected):
    if len(expected) == 40:
        digest = hashlib.sha1()
    elif len(expected) == 64:
        digest = hashlib.sha256()
    else:
        reject(f"unsupported Git object id {expected!r}")
    digest.update(f"blob {len(payload)}\0".encode("ascii"))
    digest.update(payload)
    return digest.hexdigest().encode("ascii")


tree_digest = hashlib.sha256()
tree_digest.update(b"recon-materialized-plugin-tree-v1\0")
tree_digest.update(canonical_relative.encode("utf-8") + b"\0")
for relative_path in sorted(materialized):
    kind, executable, payload = materialized[relative_path]
    index_mode, object_id = tracked[relative_path]
    expected_mode = b"120000" if kind == b"symlink" else (
        b"100755" if executable == b"1" else b"100644"
    )
    if index_mode != expected_mode:
        reject(
            f"materialized type/executable bit disagrees with Git for "
            f"{relative_path!r}: {expected_mode.decode()} vs {index_mode.decode()}"
        )
    if blob_object_id(payload, object_id) != object_id:
        reject(f"materialized bytes disagree with Git for {relative_path!r}")
    for field in (relative_path, kind, executable, payload):
        tree_digest.update(len(field).to_bytes(8, "big"))
        tree_digest.update(field)

print(f"sha256:{tree_digest.hexdigest()} entries:{len(materialized)}")
PY
}

read_configured_plugin() {
  python3 - "$CONFIGURED_ROOT" "$MARKETPLACE" "$PLUGIN" <<'PY'
import json
import sys
from pathlib import Path, PurePosixPath

root = Path(sys.argv[1])
expected_marketplace, expected_plugin = sys.argv[2:4]
manifest = json.loads((root / ".agents/plugins/marketplace.json").read_text())
if manifest.get("name") != expected_marketplace:
    raise SystemExit(
        f"configured manifest name is {manifest.get('name')!r}, expected {expected_marketplace!r}"
    )
matches = [row for row in manifest.get("plugins", []) if row.get("name") == expected_plugin]
if len(matches) != 1:
    raise SystemExit(f"configured marketplace must contain exactly one {expected_plugin!r} plugin")
source = matches[0].get("source") or {}
raw_path = source.get("path", "")
relative = PurePosixPath(raw_path)
parts = tuple(part for part in relative.parts if part != ".")
if source.get("source") != "local" or relative.is_absolute() or not parts or any(
    part in {"", ".."} for part in parts
):
    raise SystemExit("configured Recon plugin must use a safe local relative path")
plugin_relative = "/".join(parts)
plugin_root = root.joinpath(*parts)
plugin = json.loads((plugin_root / ".codex-plugin/plugin.json").read_text())
if plugin.get("name") != expected_plugin:
    raise SystemExit(f"configured plugin name is {plugin.get('name')!r}")
print(plugin.get("version", ""))
print(plugin_root.absolute())
print(plugin_relative)
PY
}

if [ "$SOURCE_TYPE" = local ] && [ "$CONFIGURED_ROOT" != "$ROOT" ]; then
  CONFIGURED_TOP="$(git -C "$CONFIGURED_ROOT" rev-parse --show-toplevel 2>/dev/null)" || refuse \
    "separate local marketplace is not a git checkout: $CONFIGURED_ROOT; reconfigure with: codex plugin marketplace remove $MARKETPLACE && codex plugin marketplace add $ROOT"
  CONFIGURED_TOP="$(cd "$CONFIGURED_TOP" && pwd -P)"
  [ "$CONFIGURED_TOP" = "$CONFIGURED_ROOT" ] || refuse \
    "configured marketplace root is not its Git checkout root: $CONFIGURED_ROOT"
  [ -z "$(git -C "$CONFIGURED_ROOT" status --porcelain --untracked-files=all)" ] || refuse \
    "configured marketplace clone is dirty: $CONFIGURED_ROOT"
  SOURCE_ORIGIN="$(git -C "$ROOT" remote get-url origin 2>/dev/null)" || refuse \
    "source repo has no origin remote: $ROOT"
  CONFIGURED_ORIGIN="$(git -C "$CONFIGURED_ROOT" remote get-url origin 2>/dev/null)" || refuse \
    "configured marketplace clone has no origin remote: $CONFIGURED_ROOT"
  [ "$(normalize_origin "$SOURCE_ORIGIN")" = "$(normalize_origin "$CONFIGURED_ORIGIN")" ] || refuse \
    "configured marketplace clone has a different origin: $CONFIGURED_ROOT"
  if ! SYNC_OUTPUT="$(git -C "$CONFIGURED_ROOT" pull --ff-only 2>&1)"; then
    refuse "marketplace clone did not fast-forward: ${SYNC_OUTPUT##*$'\n'}"
  fi
  echo "codex: marketplace clone synced — $CONFIGURED_ROOT"
elif [ "$SOURCE_TYPE" != local ]; then
  codex plugin marketplace upgrade "$MARKETPLACE" >/dev/null || refuse \
    "marketplace '$MARKETPLACE' upgrade failed"
  echo "codex: marketplace '$MARKETPLACE' upgraded"
fi

CONFIGURED_TOP="$(git -C "$CONFIGURED_ROOT" rev-parse --show-toplevel 2>/dev/null)" || refuse \
  "configured marketplace is not a git checkout after synchronization: $CONFIGURED_ROOT"
CONFIGURED_TOP="$(cd "$CONFIGURED_TOP" && pwd -P)"
[ "$CONFIGURED_TOP" = "$CONFIGURED_ROOT" ] || refuse \
  "configured marketplace root is not its Git checkout root: $CONFIGURED_ROOT"
[ -z "$(git -C "$CONFIGURED_ROOT" status --porcelain --untracked-files=all)" ] || refuse \
  "configured marketplace clone is dirty after synchronization: $CONFIGURED_ROOT"

if [ "$CONFIGURED_ROOT" != "$ROOT" ]; then
  SOURCE_ORIGIN="$(git -C "$ROOT" remote get-url origin 2>/dev/null)" || refuse \
    "source repo has no origin remote: $ROOT"
  CONFIGURED_ORIGIN="$(git -C "$CONFIGURED_ROOT" remote get-url origin 2>/dev/null)" || refuse \
    "configured marketplace clone has no origin remote: $CONFIGURED_ROOT"
  [ "$(normalize_origin "$SOURCE_ORIGIN")" = "$(normalize_origin "$CONFIGURED_ORIGIN")" ] || refuse \
    "configured marketplace clone has a different origin: $CONFIGURED_ROOT"
fi

CONFIGURED_HEAD="$(git -C "$CONFIGURED_ROOT" rev-parse HEAD 2>/dev/null)" || refuse \
  "configured marketplace has no Git HEAD after synchronization: $CONFIGURED_ROOT"
[ "$CONFIGURED_HEAD" = "$SOURCE_HEAD" ] || refuse \
  "configured marketplace HEAD $CONFIGURED_HEAD does not match source released HEAD $SOURCE_HEAD"

configured_plugin="$(read_configured_plugin)" || refuse \
  "configured marketplace manifest cannot be attested"
CONFIGURED_VERSION="$(printf '%s\n' "$configured_plugin" | sed -n '1p')"
CONFIGURED_PLUGIN_ROOT="$(printf '%s\n' "$configured_plugin" | sed -n '2p')"
CONFIGURED_PLUGIN_REL="$(printf '%s\n' "$configured_plugin" | sed -n '3p')"
[ "$CONFIGURED_PLUGIN_REL" = recon ] || refuse \
  "configured plugin relative path is $CONFIGURED_PLUGIN_REL, expected recon"
[ "$CONFIGURED_VERSION" = "$VERSION" ] || refuse \
  "configured marketplace has v$CONFIGURED_VERSION, source release is v$VERSION"

if ! SOURCE_TREE="$(attest_plugin_tree "$ROOT" recon source)"; then
  refuse "source materialized plugin tree cannot be attested"
fi
if ! CONFIGURED_TREE="$(attest_plugin_tree "$CONFIGURED_ROOT" "$CONFIGURED_PLUGIN_REL" configured)"; then
  refuse "configured materialized plugin tree cannot be attested"
fi
[ "$CONFIGURED_TREE" = "$SOURCE_TREE" ] || refuse \
  "configured materialized plugin tree does not match source: $CONFIGURED_TREE vs $SOURCE_TREE"

attest_release_state() {
  local boundary="$1" tree_label="$2"
  local source_head_now configured_head_now source_version_now
  local configured_plugin_now configured_version_now configured_plugin_root_now
  local configured_plugin_rel_now source_tree_now configured_tree_now

  [ -z "$(git -C "$ROOT" status --porcelain --untracked-files=all)" ] || refuse \
    "source release checkout is dirty after $boundary: $ROOT"
  [ -z "$(git -C "$CONFIGURED_ROOT" status --porcelain --untracked-files=all)" ] || refuse \
    "configured marketplace clone is dirty after $boundary: $CONFIGURED_ROOT"
  source_head_now="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null)" || refuse \
    "source release checkout lost its Git HEAD after $boundary: $ROOT"
  configured_head_now="$(git -C "$CONFIGURED_ROOT" rev-parse HEAD 2>/dev/null)" || refuse \
    "configured marketplace lost its Git HEAD after $boundary: $CONFIGURED_ROOT"
  [ "$source_head_now" = "$SOURCE_HEAD" ] || refuse \
    "source release HEAD changed after $boundary: $source_head_now vs $SOURCE_HEAD"
  [ "$configured_head_now" = "$SOURCE_HEAD" ] || refuse \
    "configured marketplace HEAD changed after $boundary: $configured_head_now vs $SOURCE_HEAD"

  source_version_now="$(python3 - "$PLUGIN_JSON" <<'PY'
import json, sys
print(json.load(open(sys.argv[1])).get("version", ""))
PY
)" || refuse "source plugin manifest cannot be re-attested after $boundary"
  configured_plugin_now="$(read_configured_plugin)" || refuse \
    "configured marketplace manifest cannot be re-attested after $boundary"
  configured_version_now="$(printf '%s\n' "$configured_plugin_now" | sed -n '1p')"
  configured_plugin_root_now="$(printf '%s\n' "$configured_plugin_now" | sed -n '2p')"
  configured_plugin_rel_now="$(printf '%s\n' "$configured_plugin_now" | sed -n '3p')"
  [ "$source_version_now" = "$VERSION" ] || refuse \
    "source plugin version changed after $boundary: $source_version_now vs $VERSION"
  [ "$configured_version_now" = "$VERSION" ] || refuse \
    "configured plugin version changed after $boundary: $configured_version_now vs $VERSION"
  [ "$configured_plugin_root_now" = "$CONFIGURED_PLUGIN_ROOT" ] || refuse \
    "configured plugin path changed after $boundary: $configured_plugin_root_now"
  [ "$configured_plugin_rel_now" = "$CONFIGURED_PLUGIN_REL" ] || refuse \
    "configured plugin relative path changed after $boundary: $configured_plugin_rel_now"

  if ! source_tree_now="$(attest_plugin_tree "$ROOT" recon "source-$tree_label")"; then
    refuse "source materialized plugin tree cannot be re-attested after $boundary"
  fi
  if ! configured_tree_now="$(attest_plugin_tree "$CONFIGURED_ROOT" "$CONFIGURED_PLUGIN_REL" "configured-$tree_label")"; then
    refuse "configured materialized plugin tree cannot be re-attested after $boundary"
  fi
  [ "$source_tree_now" = "$SOURCE_TREE" ] || refuse \
    "source materialized plugin tree changed after $boundary"
  [ "$configured_tree_now" = "$CONFIGURED_TREE" ] || refuse \
    "configured materialized plugin tree changed after $boundary"
  [ "$configured_tree_now" = "$source_tree_now" ] || refuse \
    "configured materialized plugin tree no longer matches source after $boundary"
}

codex plugin add "$PLUGIN@$MARKETPLACE" --json >/dev/null || refuse "Codex plugin install failed"
attest_release_state "installation" "install"

if ! INSTALLED_PATH="$(codex plugin list --json | python3 -c '
import json, sys
plugin_id, version = sys.argv[1:3]
expected_path = __import__("pathlib").Path(sys.argv[3]).resolve()
rows = json.load(sys.stdin).get("installed", [])
matches = [row for row in rows if row.get("pluginId") == plugin_id]
if len(matches) != 1:
    raise SystemExit(f"expected one installed {plugin_id}, found {len(matches)}")
row = matches[0]
if not row.get("installed") or not row.get("enabled"):
    raise SystemExit(f"{plugin_id} is not installed and enabled")
actual_version = row.get("version")
if actual_version != version:
    raise SystemExit(f"installed version is {actual_version!r}, expected {version!r}")
actual_path = __import__("pathlib").Path((row.get("source") or {}).get("path", "")).resolve()
if actual_path != expected_path:
    raise SystemExit(f"installed source is {actual_path}, expected {expected_path}")
print(actual_path)
' "$PLUGIN@$MARKETPLACE" "$VERSION" "$CONFIGURED_PLUGIN_ROOT")"; then
  refuse "Codex reported an installation that does not match the released marketplace bytes"
fi

# Codex's list call is part of the trust boundary too: it is the last external
# command before success, so close its mutation window with the complete release
# attestation rather than relying on the earlier post-add snapshot.
attest_release_state "Codex installation report" "list"

echo "codex: activated $PLUGIN@$MARKETPLACE v$VERSION"
echo "codex: verified v$VERSION commit $SOURCE_HEAD tree $SOURCE_TREE from $INSTALLED_PATH"
