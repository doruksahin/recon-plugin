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
#     semantics, like Jira attachments) and cleans staging on failure.
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

case "$CMD" in
  start)
    mkdir -p "$REPRO_DIR"
    if [ -d "$FINAL" ]; then
      echo "REPLACED: prior finalized session removed (recon-owned artifacts replace, never accumulate)"
      rm -rf "$FINAL"
    fi
    cleanup_staging
    printf '{\n  "output": "./session-staging"\n}\n' > "$CONFIG"
    if (cd "$REPRO_DIR" && proofshot start --force "$@"); then
      echo "RECORDING: active — drive the UI only through record-repro.sh $TICKET exec"
    else
      cleanup_staging
      echo "RECORDING: start failed — report an honest failed repro (never fall back to unrecorded browsing)" >&2
      exit 1
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
