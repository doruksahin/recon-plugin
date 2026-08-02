#!/bin/bash
# verify-discovery.sh <TICKET-ID> <pre-gate|post-gate> — verifies the
# scenario → route → brief → approval chain before a package is presented or a
# handoff is printed. Exit 0 clean, 1 violation, 2 missing inputs/broken install.
set -euo pipefail

[ "$#" -eq 2 ] || { echo "usage: verify-discovery.sh <TICKET-ID> <pre-gate|post-gate>" >&2; exit 2; }
TICKET="$1"
MODE="$2"
case "$TICKET" in
  *[!A-Za-z0-9-]* | "") echo "invalid ticket id: $TICKET" >&2; exit 2 ;;
esac
case "$MODE" in
  pre-gate | post-gate) ;;
  *) echo "invalid mode: $MODE (expected pre-gate|post-gate)" >&2; exit 2 ;;
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
exec python3 "$SCRIPT_DIR/artifact-tools.py" verify-discovery "$DIR" "$TICKET" "$MODE"
