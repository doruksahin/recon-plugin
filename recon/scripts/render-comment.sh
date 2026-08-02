#!/bin/bash
# render-comment.sh <TICKET-ID> — invariant 13 as a rail, now including the
# rendering itself: triage/jira/comment.txt is EMITTED from triage.yaml +
# meta.yaml (and, for approved READY delivery, discovery/gate.yaml +
# route/routing.yaml) by triage-tools.py — the model never writes the comment,
# so transcription drift between the verified artifacts and posted bytes is
# impossible.
# Header date comes from meta.yaml `started`, the marker version from
# `plugin_version`, mentions from each blocker's resolved `owner_account_id`.
#
# Run verify-triage.sh first (this script re-checks only what rendering needs);
# verify-comment-shape.sh afterwards stays as the independent shape check.
# Exit 0 rendered, 1 unrenderable yaml, 2 missing inputs. RECON_ROOT overrides
# the workspace root (default ~/.claude/recon) — used by fixture-based tests.
set -euo pipefail

TICKET="${1:?usage: render-comment.sh <TICKET-ID>}"
case "$TICKET" in
  *[!A-Za-z0-9-]* | "") echo "invalid ticket id: $TICKET" >&2; exit 2 ;;
esac
DIR="${RECON_ROOT:-$HOME/.claude/recon}/$TICKET"
[ -d "$DIR" ] || { echo "no workspace: $DIR" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required (ships with macOS CLT)" >&2; exit 2; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec python3 "$SCRIPT_DIR/triage-tools.py" render "$DIR" "$TICKET"
