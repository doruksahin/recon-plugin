#!/bin/bash
# fresh-workspace.sh <TICKET-ID> — recon step 0: deterministic clean workspace.
#
# Archives every prior artifact in ~/.claude/recon/<TICKET>/ into runs/<timestamp>/
# (dotfiles included), then stamps the new run with meta.yaml. The archive check is
# find-based on purpose: `ls`/`grep` may be aliased or wrapped by a user's shell,
# which makes their exit codes unreliable. The plugin version is read from the
# plugin.json that ships next to this script, so it is correct both in the
# marketplace clone and in any versioned cache copy.
set -euo pipefail

TICKET="${1:?usage: fresh-workspace.sh <TICKET-ID>}"
case "$TICKET" in
  *[!A-Za-z0-9-]* | "") echo "invalid ticket id: $TICKET" >&2; exit 2 ;;
esac

DIR="$HOME/.claude/recon/$TICKET"
mkdir -p "$DIR"

archived="nothing (fresh workspace)"
if [ -n "$(find "$DIR" -maxdepth 1 -mindepth 1 ! -name runs -print -quit)" ]; then
  TS="$(date +%Y%m%d-%H%M%S)"
  while [ -e "$DIR/runs/$TS" ]; do TS="${TS}x"; done
  mkdir -p "$DIR/runs/$TS"
  find "$DIR" -maxdepth 1 -mindepth 1 ! -name runs -exec mv {} "$DIR/runs/$TS/" \;
  count="$(find "$DIR/runs/$TS" -maxdepth 1 -mindepth 1 | wc -l | tr -d ' ')"
  archived="$count entries -> runs/$TS/"
fi

SELF="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_JSON="$SELF/../../../.claude-plugin/plugin.json"
V="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$PLUGIN_JSON" 2>/dev/null | head -1)"

printf 'skill: recon-triage\nplugin_version: %s\nstarted: %s\nticket: %s\n' \
  "${V:-unknown}" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$TICKET" > "$DIR/meta.yaml"

echo "workspace: $DIR"
echo "archived: $archived"
echo "stamped: meta.yaml (plugin_version: ${V:-unknown})"
