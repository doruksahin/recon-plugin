#!/bin/bash
# set-governance.sh <none|decree|auto> — persist the developer's standing governance
# choice to ~/.config/recon/config. Called by recon-discovery exactly once, after the
# one-time AskUserQuestion that fires when detect-governance.sh returns "undecided".
set -euo pipefail

V="${1:?usage: set-governance.sh <none|decree|auto>}"
case "$V" in
  none|decree|auto) ;;
  *) echo "invalid governance value: '$V' (want none|decree|auto)" >&2; exit 2 ;;
esac

CONFIG_DIR="$HOME/.config/recon"
mkdir -p "$CONFIG_DIR"
printf 'governance=%s\n' "$V" > "$CONFIG_DIR/config"
echo "persisted: governance=$V -> $CONFIG_DIR/config"
