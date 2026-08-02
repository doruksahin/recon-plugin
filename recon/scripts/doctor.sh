#!/bin/bash
# doctor.sh — recon's orientation + setup check, the engine behind the
# recon-help skill. Prints ONLY live-derived facts so help can never drift:
#   version      read from the plugin.json that ships next to this script
#   skills       generated from each sibling SKILL.md's own frontmatter
#                description (the owner of "when to use")
#   checks       computed now — Jira credentials (env file + GET /myself),
#                handoff style (detect-governance.sh, repo-dependent), and the
#                optional doc tool's evidence line
# Read-only everywhere: no workspace writes, no Jira mutations, no config
# writes. Exit 0 always when the report prints (a failing CHECK is content,
# not an error); 2 when the plugin install itself is broken.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_JSON="$SCRIPT_DIR/../.claude-plugin/plugin.json"
SKILLS_DIR="$SCRIPT_DIR/../skills"
[ -f "$PLUGIN_JSON" ] || { echo "broken install: no $PLUGIN_JSON" >&2; exit 2; }
[ -d "$SKILLS_DIR" ] || { echo "broken install: no $SKILLS_DIR" >&2; exit 2; }

VERSION="$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$PLUGIN_JSON" | head -1)"
echo "recon v$VERSION — pipeline doctor"
echo
if [ -x "$SCRIPT_DIR/reconctl.sh" ]; then
  AGENT_HOST="$(bash "$SCRIPT_DIR/reconctl.sh" detect-host)"
  AGENT_SURFACE="$(bash "$SCRIPT_DIR/reconctl.sh" detect-surface)"
  ENTRYPOINT="$(bash "$SCRIPT_DIR/reconctl.sh" invocation recon.triage ATT-1234)"
  echo "WORKSPACE"
  echo "  root               $(bash "$SCRIPT_DIR/reconctl.sh" root)"
  echo "  override           set RECON_ROOT to an absolute path"
  echo "  host               $AGENT_HOST"
  echo "  surface            $AGENT_SURFACE"
  echo
else
  echo "broken install: no $SCRIPT_DIR/reconctl.sh" >&2
  exit 2
fi
echo "ONE COMMAND"
echo "  $ENTRYPOINT   # everything else chains or fires on triggers"
echo
echo "SKILLS (each line is that skill's own description, first sentence)"
while IFS= read -r skill_md; do
  name="$(basename "$(dirname "$skill_md")")"
  desc="$(sed -n 's/^description: *//p' "$skill_md" | head -1)"
  desc="${desc%%.*}."
  printf '  %-16s %s\n' "$name" "$desc"
done < <(find "$SKILLS_DIR" -mindepth 2 -maxdepth 2 -name SKILL.md | sort)
echo
echo "CHECKS"

# --- Runtime + Jira: one shared preflight rail, no second implementation.
PREFLIGHT="$(bash "$SCRIPT_DIR/reconctl.sh" preflight triage)" || PREFLIGHT_STATUS=$?
printf '%s\n' "$PREFLIGHT" | sed 's/^/  /'
[ "${PREFLIGHT_STATUS:-0}" -eq 0 ] || echo "  fix the failed preflight checks before running Recon Triage"

# --- Repro recorder: derived from the same preflight rail the skill runs.
# (Separate sed expressions: BSD sed has no \| alternation in BRE.)
REPRO_PF="$(bash "$SCRIPT_DIR/reconctl.sh" preflight repro 2>/dev/null)" || true
RECORDER_LINES="$(printf '%s\n' "$REPRO_PF" | sed -n \
  -e 's/^check\.command\.proofshot: //p' \
  -e 's/^check\.command\.agent-browser: //p' \
  -e 's/^check\.proofshot_version: //p')"
if [ -z "$RECORDER_LINES" ]; then
  echo "  repro recorder      ✗ preflight repro produced no recorder checks — run reconctl.sh preflight repro directly"
elif printf '%s\n' "$RECORDER_LINES" | grep -q FAIL; then
  echo "  repro recorder      ✗ $(printf '%s\n' "$RECORDER_LINES" | grep FAIL | head -1 | sed 's/^FAIL — //')"
else
  echo "  repro recorder      ✓ proofshot $(printf '%s\n' "$RECORDER_LINES" | sed -n 's/^PASS — \(.*\) (pinned)$/\1/p') + agent-browser (pinned)"
fi

# --- Handoff style: repo-dependent; reuse the resolution rail verbatim.
GOV_OUT="$("$SCRIPT_DIR/detect-governance.sh" 2>/dev/null)" || GOV_OUT=""
GOV="$(printf '%s\n' "$GOV_OUT" | sed -n 's/^governance: //p')"
SRC="$(printf '%s\n' "$GOV_OUT" | sed -n 's/^source: //p')"
case "$GOV" in
  undecided)
    echo "  handoff style       ! not chosen yet — your first READY ticket asks once, or choose now:"
    echo "                        bash $SCRIPT_DIR/set-governance.sh <none|decree|auto>" ;;
  none)
    echo "  handoff style       ✓ plain briefs ($SRC) — change anytime: set-governance.sh" ;;
  "")
    echo "  handoff style       ! detect-governance.sh failed — run it directly for details" ;;
  *)
    echo "  handoff style       ✓ $GOV docs ($SRC) — change anytime: set-governance.sh" ;;
esac

# --- Optional doc tool: show the rail's own evidence line, no interpretation.
EVIDENCE="$(printf '%s\n' "$GOV_OUT" | sed -n 's/^evidence: //p')"
[ -n "$EVIDENCE" ] && echo "  doc tool (optional) $EVIDENCE (checked in: $(git rev-parse --show-toplevel 2>/dev/null || pwd))"

echo
echo "NEXT"
echo "  $ENTRYPOINT"
echo "  Deeper: recon/docs/pipeline.md (machine spec) · README.md (overview + flow diagram)"
