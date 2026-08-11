#!/bin/bash
# record-repro.sh <TICKET-ID> <start|exec|stop|status> [args…] — the recorded
# repro runtime rail. Brackets every repro browser action inside a proofshot
# session so the action log and video are mechanical provenance for repro.md.
#
# Discipline the rail owns (the skill never calls proofshot/agent-browser raw):
#   - cwd is pinned to $RECON_ROOT/<TICKET>/repro/ for every proofshot call and
#     a workspace-local proofshot.config.json (output: ./session-staging) is
#     written, so start/exec/stop always resolve the SAME session and any
#     config higher in the tree is shadowed.
#   - exec refuses (exit 2) when no recording is active: proofshot would
#     otherwise execute UNLOGGED and provenance would silently vanish.
#   - stop relocates step-numbered screenshots (<n>-<slug>.png) into
#     repro/exhibits/, finalizes the bundle at repro/session/, and removes the
#     staging dir + config so no transient file survives to fail lint.
#   - start replaces a previously finalized repro/session/ (replacement
#     semantics, like Jira attachments); the one active-recording failure mode
#     gets one close-and-retry, then remains an honest failure if it persists.
# The proofshot version pin lives in reconctl.sh (`preflight repro`), the one
# owner of that fact; this rail only requires the binaries to exist.
# Exit 0 ok, 1 violation/failure, 2 missing inputs or broken install.
set -euo pipefail

TICKET="${1:?usage: record-repro.sh <TICKET-ID> <start|exec|stop|status> [args...]}"
CMD="${2:?usage: record-repro.sh <TICKET-ID> <start|exec|stop|status> [args...]}"
shift 2
case "$TICKET" in
  *[!A-Za-z0-9-]* | "") echo "invalid ticket id: $TICKET" >&2; exit 2 ;;
esac

ROOT="${RECON_ROOT:-$HOME/.claude/recon}"
case "$ROOT" in
  /*) ;;
  *) echo "RECON_ROOT must be an absolute path: $ROOT" >&2; exit 2 ;;
esac
DIR="${ROOT%/}/$TICKET"
[ -d "$DIR" ] || { echo "no workspace: $DIR" >&2; exit 2; }

REPRO_DIR="$DIR/repro"
STAGING="$REPRO_DIR/session-staging"
CONFIG="$REPRO_DIR/proofshot.config.json"
FINAL="$REPRO_DIR/session"
MARKER="$STAGING/.session.json"

for bin in proofshot agent-browser; do
  command -v "$bin" >/dev/null 2>&1 || {
    echo "$bin not found — install the recorder (reconctl.sh preflight repro prints the check)" >&2
    exit 2
  }
done

cleanup_staging() {
  rm -rf "$STAGING"
  rm -f "$CONFIG"
}

# The marker is the ONLY authority on whether this run owns the dev server.
# proofshot records serverAlreadyRunning there, so its log prose cannot
# distinguish "the recording started it" from "one was already up" — scraping a
# log line would kill a dev server the developer started. Read the marker BEFORE
# proofshot stop clears it. Empty output means "this run owns nothing".
owned_server_port() {
  python3 -c '
import json, sys
try:
    state = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)
if state.get("serverAlreadyRunning") is False and state.get("port"):
    print(state["port"])
' "$MARKER" 2>/dev/null || true
}

stop_owned_server() {
  local server_port="$1" message="$2" pids=""
  [ -n "$server_port" ] || return 0
  command -v lsof >/dev/null 2>&1 || return 0
  pids="$(lsof -ti ":$server_port" 2>/dev/null || true)"
  [ -n "$pids" ] || return 0
  # shellcheck disable=SC2086
  kill $pids 2>/dev/null || true
  echo "$message on :$server_port"
}

recover_failed_start() {
  local start_log="$1"
  local session=""
  local session_dir=""
  local session_base=""
  local server_port=""
  local closed=0

  # ProofShot reports the agent-browser session in its failure output. When a
  # timeout suppresses that output, recover it from the one staging directory
  # it already created; the directory begins with ProofShot's timestamp seed.
  session="$(sed -n "s/.*agent-browser --session '\([^']*\)'.*/\1/p" "$start_log" | tail -n 1)"
  if [ -z "$session" ]; then
    session_dir="$(find "$STAGING" -mindepth 1 -maxdepth 1 -type d -print -quit 2>/dev/null || true)"
    if [ -n "$session_dir" ]; then
      session_base="${session_dir##*/}"
      session="proofshot-$(printf '%s' "$session_base" | cut -c1-19)"
    fi
  fi

  if [ -n "$session" ]; then
    if agent-browser --session "$session" record stop >/dev/null 2>&1; then
      echo "RECOVERY: stopped stranded recording session $session"
    fi
    if agent-browser --session "$session" close >/dev/null 2>&1; then
      echo "RECOVERY: closed stranded browser session $session"
      closed=1
    fi
  fi

  # A failed start can still have written the marker, so the same ownership
  # authority the stop path uses applies here — never the log's prose.
  server_port="$(owned_server_port)"
  stop_owned_server "$server_port" \
    "RECOVERY: stopped the dev server this failed recording started"

  [ "$closed" -eq 1 ]
}

case "$CMD" in
  start)
    mkdir -p "$REPRO_DIR"
    if [ -d "$FINAL" ]; then
      echo "REPLACED: prior finalized session removed (recon-owned artifacts replace, never accumulate)"
      rm -rf "$FINAL"
    fi
    cleanup_staging
    printf '{\n  "output": "./session-staging"\n}\n' > "$CONFIG"
    start_log="$REPRO_DIR/.record-repro-start.log"
    if (cd "$REPRO_DIR" && proofshot start --force "$@") >"$start_log" 2>&1; then
      cat "$start_log"
      rm -f "$start_log"
      echo "RECORDING: active — drive the UI only through record-repro.sh $TICKET exec"
    else
      cat "$start_log" >&2
      if [ -n "$(sed -n '/Recording already active/p' "$start_log")" ] \
        && recover_failed_start "$start_log"; then
        echo "RECOVERY: retrying the recording start once after closing the partial session"
        rm -f "$start_log"
        cleanup_staging
        printf '{\n  "output": "./session-staging"\n}\n' > "$CONFIG"
        if (cd "$REPRO_DIR" && proofshot start --force "$@") >"$start_log" 2>&1; then
          cat "$start_log"
          rm -f "$start_log"
          echo "RECORDING: active — drive the UI only through record-repro.sh $TICKET exec"
        else
          cat "$start_log" >&2
          recover_failed_start "$start_log" || true
          rm -f "$start_log"
          cleanup_staging
          echo "RECORDING: start failed after one recovery retry — report an honest failed repro (never fall back to unrecorded browsing)" >&2
          exit 1
        fi
      else
        recover_failed_start "$start_log" || true
        rm -f "$start_log"
        cleanup_staging
        echo "RECORDING: start failed — report an honest failed repro (never fall back to unrecorded browsing)" >&2
        exit 1
      fi
    fi
    ;;
  exec)
    if [ ! -f "$MARKER" ]; then
      echo "no active recording — run record-repro.sh $TICKET start first (unrecorded actions leave no provenance)" >&2
      exit 2
    fi
    (cd "$REPRO_DIR" && proofshot exec "$@")
    ;;
  stop)
    if [ ! -f "$MARKER" ]; then
      echo "no active recording to stop — run record-repro.sh $TICKET start first" >&2
      exit 2
    fi
    # proofshot leaves the --run dev server behind (its own restarts self-heal
    # the port, but a recon stage must not leak side effects past STOP). Resolve
    # ownership BEFORE proofshot stop clears the marker.
    server_port="$(owned_server_port)"
    (cd "$REPRO_DIR" && proofshot stop "$@")
    session_dir=""
    count=0
    while IFS= read -r d; do
      session_dir="$d"
      count=$((count + 1))
    done < <(find "$STAGING" -mindepth 1 -maxdepth 1 -type d)
    if [ "$count" -ne 1 ] || [ -z "$session_dir" ]; then
      echo "expected exactly one session dir under session-staging, found $count — broken recorder run" >&2
      exit 1
    fi
    mkdir -p "$REPRO_DIR/exhibits"
    while IFS= read -r png; do
      base="$(basename "$png")"
      case "$base" in
        [1-9]*-*.png)
          mv "$png" "$REPRO_DIR/exhibits/$base"
          echo "EXHIBIT: exhibits/$base"
          ;;
      esac
    done < <(find "$session_dir" -mindepth 1 -maxdepth 1 -type f -name '*.png')
    rm -rf "$FINAL"
    mv "$session_dir" "$FINAL"
    cleanup_staging
    actions="$(python3 -c 'import json,sys;print(len(json.load(open(sys.argv[1]))))' "$FINAL/session-log.json" 2>/dev/null || echo 0)"
    video_bytes="$(wc -c < "$FINAL/session.webm" 2>/dev/null | tr -d ' ' || echo 0)"
    echo "SESSION: repro/session ($actions logged action(s), session.webm $video_bytes bytes)"
    stop_owned_server "$server_port" \
      "SERVER: stopped the dev server this recording started"
    ;;
  status)
    if [ -f "$MARKER" ]; then
      echo "recording: active"
    else
      echo "recording: none"
    fi
    if [ -d "$FINAL" ]; then
      echo "session: finalized (repro/session)"
    else
      echo "session: none"
    fi
    ;;
  *)
    echo "unknown command: $CMD (expected start|exec|stop|status)" >&2
    exit 2
    ;;
esac
