#!/bin/bash
# lint-workspace.sh <TICKET-ID> — recon invariant 10 as a rail.
#
# Compares the current-run workspace tree against the artifact registry
# (recon/docs/pipeline.md). Every file must match a registered pattern;
# anything else is an undeclared artifact — a contract violation. runs/ is
# archived history and is skipped entirely. Exit 0 = clean, 1 = violations,
# 2 = no workspace.
set -euo pipefail

TICKET="${1:?usage: lint-workspace.sh <TICKET-ID>}"
case "$TICKET" in
  *[!A-Za-z0-9-]* | "") echo "invalid ticket id: $TICKET" >&2; exit 2 ;;
esac

DIR="$HOME/.claude/recon/$TICKET"
[ -d "$DIR" ] || { echo "no workspace: $DIR" >&2; exit 2; }

violations=0
checked=0
while IFS= read -r f; do
  rel="${f#"$DIR"/}"
  checked=$((checked + 1))
  case "$rel" in
    meta.yaml | index.md) ;;
    triage/ticket.json | triage/triage.yaml | triage/aux-*.json) ;;
    triage/jira/comment.txt | triage/jira/post-result.json | triage/jira/attach-result.json) ;;
    discovery/discovery.md | discovery/routing.yaml | discovery/spec-draft.md) ;;
    repro/repro.md | repro/exhibits/*.png) ;;
    report/dossier.html) ;;
    *)
      echo "VIOLATION: $rel — not in the artifact registry (recon/docs/pipeline.md)"
      violations=$((violations + 1))
      ;;
  esac
done < <(find "$DIR" -type f ! -path "$DIR/runs/*" | sort)

if [ "$violations" -eq 0 ]; then
  echo "lint: clean — $checked file(s), all registered"
else
  echo "lint: $violations violation(s) out of $checked file(s) — register the artifact or remove it"
  exit 1
fi
