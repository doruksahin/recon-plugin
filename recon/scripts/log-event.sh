#!/bin/bash
# log-event.sh <TICKET-ID> <event> [key=value ...] — the ticket-ledger rail.
#
# Appends exactly one JSON line to ~/.claude/recon/<TICKET>/history.ndjson:
#   {"ts":"<utc now>","run":"<meta started>","v":"<meta plugin_version>",
#    "event":"<event>", "<key>":"<value>", ...}
# The event vocabulary is CLOSED (print it with --vocab; lint-workspace.sh
# reads it from here — this script is the vocabulary's only owner). The ledger
# is OUTPUT, NEVER EVIDENCE: no check, verdict, or routing may read it; it
# survives fresh-workspace.sh across runs so views can tell the ticket's story.
# Exit 0 appended, 1 unknown event / malformed pair, 2 missing inputs.
# RECON_ROOT overrides the workspace root (fixture tests).
set -euo pipefail

VOCAB="run_started verdict routed comment_posted attachments_replaced gate_answered handoff_printed dossier_published canvas_published"

if [ "${1:-}" = "--vocab" ]; then
  echo "$VOCAB"
  exit 0
fi

TICKET="${1:?usage: log-event.sh <TICKET-ID> <event> [key=value ...] | --vocab}"
EVENT="${2:?usage: log-event.sh <TICKET-ID> <event> [key=value ...] | --vocab}"
shift 2
case "$TICKET" in
  *[!A-Za-z0-9-]* | "") echo "invalid ticket id: $TICKET" >&2; exit 2 ;;
esac

known=0
for e in $VOCAB; do [ "$e" = "$EVENT" ] && known=1; done
if [ "$known" -eq 0 ]; then
  echo "log-event: unknown event '$EVENT' — allowed: $VOCAB" >&2
  exit 1
fi

for pair in "$@"; do
  case "$pair" in
    [A-Za-z_]*=*) : ;;
    *) echo "log-event: malformed pair '$pair' — expected key=value" >&2; exit 1 ;;
  esac
done

DIR="${RECON_ROOT:-$HOME/.claude/recon}/$TICKET"
META="$DIR/meta.yaml"
[ -f "$META" ] || { echo "no meta.yaml in $DIR — run fresh-workspace.sh first" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required (ships with macOS CLT)" >&2; exit 2; }

RUN="$(sed -n 's/^started: *//p' "$META" | head -1)"
V="$(sed -n 's/^plugin_version: *//p' "$META" | head -1)"
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

TS="$TS" RUN="$RUN" V="$V" EVENT="$EVENT" python3 - "$@" <<'PY' >> "$DIR/history.ndjson"
import json, os, sys
row = {"ts": os.environ["TS"], "run": os.environ["RUN"], "v": os.environ["V"],
       "event": os.environ["EVENT"]}
for pair in sys.argv[1:]:
    k, _, v = pair.partition("=")
    row[k] = v
print(json.dumps(row, separators=(",", ":")))
PY

echo "ledger: $EVENT appended to $DIR/history.ndjson"
