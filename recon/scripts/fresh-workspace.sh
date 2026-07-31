#!/bin/bash
# fresh-workspace.sh <TICKET-ID> — recon step 0: deterministic clean workspace.
#
# Archives every prior artifact in ~/.claude/recon/<TICKET>/ into runs/<timestamp>/
# (dotfiles included), stamps the new run with meta.yaml, and copies the static
# workspace index (docs/workspace-index.md -> index.md). The archive check is
# find-based on purpose: `ls`/`grep` may be aliased or wrapped by a user's shell,
# which makes their exit codes unreliable. The plugin version is read from the
# plugin.json that ships with this script, so it is correct both in the
# marketplace clone and in any versioned cache copy.
set -euo pipefail

TICKET="${1:?usage: fresh-workspace.sh <TICKET-ID>}"
case "$TICKET" in
  *[!A-Za-z0-9-]* | "") echo "invalid ticket id: $TICKET" >&2; exit 2 ;;
esac

DIR="$HOME/.claude/recon/$TICKET"
mkdir -p "$DIR"

# Once-per-run guard: a triage run invokes this script exactly once. A second
# invocation minutes later is almost certainly the same run re-entering step 0
# — archiving would destroy the run's own in-progress artifacts (observed on
# ATT-5047, 2026-07-31). A genuine new run within the window can force it.
META="$DIR/meta.yaml"
if [ -f "$META" ] && [ "${RECON_STEP0_FORCE:-0}" != "1" ]; then
  NOW="$(date +%s)"
  MT="$(stat -f %m "$META" 2>/dev/null || stat -c %Y "$META" 2>/dev/null || echo 0)"
  AGE=$(( NOW - MT ))
  if [ "$AGE" -lt 1800 ]; then
    echo "workspace: $DIR"
    echo "archived: SKIPPED — step 0 already ran ${AGE}s ago (once-per-run guard); continuing the current run"
    echo "stamped: existing meta.yaml kept ($(sed -n 's/^plugin_version: \(.*\)$/plugin_version: \1/p' "$META"))"
    echo "note: only if this is genuinely a NEW run, re-invoke with RECON_STEP0_FORCE=1"
    exit 0
  fi
fi

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
PLUGIN_JSON="$SELF/../.claude-plugin/plugin.json"
V="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$PLUGIN_JSON" 2>/dev/null | head -1)"

printf 'skill: recon-triage\nplugin_version: %s\nstarted: %s\nticket: %s\n' \
  "${V:-unknown}" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$TICKET" > "$DIR/meta.yaml"

INDEX_SRC="$SELF/../docs/workspace-index.md"
indexed="index.md (copied from plugin docs)"
if [ -f "$INDEX_SRC" ]; then
  cp "$INDEX_SRC" "$DIR/index.md"
else
  indexed="index.md SKIPPED — $INDEX_SRC missing (broken install?)"
fi

echo "workspace: $DIR"
echo "archived: $archived"
echo "stamped: meta.yaml (plugin_version: ${V:-unknown}) + $indexed"
