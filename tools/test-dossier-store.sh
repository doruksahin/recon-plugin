#!/bin/bash
# Hermetic contract tests for Recon's task-packet-store delivery adapter.
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
STORE_DOSSIER="$ROOT/recon/scripts/store-dossier.sh"
REPORT_SKILL="$ROOT/recon/skills/recon-report/SKILL.md"
BASE_TMP="${TMPDIR:-/tmp}"
BASE_TMP="${BASE_TMP%/}"
FIXTURE="$(mktemp -d "$BASE_TMP/recon-dossier-store-test.XXXXXX")"
TICKET="PROJ-123"
PASS_COUNT=0

cleanup() {
  case "$FIXTURE" in
    "$BASE_TMP"/recon-dossier-store-test.*) rm -rf "$FIXTURE" ;;
    *) echo "refusing to remove unexpected fixture path: $FIXTURE" >&2 ;;
  esac
}
trap cleanup EXIT

fail() { echo "dossier store: FAIL — $1" >&2; exit 1; }
pass() { PASS_COUNT=$((PASS_COUNT + 1)); }
assert_contains() { printf '%s\n' "$1" | grep -Fq -- "$2" || fail "$3 (missing '$2')"; }

BIN="$FIXTURE/bin"
FAKE_STORE="$FIXTURE/store"
LOG="$FIXTURE/npm.log"
REAL_FIND="$(command -v find)"
mkdir -p "$BIN" "$FAKE_STORE"

cat >"$BIN/find" <<'FAKE_FIND'
#!/bin/bash
set -euo pipefail
if [ -n "${FAKE_FIND_FAIL_PATH:-}" ] && [ "${1:-}" = "${FAKE_FIND_SOURCE:-}" ]; then
  "$FAKE_REAL_FIND" "$1" \
    -path "$FAKE_FIND_FAIL_PATH" -prune -o \
    -path "$1/runs" -prune -o -print0
  echo "find: $FAKE_FIND_FAIL_PATH: Permission denied" >&2
  exit 1
fi
exec "$FAKE_REAL_FIND" "$@"
FAKE_FIND
chmod +x "$BIN/find"

cat >"$BIN/npm" <<'FAKE'
#!/bin/bash
set -euo pipefail
[ "$(printenv 'npm_config_@doruksahin:registry')" = "https://registry.npmjs.org/" ] \
  || { echo "FAKE_REGISTRY: scoped registry was not pinned" >&2; exit 2; }
printf '%q ' "$@" >>"$FAKE_LOG"
printf '\n' >>"$FAKE_LOG"
[ "${1:-}" = "exec" ] || { echo "FAKE_ARGS: expected npm exec" >&2; exit 2; }
shift
[ "${1:-}" = "--yes" ] || { echo "FAKE_ARGS: expected --yes" >&2; exit 2; }
shift
[ "${1:-}" = "--package=@doruksahin/task-packet-store@0.1.0" ] \
  || { echo "FAKE_ARGS: exact package pin missing" >&2; exit 2; }
shift
[ "${1:-}" = "--" ] && [ "${2:-}" = "task-packet-store" ] \
  || { echo "FAKE_ARGS: binary separator missing" >&2; exit 2; }
shift 2
command_name="${1:-}"
shift

value_for() {
  local wanted="$1"
  shift
  while [ "$#" -gt 0 ]; do
    if [ "$1" = "$wanted" ]; then
      printf '%s\n' "$2"
      return 0
    fi
    shift 2
  done
  return 1
}

if [ "${FAKE_FAIL_PHASE:-}" = "$command_name" ]; then
  echo "FAKE_PHASE: injected $command_name failure" >&2
  exit 1
fi

case "$command_name" in
  doctor)
    store="$(value_for --store "$@")"
    python3 - "$store" <<'PY'
import json, sys
config = json.load(open(sys.argv[1], encoding="utf-8"))
if config["driver"] == "fs":
    print(json.dumps({"driver": "fs", "rclone": None, "rcloneTested": "1.75.0",
                      "credential": "none", "remoteRoot": config["root"]}))
else:
    prefix = config.get("prefix", "")
    suffix = f"/{prefix}" if prefix else ""
    print(json.dumps({"driver": "gdrive", "rclone": "1.75.0", "rcloneTested": "1.75.0",
                      "credential": "PACKET_STORE_DRIVE_TOKEN",
                      "remoteRoot": f":drive,team_drive={config['sharedDriveId']}:{suffix}"}))
PY
    ;;
  begin)
    store="$(value_for --store "$@")"
    ticket="$(value_for --ticket "$@")"
    stage="$(value_for --stage "$@")"
    run_key="$(value_for --run-key "$@")"
    tool="$(value_for --tool "$@")"
    state="$(value_for --state "$@")"
    counter="$FAKE_STORE_ROOT/$ticket.$stage.counter"
    if [ -f "$counter" ]; then
      number=$(( $(cat "$counter") + 1 ))
    else
      number=1
    fi
    printf '%s\n' "$number" >"$counter"
    version="v$number"
    run_directory="stages/$stage/runs/$version"
    destination="$FAKE_STORE_ROOT/$ticket/$run_directory"
    mkdir -p "$destination" "$(dirname "$state")"
    printf '%s\n' "tool: $tool" "run_key: $run_key" >"$destination/run.md"
    printf '%s\n' "$ticket" "$stage" "$version" "$run_key" "$run_directory" "$store" >"$state.fake"
    : >"$state"
    python3 - "$ticket" "$stage" "$version" "$run_key" "$run_directory" "$state" <<'PY'
import json, sys
ticket, stage, version, run_key, run_directory, state = sys.argv[1:]
print(json.dumps({"ticket": ticket, "stage": stage, "version": version,
                  "runKey": run_key, "runDirectory": run_directory, "stateFile": state}))
PY
    ;;
  checkpoint)
    state="$(value_for --state "$@")"
    reason="$(value_for --reason "$@")"
    source="$(value_for --source "$@")"
    mapfile_path="$state.fake"
    ticket="$(sed -n '1p' "$mapfile_path")"
    stage="$(sed -n '2p' "$mapfile_path")"
    version="$(sed -n '3p' "$mapfile_path")"
    run_directory="$(sed -n '5p' "$mapfile_path")"
    destination="$FAKE_STORE_ROOT/$ticket/$run_directory"
    cp -R "$source"/. "$destination"/
    file_count="$(find "$source" -type f | wc -l | tr -d ' ')"
    printf '{"schemaVersion":1,"files":[]}\n' >"$destination/snapshot.json"
    printf '{"version":"%s","reason":"%s","fileCount":%s,"inventorySha256":"%064d"}\n' \
      "$version" "$reason" "$file_count" 0
    ;;
  locate)
    ticket="$(value_for --ticket "$@")"
    relative="$(value_for --path "$@")"
    target="$FAKE_STORE_ROOT/$ticket/$relative"
    if [ "${FAKE_FAIL_PATH:-}" = "$relative" ]; then
      echo "FAKE_LOCATE: injected failure for $relative" >&2
      exit 1
    fi
    [ -e "$target" ] || { echo "FAKE_LOCATE: missing $relative" >&2; exit 1; }
    if [ -d "$target" ]; then kind=directory; else kind=file; fi
    python3 - "$ticket" "$relative" "$kind" "$target" <<'PY'
import json, sys
ticket, relative, kind, location = sys.argv[1:]
print(json.dumps({"ticket": ticket, "driver": "fs", "relativePath": relative,
                  "kind": kind, "location": location}))
PY
    ;;
  *)
    echo "FAKE_ARGS: unexpected command $command_name" >&2
    exit 2
    ;;
esac
FAKE
chmod +x "$BIN/npm"

make_workspace() {
  local ticket="$1"
  local workspace="$FIXTURE/work/$ticket"
  mkdir -p "$workspace/triage" "$workspace/report" "$workspace/repro/session" "$workspace/runs/old/report"
  printf 'skill: recon-triage\nplugin_version: 0.21.0\nstarted: 2026-09-05T00:00:00Z\nticket: %s\n' "$ticket" >"$workspace/meta.yaml"
  printf 'disposition: READY\n' >"$workspace/triage/triage.yaml"
  printf '<!doctype html><title>%s Recon dossier</title>\n' "$ticket" >"$workspace/report/dossier.html"
  printf 'recorded support\n' >"$workspace/repro/session/session.webm"
  printf '<!doctype html><title>archived and forbidden</title>\n' >"$workspace/runs/old/report/dossier.html"
  printf '%s\n' "$workspace"
}

current_tree_digest() {
  python3 - "$1" <<'PY'
import hashlib
import os
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
digest = hashlib.sha256()
for directory, names, files in os.walk(root):
    if pathlib.Path(directory) == root:
        names[:] = [name for name in names if name != "runs"]
    names.sort()
    files.sort()
    for name in files:
        path = pathlib.Path(directory, name)
        relative = path.relative_to(root).as_posix()
        digest.update(relative.encode())
        digest.update(b"\0")
        digest.update(path.read_bytes())
print(digest.hexdigest())
PY
}

CONFIG="$FIXTURE/store.json"
printf '{"driver":"fs","root":"%s"}\n' "$FAKE_STORE" >"$CONFIG"
WORKSPACE="$(make_workspace "$TICKET")"
ENV_ARGS=(PATH="$BIN:$PATH" FAKE_REAL_FIND="$REAL_FIND" FAKE_STORE_ROOT="$FAKE_STORE" FAKE_LOG="$LOG")

chmod 000 "$WORKSPACE/runs"
RECEIPT1="$(env "${ENV_ARGS[@]}" bash "$STORE_DOSSIER" --store "$CONFIG" --ticket "$TICKET" --source "$WORKSPACE")"
chmod 700 "$WORKSPACE/runs"
python3 - "$RECEIPT1" "$FAKE_STORE" "$TICKET" <<'PY' || fail "first receipt contract"
import json, pathlib, sys
receipt = json.loads(sys.argv[1])
root, ticket = pathlib.Path(sys.argv[2]), sys.argv[3]
assert receipt["package"] == "@doruksahin/task-packet-store@0.1.0"
assert receipt["tool"] == "recon@0.21.0"
assert receipt["ticket"] == ticket and receipt["stage"] == "10-recon" and receipt["version"] == "v1"
assert receipt["primaryResult"] == "report/dossier.html"
run = root / ticket / "stages/10-recon/runs/v1"
assert receipt["locations"]["run"]["location"] == str(run)
assert receipt["locations"]["primary"]["location"] == str(run / "report/dossier.html")
assert receipt["locations"]["runRecord"]["location"] == str(run / "run.md")
assert receipt["locations"]["snapshot"]["location"] == str(run / "snapshot.json")
assert (run / "repro/session/session.webm").read_text() == "recorded support\n"
assert not (run / "runs").exists()
PY
pass

grep -Fq 'If no absolute store config was supplied, skip this step without probing for one.' "$REPORT_SKILL" \
  || fail "report skill lost the no-store behavior"
if grep -Fq 'store-dossier.sh' "$ROOT/recon/skills/recon-triage/SKILL.md" \
  || grep -Fq 'store-dossier.sh' "$ROOT/recon/skills/recon-discovery/SKILL.md"; then
  fail "a Jira delivery path invokes storage without an explicit report input"
fi
pass

V1_DOSSIER="$FAKE_STORE/$TICKET/stages/10-recon/runs/v1/report/dossier.html"
V1_HASH="$(shasum -a 256 "$V1_DOSSIER" | cut -d' ' -f1)"
printf '<!doctype html><title>%s second Recon dossier</title>\n' "$TICKET" >"$WORKSPACE/report/dossier.html"
RECEIPT2="$(env "${ENV_ARGS[@]}" bash "$STORE_DOSSIER" --store "$CONFIG" --ticket "$TICKET" --source "$WORKSPACE")"
assert_contains "$RECEIPT2" '"version":"v2"' "repeat delivery reserves v2"
[ "$(shasum -a 256 "$V1_DOSSIER" | cut -d' ' -f1)" = "$V1_HASH" ] || fail "repeat delivery changed v1"
pass

EXPECTED_CALLS=14
[ "$(wc -l <"$LOG" | tr -d ' ')" -eq "$EXPECTED_CALLS" ] || fail "expected $EXPECTED_CALLS pinned package calls"
if grep -vF -- '--package=@doruksahin/task-packet-store@0.1.0' "$LOG" | grep -q .; then
  fail "a package call was not exactly pinned"
fi
pass

TRAVERSAL_TICKET="PROJ-126"
TRAVERSAL_WORKSPACE="$(make_workspace "$TRAVERSAL_TICKET")"
TRAVERSAL_WORKSPACE="$(cd "$TRAVERSAL_WORKSPACE" && pwd -P)"
if env "${ENV_ARGS[@]}" \
  FAKE_FIND_SOURCE="$TRAVERSAL_WORKSPACE" \
  FAKE_FIND_FAIL_PATH="$TRAVERSAL_WORKSPACE/repro/session" \
  bash "$STORE_DOSSIER" \
  --store "$CONFIG" --ticket "$TRAVERSAL_TICKET" --source "$TRAVERSAL_WORKSPACE" \
  >"$FIXTURE/traversal.out" 2>"$FIXTURE/traversal.err"; then
  fail "unreadable current-run evidence unexpectedly passed"
fi
[ ! -s "$FIXTURE/traversal.out" ] || fail "traversal failure emitted a success receipt"
assert_contains "$(cat "$FIXTURE/traversal.err")" "source traversal failed" "traversal failure diagnostic"
[ ! -e "$FAKE_STORE/$TRAVERSAL_TICKET/stages/10-recon/runs/v1/run.md" ] \
  || fail "traversal failure reserved a run"
pass

OVERLAP_TICKET="PROJ-127"
OVERLAP_WORKSPACE="$(make_workspace "$OVERLAP_TICKET")"
OVERLAP_BEFORE="$(current_tree_digest "$OVERLAP_WORKSPACE")"
OVERLAP_CONFIG="$FIXTURE/overlap-store.json"
printf '{"driver":"fs","root":"%s"}\n' "$FIXTURE/work" >"$OVERLAP_CONFIG"
if env "${ENV_ARGS[@]}" bash "$STORE_DOSSIER" \
  --store "$OVERLAP_CONFIG" --ticket "$OVERLAP_TICKET" --source "$OVERLAP_WORKSPACE" \
  >"$FIXTURE/overlap.out" 2>"$FIXTURE/overlap.err"; then
  fail "source-equals-packet destination overlap unexpectedly passed"
fi
[ ! -s "$FIXTURE/overlap.out" ] || fail "overlap failure emitted a success receipt"
assert_contains "$(cat "$FIXTURE/overlap.err")" "store destination overlaps source workspace" "overlap diagnostic"
[ ! -e "$OVERLAP_WORKSPACE/stages" ] || fail "overlap failure reserved a run inside the source"
[ "$(current_tree_digest "$OVERLAP_WORKSPACE")" = "$OVERLAP_BEFORE" ] || fail "overlap failure changed source bytes"

ALIAS_TICKET="PROJ-128"
ALIAS_WORKSPACE="$(make_workspace "$ALIAS_TICKET")"
ALIAS_BEFORE="$(current_tree_digest "$ALIAS_WORKSPACE")"
ln -s "$FIXTURE/work" "$FIXTURE/work-alias"
ALIAS_CONFIG="$FIXTURE/alias-store.json"
printf '{"driver":"fs","root":"%s"}\n' "$FIXTURE/work-alias" >"$ALIAS_CONFIG"
if env "${ENV_ARGS[@]}" bash "$STORE_DOSSIER" \
  --store "$ALIAS_CONFIG" --ticket "$ALIAS_TICKET" --source "$ALIAS_WORKSPACE" \
  >"$FIXTURE/alias.out" 2>"$FIXTURE/alias.err"; then
  fail "symlink-aliased destination overlap unexpectedly passed"
fi
[ ! -s "$FIXTURE/alias.out" ] || fail "symlink-alias overlap emitted a success receipt"
assert_contains "$(cat "$FIXTURE/alias.err")" "store destination overlaps source workspace" "symlink-alias diagnostic"
[ ! -e "$ALIAS_WORKSPACE/stages" ] || fail "symlink-alias overlap reserved a run inside the source"
[ "$(current_tree_digest "$ALIAS_WORKSPACE")" = "$ALIAS_BEFORE" ] || fail "symlink-alias overlap changed source bytes"

DESCENDANT_TICKET="PROJ-129"
DESCENDANT_WORKSPACE="$(make_workspace "$DESCENDANT_TICKET")"
DESCENDANT_BEFORE="$(current_tree_digest "$DESCENDANT_WORKSPACE")"
DESCENDANT_CONFIG="$FIXTURE/descendant-store.json"
printf '{"driver":"fs","root":"%s"}\n' "$DESCENDANT_WORKSPACE/packet-store" >"$DESCENDANT_CONFIG"
if env "${ENV_ARGS[@]}" bash "$STORE_DOSSIER" \
  --store "$DESCENDANT_CONFIG" --ticket "$DESCENDANT_TICKET" --source "$DESCENDANT_WORKSPACE" \
  >"$FIXTURE/descendant.out" 2>"$FIXTURE/descendant.err"; then
  fail "destination-inside-source overlap unexpectedly passed"
fi
[ ! -s "$FIXTURE/descendant.out" ] || fail "descendant overlap emitted a success receipt"
assert_contains "$(cat "$FIXTURE/descendant.err")" "store destination overlaps source workspace" "descendant overlap diagnostic"
[ ! -e "$DESCENDANT_WORKSPACE/packet-store" ] || fail "descendant overlap created the store inside the source"
[ "$(current_tree_digest "$DESCENDANT_WORKSPACE")" = "$DESCENDANT_BEFORE" ] || fail "descendant overlap changed source bytes"
pass

DOCTOR_TICKET="PROJ-130"
DOCTOR_WORKSPACE="$(make_workspace "$DOCTOR_TICKET")"
if env "${ENV_ARGS[@]}" FAKE_FAIL_PHASE=doctor bash "$STORE_DOSSIER" \
  --store "$CONFIG" --ticket "$DOCTOR_TICKET" --source "$DOCTOR_WORKSPACE" \
  >"$FIXTURE/doctor.out" 2>"$FIXTURE/doctor.err"; then
  fail "injected doctor failure unexpectedly passed"
fi
[ ! -s "$FIXTURE/doctor.out" ] || fail "doctor failure emitted a success receipt"
assert_contains "$(cat "$FIXTURE/doctor.err")" "doctor failed" "doctor failure diagnostic"
[ ! -e "$FAKE_STORE/$DOCTOR_TICKET/stages/10-recon/runs/v1/run.md" ] \
  || fail "doctor failure reserved a run"
pass

if env "${ENV_ARGS[@]}" bash "$STORE_DOSSIER" --store "$CONFIG" --ticket "$TICKET" --source relative \
  >"$FIXTURE/relative.out" 2>"$FIXTURE/relative.err"; then
  fail "relative source unexpectedly passed"
fi
[ ! -s "$FIXTURE/relative.out" ] || fail "relative-source failure emitted a success receipt"
assert_contains "$(cat "$FIXTURE/relative.err")" "--source must be an absolute path" "relative-source diagnostic"
pass

printf 'not registered\n' >"$WORKSPACE/rogue.txt"
if env "${ENV_ARGS[@]}" bash "$STORE_DOSSIER" --store "$CONFIG" --ticket "$TICKET" --source "$WORKSPACE" \
  >"$FIXTURE/lint.out" 2>"$FIXTURE/lint.err"; then
  fail "unregistered current-run file unexpectedly passed"
fi
[ ! -s "$FIXTURE/lint.out" ] || fail "lint failure emitted a success receipt"
assert_contains "$(cat "$FIXTURE/lint.err")" "workspace validation failed" "lint failure diagnostic"
rm "$WORKSPACE/rogue.txt"
pass

FAIL_TICKET="PROJ-124"
FAIL_WORKSPACE="$(make_workspace "$FAIL_TICKET")"
if env "${ENV_ARGS[@]}" FAKE_FAIL_PHASE=checkpoint bash "$STORE_DOSSIER" \
  --store "$CONFIG" --ticket "$FAIL_TICKET" --source "$FAIL_WORKSPACE" \
  >"$FIXTURE/checkpoint.out" 2>"$FIXTURE/checkpoint.err"; then
  fail "injected checkpoint failure unexpectedly passed"
fi
[ ! -s "$FIXTURE/checkpoint.out" ] || fail "checkpoint failure emitted a success receipt"
assert_contains "$(cat "$FIXTURE/checkpoint.err")" "checkpoint failed" "checkpoint failure diagnostic"
[ -f "$FAKE_STORE/$FAIL_TICKET/stages/10-recon/runs/v1/run.md" ] || fail "failed checkpoint lost its reserved run record"
[ ! -e "$FAKE_STORE/$FAIL_TICKET/stages/10-recon/runs/v1/snapshot.json" ] || fail "failed checkpoint wrote snapshot"
pass

LOCATE_TICKET="PROJ-125"
LOCATE_WORKSPACE="$(make_workspace "$LOCATE_TICKET")"
FAIL_PATH="stages/10-recon/runs/v1/report/dossier.html"
if env "${ENV_ARGS[@]}" FAKE_FAIL_PATH="$FAIL_PATH" bash "$STORE_DOSSIER" \
  --store "$CONFIG" --ticket "$LOCATE_TICKET" --source "$LOCATE_WORKSPACE" \
  >"$FIXTURE/locate.out" 2>"$FIXTURE/locate.err"; then
  fail "injected locate failure unexpectedly passed"
fi
[ ! -s "$FIXTURE/locate.out" ] || fail "locate failure emitted a success receipt"
assert_contains "$(cat "$FIXTURE/locate.err")" "locate-primary failed" "locate failure diagnostic"
[ -f "$FAKE_STORE/$LOCATE_TICKET/stages/10-recon/runs/v1/snapshot.json" ] || fail "locate failure did not reach persisted checkpoint"
pass

echo "dossier store: PASS — $PASS_COUNT contract groups"
