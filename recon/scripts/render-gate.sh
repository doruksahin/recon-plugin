#!/bin/bash
# render-gate.sh <TICKET-ID> — the in-session analogue of render-comment.sh:
# discovery/gate-questions.md is EMITTED from discovery.md + routing.yaml, so
# the gate presents rail-rendered bytes, never a model paraphrase (ADR 0002).
# One block per OPEN-N (scenario, options, exactly one "(recommended)") plus
# the PACKAGE block. Run after verify-discovery.sh pre-gate is clean; re-run
# after every Edit-loop change to discovery.md before re-presenting.
# Exit 0 rendered, 1 unrenderable contract, 2 missing inputs. RECON_ROOT
# overrides the workspace root (default ~/.claude/recon) — used by fixtures.
set -euo pipefail

TICKET="${1:?usage: render-gate.sh <TICKET-ID>}"
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
exec python3 "$SCRIPT_DIR/artifact-tools.py" render-gate "$DIR" "$TICKET"
