#!/bin/bash
# store-dossier.sh --store <abs-config> --ticket <TICKET> --source <abs-workspace>
#
# Delivery-only task-packet-store adapter for an already-rendered Recon run.
# Stages the complete current workspace without opening top-level runs/, checks
# the staged tree against Recon's registry, reserves 10-recon, checkpoints it,
# and emits one JSON receipt only after every saved location resolves.
set -euo pipefail

PACKAGE="@doruksahin/task-packet-store@0.1.0"
STAGE="10-recon"
PRIMARY="report/dossier.html"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

usage() {
  echo "usage: store-dossier.sh --store <absolute-config.json> --ticket <TICKET> --source <absolute-current-workspace>" >&2
  exit 2
}

fail() {
  local status="$1"
  shift
  echo "dossier-store: $*" >&2
  exit "$status"
}

STORE=""
TICKET=""
SOURCE=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --store)
      [ "$#" -ge 2 ] || usage
      STORE="$2"
      shift 2
      ;;
    --ticket)
      [ "$#" -ge 2 ] || usage
      TICKET="$2"
      shift 2
      ;;
    --source)
      [ "$#" -ge 2 ] || usage
      SOURCE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    *)
      usage
      ;;
  esac
done

[ -n "$STORE" ] && [ -n "$TICKET" ] && [ -n "$SOURCE" ] || usage
case "$STORE" in /*) ;; *) fail 2 "--store must be an absolute path" ;; esac
case "$SOURCE" in /*) ;; *) fail 2 "--source must be an absolute path" ;; esac
[[ "$TICKET" =~ ^[A-Z][A-Z0-9]+-[0-9]+$ ]] || fail 2 "invalid ticket: $TICKET"
[ -f "$STORE" ] || fail 2 "store config is not a file: $STORE"

SOURCE="${SOURCE%/}"
[ -d "$SOURCE" ] || fail 2 "source workspace is not a directory: $SOURCE"
[ ! -L "$SOURCE" ] || fail 2 "source workspace must not be a symlink: $SOURCE"
[ "$(basename "$SOURCE")" = "$TICKET" ] || fail 2 "source workspace basename must equal ticket $TICKET"
STORE="$(cd "$(dirname "$STORE")" && pwd -P)/$(basename "$STORE")"
SOURCE="$(cd "$SOURCE" && pwd -P)"

for required in meta.yaml triage/triage.yaml "$PRIMARY"; do
  [ -f "$SOURCE/$required" ] && [ ! -L "$SOURCE/$required" ] \
    || fail 2 "required regular current-run file is missing: $required"
done

for command_name in node npm python3 find cp; do
  command -v "$command_name" >/dev/null 2>&1 \
    || fail 2 "required command is unavailable: $command_name"
done
NODE_MAJOR="$(node -p 'Number(process.versions.node.split(".")[0])')"
[ "$NODE_MAJOR" -ge 20 ] || fail 2 "Node.js 20 or newer is required"

PLUGIN_VERSION="$({ python3 - "$SOURCE/meta.yaml" "$TICKET" <<'PY'
import re
import sys

path, expected_ticket = sys.argv[1:]
values = {}
for raw in open(path, encoding="utf-8"):
    match = re.match(r"^(ticket|plugin_version):[ ]*([^#\r\n]+?)[ ]*$", raw)
    if not match:
        continue
    key, value = match.groups()
    if key in values:
        raise SystemExit(f"dossier-store: duplicate {key} in meta.yaml")
    values[key] = value.strip("'\"")
if values.get("ticket") != expected_ticket:
    raise SystemExit(f"dossier-store: meta.yaml ticket does not equal {expected_ticket}")
version = values.get("plugin_version", "")
if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+(?:[-+][0-9A-Za-z.-]+)?", version):
    raise SystemExit("dossier-store: meta.yaml plugin_version is not a semantic version")
print(version)
PY
} 2>&1)" || { echo "$PLUGIN_VERSION" >&2; exit 2; }
TOOL="recon@$PLUGIN_VERSION"

BASE_TMP="$(cd "${TMPDIR:-/tmp}" && pwd -P)"
WORK="$(mktemp -d "$BASE_TMP/recon-dossier-store.XXXXXX")"
cleanup() {
  case "$WORK" in
    "$BASE_TMP"/recon-dossier-store.*) rm -rf "$WORK" ;;
    *) echo "dossier-store: refusing to remove unexpected temporary path: $WORK" >&2 ;;
  esac
}
trap cleanup EXIT

TPS=(
  env 'npm_config_@doruksahin:registry=https://registry.npmjs.org/'
  npm exec --yes "--package=$PACKAGE" -- task-packet-store
)

run_tps() {
  local phase="$1"
  shift
  local stdout_file="$WORK/$phase.json"
  local stderr_file="$WORK/$phase.err"
  local status
  set +e
  "${TPS[@]}" "$@" >"$stdout_file" 2>"$stderr_file"
  status=$?
  set -e
  if [ "$status" -ne 0 ]; then
    if [ -s "$stderr_file" ]; then
      sed 's/^/  /' "$stderr_file" >&2
    fi
    fail "$status" "$phase failed (task-packet-store exit $status)"
  fi
  python3 - "$stdout_file" "$phase" <<'PY' >/dev/null
import json
import sys

path, phase = sys.argv[1:]
try:
    value = json.load(open(path, encoding="utf-8"))
except Exception as error:
    raise SystemExit(f"dossier-store: {phase} returned invalid JSON: {error}")
if not isinstance(value, dict):
    raise SystemExit(f"dossier-store: {phase} did not return a JSON object")
PY
}

# Ask the package to validate its own config and expose its resolved transport
# metadata. For filesystem stores only, reject every source/destination overlap
# before begin can create run.md inside the live Recon workspace.
run_tps doctor doctor --store "$STORE"
python3 - "$WORK/doctor.json" "$SOURCE" "$TICKET" <<'PY'
import json
import os
import sys

doctor_path, source, ticket = sys.argv[1:]
with open(doctor_path, encoding="utf-8") as handle:
    doctor = json.load(handle)

driver = doctor.get("driver")
remote_root = doctor.get("remoteRoot")
if driver not in {"fs", "gdrive"} or not isinstance(remote_root, str) or not remote_root:
    raise SystemExit("dossier-store: doctor returned incoherent store metadata")
if driver != "fs":
    raise SystemExit(0)
if not os.path.isabs(remote_root):
    raise SystemExit("dossier-store: doctor returned a non-absolute filesystem root")

def intended_realpath(target):
    missing = []
    current = os.path.abspath(target)
    while not os.path.exists(current):
        parent, name = os.path.dirname(current), os.path.basename(current)
        if parent == current:
            break
        missing.insert(0, name)
        current = parent
    return os.path.join(os.path.realpath(current), *missing)

source = os.path.realpath(source)
destination = intended_realpath(os.path.join(remote_root, ticket))
contains = lambda outer, inner: inner == outer or inner.startswith(outer + os.sep)
if contains(source, destination) or contains(destination, source):
    raise SystemExit("dossier-store: store destination overlaps source workspace")
PY

STAGED_ROOT="$WORK/current"
STAGED_SOURCE="$STAGED_ROOT/$TICKET"
mkdir -p "$STAGED_SOURCE"

# Prune the archive before traversal. Recon invariant 3 forbids opening,
# listing, copying, or citing anything below the current workspace's runs/.
SOURCE_ENTRIES="$WORK/source-entries"
SOURCE_FIND_ERR="$WORK/source-find.err"
set +e
find "$SOURCE" -path "$SOURCE/runs" -prune -o -print0 \
  >"$SOURCE_ENTRIES" 2>"$SOURCE_FIND_ERR"
FIND_STATUS=$?
set -e
if [ "$FIND_STATUS" -ne 0 ]; then
  if [ -s "$SOURCE_FIND_ERR" ]; then
    sed 's/^/  /' "$SOURCE_FIND_ERR" >&2
  fi
  fail "$FIND_STATUS" "source traversal failed (find exit $FIND_STATUS)"
fi

while IFS= read -r -d '' entry; do
  [ "$entry" = "$SOURCE" ] && continue
  relative="${entry#"$SOURCE"/}"
  destination="$STAGED_SOURCE/$relative"
  if [ -L "$entry" ]; then
    fail 2 "source workspace contains a symlink: $relative"
  elif [ -d "$entry" ]; then
    mkdir -p "$destination"
  elif [ -f "$entry" ]; then
    mkdir -p "$(dirname "$destination")"
    cp -p "$entry" "$destination"
  else
    fail 2 "source workspace contains a non-regular entry: $relative"
  fi
done <"$SOURCE_ENTRIES"

set +e
LINT_OUTPUT="$(RECON_ROOT="$STAGED_ROOT" bash "$SCRIPT_DIR/lint-workspace.sh" "$TICKET" 2>&1)"
LINT_STATUS=$?
set -e
[ "$LINT_STATUS" -eq 0 ] || fail "$LINT_STATUS" "workspace validation failed: $LINT_OUTPUT"

RUN_KEY="recon.${TICKET//-/}.$(date -u +%Y%m%dT%H%M%SZ).${WORK##*.}"
STATE="$WORK/run-state.json"

run_tps begin begin \
  --store "$STORE" \
  --ticket "$TICKET" \
  --stage "$STAGE" \
  --run-key "$RUN_KEY" \
  --tool "$TOOL" \
  --state "$STATE"

read -r VERSION RUN_DIRECTORY < <(python3 - "$WORK/begin.json" "$TICKET" "$STAGE" "$RUN_KEY" "$STATE" <<'PY'
import json
import re
import sys

path, ticket, stage, run_key, state = sys.argv[1:]
value = json.load(open(path, encoding="utf-8"))
version = value.get("version")
expected = f"stages/{stage}/runs/{version}"
if (
    value.get("ticket") != ticket
    or value.get("stage") != stage
    or value.get("runKey") != run_key
    or __import__("os").path.realpath(str(value.get("stateFile", ""))) != __import__("os").path.realpath(state)
    or not isinstance(version, str)
    or not re.fullmatch(r"v[1-9][0-9]*", version)
    or value.get("runDirectory") != expected
):
    raise SystemExit("dossier-store: begin returned an incoherent reservation")
print(version, expected)
PY
)

run_tps checkpoint checkpoint \
  --state "$STATE" \
  --reason recon-dossier-rendered \
  --source "$STAGED_SOURCE"

run_tps locate-run locate \
  --store "$STORE" --ticket "$TICKET" --path "$RUN_DIRECTORY"
run_tps locate-primary locate \
  --store "$STORE" --ticket "$TICKET" --path "$RUN_DIRECTORY/$PRIMARY"
run_tps locate-run-record locate \
  --store "$STORE" --ticket "$TICKET" --path "$RUN_DIRECTORY/run.md"
run_tps locate-snapshot locate \
  --store "$STORE" --ticket "$TICKET" --path "$RUN_DIRECTORY/snapshot.json"

python3 - \
  "$WORK/begin.json" \
  "$WORK/checkpoint.json" \
  "$WORK/locate-run.json" \
  "$WORK/locate-primary.json" \
  "$WORK/locate-run-record.json" \
  "$WORK/locate-snapshot.json" \
  "$PACKAGE" "$TOOL" "$TICKET" "$STAGE" "$VERSION" "$SOURCE" "$PRIMARY" "$LINT_OUTPUT" <<'PY'
import json
import re
import sys

(
    begin_path,
    checkpoint_path,
    run_path,
    primary_path,
    record_path,
    snapshot_path,
    package,
    tool,
    ticket,
    stage,
    version,
    source,
    primary,
    lint,
) = sys.argv[1:]

def load(path):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)

begin = load(begin_path)
checkpoint = load(checkpoint_path)
run = load(run_path)
primary_location = load(primary_path)
run_record = load(record_path)
snapshot = load(snapshot_path)
run_directory = f"stages/{stage}/runs/{version}"

if checkpoint.get("version") != version:
    raise SystemExit("dossier-store: checkpoint version does not match reservation")
if checkpoint.get("reason") != "recon-dossier-rendered":
    raise SystemExit("dossier-store: checkpoint reason does not match request")
if not isinstance(checkpoint.get("fileCount"), int) or checkpoint["fileCount"] < 3:
    raise SystemExit("dossier-store: checkpoint file count does not cover the required current run")
if not re.fullmatch(r"[0-9a-f]{64}", str(checkpoint.get("inventorySha256", ""))):
    raise SystemExit("dossier-store: checkpoint inventory digest is invalid")

expected_locations = (
    ("run", run, run_directory, "directory"),
    ("primary", primary_location, f"{run_directory}/{primary}", "file"),
    ("runRecord", run_record, f"{run_directory}/run.md", "file"),
    ("snapshot", snapshot, f"{run_directory}/snapshot.json", "file"),
)
drivers = set()
for label, value, relative, kind in expected_locations:
    if value.get("ticket") != ticket or value.get("relativePath") != relative or value.get("kind") != kind:
        raise SystemExit(f"dossier-store: {label} location does not match the saved run")
    if value.get("driver") not in {"fs", "gdrive"} or not isinstance(value.get("location"), str) or not value["location"]:
        raise SystemExit(f"dossier-store: {label} location is incomplete")
    drivers.add(value["driver"])
if len(drivers) != 1:
    raise SystemExit("dossier-store: saved locations disagree on transport")

receipt = {
    "schemaVersion": 1,
    "operation": "recon-dossier-store",
    "package": package,
    "tool": tool,
    "ticket": ticket,
    "stage": stage,
    "version": version,
    "sourceDirectory": source,
    "primaryResult": primary,
    "lint": lint,
    "checkpoint": checkpoint,
    "locations": {
        "run": run,
        "primary": primary_location,
        "runRecord": run_record,
        "snapshot": snapshot,
    },
}
print(json.dumps(receipt, separators=(",", ":")))
PY
