#!/bin/bash
# route-generic.sh <TICKET-ID> <governance-source> — governance-free routing as a
# pure rail (zero model freedom). Run from inside the target repo.
#
# The routing judgment was already made by discovery when it wrote (or could not
# write) Gherkin scenarios; this script just reads that fact:
#   0 scenarios in discovery/discovery.md -> route: direct  (rule G0)
#   >=1 scenario                          -> route: brief   (rule G1)
# Writes route/routing.yaml including the handoff as verbatim data — consumers
# quote it, never compose it.
set -euo pipefail

TICKET="${1:?usage: route-generic.sh <TICKET-ID> <governance-source>}"
SRC="${2:?usage: route-generic.sh <TICKET-ID> <governance-source>}"
case "$TICKET" in
  *[!A-Za-z0-9-]* | "") echo "invalid ticket id: $TICKET" >&2; exit 2 ;;
esac

DIR="$HOME/.claude/recon/$TICKET"
DISC="$DIR/discovery/discovery.md"
[ -f "$DISC" ] || { echo "missing $DISC — run discovery's contract step first" >&2; exit 2; }

N="$(grep -cE '^[[:space:]#>*-]*Scenario' "$DISC" || true)"
REPO_COMMIT="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
mkdir -p "$DIR/route"

if [ "$N" -eq 0 ]; then
  cat > "$DIR/route/routing.yaml" <<EOF
routing:
  route: direct
  matched_rule: G0
  governance: none
  governance_source: $SRC
  brief_kind: none
  evidence:
    scenarios: 0
    repo_commit: "$REPO_COMMIT"
  rules_not_matched:
    G1: "discovery.md contains no scenarios — there is no behavior contract to implement a brief against"
  handoff: |
    → implement directly; reference $TICKET in the commit message
EOF
  ROUTE=direct RULE=G0
else
  cat > "$DIR/route/routing.yaml" <<EOF
routing:
  route: brief
  matched_rule: G1
  governance: none
  governance_source: $SRC
  brief_kind: implementation-brief
  evidence:
    scenarios: $N
    repo_commit: "$REPO_COMMIT"
  rules_not_matched:
    G0: "discovery.md contains $N scenario(s) — a behavior contract exists"
  handoff: |
    → implement in a NEW session from ~/.claude/recon/$TICKET/discovery/spec-draft.md
    → verify against the scenarios in ~/.claude/recon/$TICKET/discovery/discovery.md
EOF
  ROUTE=brief RULE=G1
fi

RECON_ROOT="$HOME/.claude/recon" \
  bash "$(cd "$(dirname "$0")" && pwd)/log-event.sh" "$TICKET" routed "route=$ROUTE" "rule=$RULE" >/dev/null

echo "route: $ROUTE (rule $RULE, $N scenario(s), governance: none/$SRC)"
echo "wrote: $DIR/route/routing.yaml"
