#!/bin/bash
# verify-triage.sh <TICKET-ID> — invariant 15 as a rail.
#
# Three mechanical passes over triage/triage.yaml (engine: triage-tools.py):
#   schema      — required keys, enum values, blocker structure
#   disposition — DERIVED from the six checks and compared to the written one;
#                 on mismatch fix the checks, never hand-edit the verdict
#   quotes      — evidence entries are typed; every `kind: quote` must appear
#                 verbatim in its named source inside triage/ticket.json
#                 (human content only — marker comments are pipeline output)
# Exit 0 clean, 1 violations, 2 missing inputs. RECON_ROOT overrides the
# workspace root (default ~/.claude/recon) — used by fixture-based tests.
set -euo pipefail

TICKET="${1:?usage: verify-triage.sh <TICKET-ID>}"
case "$TICKET" in
  *[!A-Za-z0-9-]* | "") echo "invalid ticket id: $TICKET" >&2; exit 2 ;;
esac
DIR="${RECON_ROOT:-$HOME/.claude/recon}/$TICKET"
[ -d "$DIR" ] || { echo "no workspace: $DIR" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required (ships with macOS CLT)" >&2; exit 2; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec python3 "$SCRIPT_DIR/triage-tools.py" verify "$DIR"
