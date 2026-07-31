#!/bin/bash
# detect-governance.sh — resolve which governance adapter the recon pipeline uses.
# Run from inside the target repo (the probe checks the repo root for decree.toml).
#
# Resolution ladder — most explicit wins; detection alone NEVER opts a developer in:
#   1. RECON_GOVERNANCE=none|decree      (this run only)
#   2. ~/.config/recon/config            governance=none|decree|auto (standing choice)
#   3. probe finds no decree             -> none (silently; nothing to opt into)
#   4. probe finds decree, no choice     -> undecided (the caller must ask ONCE and
#                                           persist the answer via set-governance.sh)
#
# Output (exactly three lines, parse-stable):
#   governance: none|decree|undecided
#   source: env|env-decree-but-unavailable|config|config-decree-but-unavailable|config-auto-probe|probe-absent|probe-detected-no-choice
#   evidence: decree_cli=..., decree_toml=..., config=..., env=...
set -euo pipefail

CONFIG="$HOME/.config/recon/config"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

decree_available() {
  command -v decree >/dev/null 2>&1 && [ -f "$REPO_ROOT/decree.toml" ]
}

GOV=""; SRC=""

if [ -n "${RECON_GOVERNANCE:-}" ]; then
  case "$RECON_GOVERNANCE" in
    none)   GOV=none; SRC=env ;;
    decree) if decree_available; then GOV=decree; SRC=env; else GOV=none; SRC=env-decree-but-unavailable; fi ;;
    *) echo "invalid RECON_GOVERNANCE: '$RECON_GOVERNANCE' (want none|decree)" >&2; exit 2 ;;
  esac
elif [ -f "$CONFIG" ]; then
  V="$(sed -n 's/^governance=\(.*\)$/\1/p' "$CONFIG" | head -1)"
  case "$V" in
    none)   GOV=none; SRC=config ;;
    decree) if decree_available; then GOV=decree; SRC=config; else GOV=none; SRC=config-decree-but-unavailable; fi ;;
    auto)   if decree_available; then GOV=decree; else GOV=none; fi; SRC=config-auto-probe ;;
    *) echo "invalid governance value in $CONFIG: '$V' (want none|decree|auto)" >&2; exit 2 ;;
  esac
fi

if [ -z "$GOV" ]; then
  if decree_available; then GOV=undecided; SRC=probe-detected-no-choice
  else GOV=none; SRC=probe-absent; fi
fi

echo "governance: $GOV"
echo "source: $SRC"
echo "evidence: decree_cli=$(command -v decree 2>/dev/null || echo absent), decree_toml=$([ -f "$REPO_ROOT/decree.toml" ] && echo present || echo absent), config=$([ -f "$CONFIG" ] && sed -n 's/^governance=.*/&/p' "$CONFIG" | head -1 || echo absent), env=${RECON_GOVERNANCE:-unset}"
