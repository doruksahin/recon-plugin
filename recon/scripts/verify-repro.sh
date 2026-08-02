#!/bin/bash
# verify-repro.sh <TICKET-ID> — structural and coarse current-run provenance
# verification for repro/repro.md, its PNG exhibits, and the recorded session
# bundle (repro/session/: schema-exact session-log.json, exhibits paired to
# logged screenshot actions in step order, a real session.webm — required for
# reproduced: true). Visual truth remains a human/model judgment after this
# rail passes. Exit 0 clean, 1 violation, 2 missing inputs or broken install.
set -euo pipefail

[ "$#" -eq 1 ] || { echo "usage: verify-repro.sh <TICKET-ID>" >&2; exit 2; }
TICKET="$1"
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
command -v python3 >/dev/null 2>&1 || { echo "python3 required (ships with macOS CLT)" >&2; exit 2; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec python3 "$SCRIPT_DIR/artifact-tools.py" verify-repro "$DIR" "$TICKET"
