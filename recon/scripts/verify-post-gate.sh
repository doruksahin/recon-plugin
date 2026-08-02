#!/bin/bash
# verify-post-gate.sh <TICKET-ID> — invariant 18 for the posting gate (ADR
# 0003), the delivery-path analogue of verify-discovery.sh post-gate.
# Proves that triage/jira/post-gate-questions.txt carried comment.txt verbatim,
# that triage/jira/post-gate.yaml records one well-formed exchange per
# presentation (non-empty verbatim answer, known outcome, terminal answer
# last), and that the terminal outcome agrees with the delivery artifacts on
# disk. Run after the answered outcome has been carried out, before reporting.
# Exit 0 clean, 1 violation, 2 missing inputs.
set -euo pipefail

TICKET="${1:?usage: verify-post-gate.sh <TICKET-ID>}"
case "$TICKET" in
  *[!A-Za-z0-9-]* | "") echo "invalid ticket id: $TICKET" >&2; exit 2 ;;
esac
RECON_ROOT="${RECON_ROOT:-$HOME/.claude/recon}"
DIR="$RECON_ROOT/$TICKET"
[ -d "$DIR" ] || { echo "no workspace: $DIR" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required (ships with macOS CLT)" >&2; exit 2; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec python3 "$SCRIPT_DIR/triage-tools.py" verify-post-gate "$DIR"
