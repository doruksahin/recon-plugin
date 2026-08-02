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
echo "ONE COMMAND"
echo "  /recon:recon-triage <TICKET-ID>   # everything else chains or fires on triggers"
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

# --- Jira credentials: the #1 onboarding cliff. Present, then actually valid.
ENV_FILE="$HOME/.config/jira/env"
if [ ! -f "$ENV_FILE" ]; then
  echo "  jira credentials    ✗ $ENV_FILE missing — create it with:"
  echo "                        JIRA_HOST=<your>.atlassian.net"
  echo "                        JIRA_EMAIL=<you>@<company>"
  echo "                        JIRA_API_TOKEN=<from id.atlassian.com/manage-profile/security/api-tokens>"
else
  # shellcheck disable=SC1090
  set -a; source "$ENV_FILE"; set +a
  HOST="${JIRA_HOST#https://}"; HOST="${HOST%/}"
  CODE="$(curl -sS -o ${TMPDIR:-/tmp}/recon-doctor-myself.$$ -w '%{http_code}' --max-time 8 \
    -u "${JIRA_EMAIL:-}:${JIRA_API_TOKEN:-}" "https://$HOST/rest/api/2/myself" 2>/dev/null || echo 000)"
  case "$CODE" in
    200)
      WHO="$(sed -n 's/.*"displayName": *"\([^"]*\)".*/\1/p' "${TMPDIR:-/tmp}/recon-doctor-myself.$$" | head -1)"
      echo "  jira credentials    ✓ env present; token valid (authenticated as ${WHO:-unknown})" ;;
    401 | 403)
      echo "  jira credentials    ✗ token rejected (HTTP $CODE) — likely expired; regenerate at"
      echo "                        https://id.atlassian.com/manage-profile/security/api-tokens"
      echo "                        then update JIRA_API_TOKEN in $ENV_FILE" ;;
    000)
      echo "  jira credentials    ! could not reach https://$HOST (offline?) — env file present, token unverified" ;;
    *)
      echo "  jira credentials    ! unexpected HTTP $CODE from GET /myself — check JIRA_HOST in $ENV_FILE" ;;
  esac
  rm -f "${TMPDIR:-/tmp}/recon-doctor-myself.$$"
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
echo "  /recon:recon-triage <TICKET-ID>"
echo "  Deeper: recon/docs/pipeline.md (machine spec) · README.md (overview + flow diagram)"
