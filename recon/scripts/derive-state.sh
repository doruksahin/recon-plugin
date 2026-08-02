#!/bin/bash
# derive-state.sh <TICKET-ID> — the state-canvas derivation rail (zero model
# freedom). Walks a CLOSED decision table over artifact presence (the registry
# files ARE the state machine) plus two fields (triage disposition, gate
# approved) and writes flat, sed-parseable state/state.yaml: one stop label,
# one status per canvas node, fact.* counts, and a fixed next-action sentence.
# A presence combination the table does not recognize is a CONTRADICTION and
# exits 1 naming the files — never guessed around.
# Exit 0 derived, 1 contradiction, 2 no run / missing inputs.
# RECON_ROOT overrides the workspace root (fixture tests).
set -euo pipefail

TICKET="${1:?usage: derive-state.sh <TICKET-ID>}"
case "$TICKET" in
  *[!A-Za-z0-9-]* | "") echo "invalid ticket id: $TICKET" >&2; exit 2 ;;
esac

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TRIAGE_INVOCATION="$(bash "$SCRIPT_DIR/reconctl.sh" invocation recon.triage "$TICKET")"
DIR="${RECON_ROOT:-$HOME/.claude/recon}/$TICKET"
META="$DIR/meta.yaml"
[ -f "$META" ] || { echo "no run: $META missing — $TRIAGE_INVOCATION first" >&2; exit 2; }

TRIAGE="$DIR/triage/triage.yaml"
DISC="$DIR/discovery/discovery.md"
ROUT="$DIR/route/routing.yaml"
BRIEF="$DIR/discovery/spec-draft.md"
GATE="$DIR/discovery/gate.yaml"
POST="$DIR/triage/jira/post-result.json"
REPRO="$DIR/repro/repro.md"
DOSS="$DIR/report/dossier.html"

# node defaults; the table below overrides
n_workspace=done n_triage=queued n_blocked=queued n_contract=queued
n_repro=absent n_routing=queued n_brief=queued n_gate=queued
n_handoff=queued n_implement=queued n_dossier=absent
stop="" next="" next_action="" DISP=""

if [ ! -f "$TRIAGE" ]; then
  stop=triage-in-progress; n_triage=current
  next_action=recon.triage
  next="triage is mid-run — finish Recon Triage for $TICKET (six checks, derived verdict)"
else
  n_triage=done
  DISP="$(sed -n 's/^disposition: *//p' "$TRIAGE" | head -1)"
  case "$DISP" in
    READY)
      n_blocked=not-taken
      if [ -f "$ROUT" ] && [ ! -f "$DISC" ]; then
        echo "contradiction: route/routing.yaml exists but discovery/discovery.md does not" >&2; exit 1
      fi
      if [ -f "$GATE" ] && [ ! -f "$BRIEF" ]; then
        echo "contradiction: discovery/gate.yaml exists but discovery/spec-draft.md does not" >&2; exit 1
      fi
      if [ ! -f "$DISC" ]; then
        stop=discovery-in-progress; n_contract=current
        next_action=recon.discovery
        next="discovery is mid-run — the behavior contract (discovery.md) is being written"
      elif [ ! -f "$ROUT" ]; then
        stop=discovery-in-progress; n_contract=done; n_routing=current
        next_action=recon.discovery
        next="discovery is mid-run — the routing stage has not produced route/routing.yaml yet"
      elif [ ! -f "$BRIEF" ]; then
        stop=discovery-in-progress; n_contract=done; n_routing=done; n_brief=current
        next_action=recon.discovery
        next="discovery is mid-run — the implementer brief (spec-draft.md) is being drafted"
      elif [ ! -f "$GATE" ]; then
        stop=approval-gate; n_contract=done; n_routing=done; n_brief=done; n_gate=current
        next_action=human.approval
        next="answer the approval gate — resolve any OPEN scenario and Approve/Edit/Reject; the answer writes discovery/gate.yaml (re-present with Recon Discovery for $TICKET)"
      else
        APPROVED="$(sed -n 's/^ *approved: *//p' "$GATE" | head -1)"
        n_contract=done; n_routing=done; n_brief=done; n_gate=done
        case "$APPROVED" in
          true)
            stop=handed-off; n_handoff=done; n_implement=current
            next_action=implementation.start
            next="recon is done — implement in a NEW session via the handoff printed verbatim from route/routing.yaml"
            ;;
          false)
            stop=rejected; n_handoff=not-taken; n_implement=not-taken
            next_action=recon.discovery
            next="gate rejected — fix what gate.yaml names, then run Recon Discovery for $TICKET again"
            ;;
          *)
            echo "contradiction: discovery/gate.yaml has no parseable 'approved:' line" >&2; exit 1
            ;;
        esac
      fi
      ;;
    BLOCKED|NEEDS_INFO)
      n_contract=not-taken; n_routing=not-taken; n_brief=not-taken
      n_gate=not-taken; n_handoff=not-taken; n_implement=not-taken
      if [ ! -f "$POST" ]; then
        stop=comment-gate; n_blocked=current
        next_action=human.approval
        next="approve the Jira comment + attachments gate in the triage session (nothing posts without it)"
      else
        stop=awaiting-replies; n_blocked=done
        next_action=recon.triage
        next="paused — answers on the ticket un-block it; then run Recon Triage for $TICKET again"
      fi
      ;;
    *)
      echo "contradiction: triage/triage.yaml disposition is '$DISP' (expected READY|BLOCKED|NEEDS_INFO)" >&2; exit 1
      ;;
  esac
fi
[ -f "$REPRO" ] && n_repro=done
[ -f "$DOSS" ] && n_dossier=done

# facts — mechanical counts and field reads (0 / empty when the file is absent)
count() { if [ -f "$1" ]; then grep -cE "$2" "$1" || true; else echo 0; fi; }
BLOCKERS="$(count "$TRIAGE" '^  - title:')"
CONFLICTS="$(count "$TRIAGE" '^  - ticket:')"
SCEN="$(count "$DISC" '^[[:space:]#>*-]*Scenario')"
OPEN="$(count "$DISC" '^#+ *OPEN-')"
EXHIBITS="$({ find "$DIR/repro/exhibits" -name '*.png' 2>/dev/null || true; } | wc -l | tr -d ' ')"
# optional files: sed on a missing path must not kill the run (set -o pipefail)
field() { { sed -n "s/^$2: *//p" "$1" 2>/dev/null || true; } | head -1; }
TITLE="$(field "$TRIAGE" title | sed 's/^"//; s/"$//')"
TASK_CLASS="$(field "$TRIAGE" task_class)"
ROUTE="$(field "$ROUT" '  route')"
RULE="$(field "$ROUT" '  matched_rule')"
GOV="$(field "$ROUT" '  governance')"
STARTED="$(sed -n 's/^started: *//p' "$META" | head -1)"
V="$(sed -n 's/^plugin_version: *//p' "$META" | head -1)"

mkdir -p "$DIR/state"
{
  printf 'recon: state\n'
  printf 'ticket: %s\n' "$TICKET"
  printf 'derived: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'run_started: %s\n' "$STARTED"
  printf 'run_version: %s\n' "$V"
  printf 'stop: %s\n' "$stop"
  printf 'next_action: %s\n' "$next_action"
  printf 'next: "%s"\n' "$next"
  printf 'node.workspace: %s\n' "$n_workspace"
  printf 'node.triage: %s\n' "$n_triage"
  printf 'node.blocked_path: %s\n' "$n_blocked"
  printf 'node.contract: %s\n' "$n_contract"
  printf 'node.repro: %s\n' "$n_repro"
  printf 'node.routing: %s\n' "$n_routing"
  printf 'node.brief: %s\n' "$n_brief"
  printf 'node.approval_gate: %s\n' "$n_gate"
  printf 'node.handoff: %s\n' "$n_handoff"
  printf 'node.implement: %s\n' "$n_implement"
  printf 'node.dossier: %s\n' "$n_dossier"
  printf 'fact.title: "%s"\n' "$TITLE"
  printf 'fact.disposition: %s\n' "${DISP:-pending}"
  printf 'fact.task_class: %s\n' "${TASK_CLASS:-unknown}"
  printf 'fact.route: %s\n' "${ROUTE:-pending}"
  printf 'fact.rule: "%s"\n' "${RULE:-—}"
  printf 'fact.governance: %s\n' "${GOV:-pending}"
  printf 'fact.blockers: %s\n' "$BLOCKERS"
  printf 'fact.conflicts: %s\n' "$CONFLICTS"
  printf 'fact.scenarios: %s\n' "$SCEN"
  printf 'fact.open: %s\n' "$OPEN"
  printf 'fact.exhibits: %s\n' "$EXHIBITS"
} > "$DIR/state/state.yaml"

echo "state: $stop (disposition: ${DISP:-pending}, route: ${ROUTE:-pending})"
echo "wrote: $DIR/state/state.yaml"
