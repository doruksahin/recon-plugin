#!/bin/bash
# set-governance.sh — the governance exchange rail: it OWNS the one-time
# handoff-style question and the record of how it was answered (ADR 0003).
#
#   set-governance.sh question <tool>
#       Print the exact question and options. recon-discovery presents these
#       bytes word-for-word — the question lives here, not in a SKILL.md, so
#       there is nothing to paraphrase and only one owner of the wording.
#   set-governance.sh answer <none|decree|auto> <tool> <verbatim answer>
#       Persist the developer's standing choice to ~/.config/recon/config AND
#       append the exchange to ~/.config/recon/governance-exchanges.ndjson:
#       the date, the tool, this rail's own re-render of the question, the
#       developer's exact words, and the value they were mapped to. Both
#       writes or neither — a missing verbatim answer exits 2 and persists
#       nothing (invariant 18: the answer to a gate is never lost).
#   set-governance.sh <none|decree|auto>
#       A developer changing their standing choice from a shell. Not a gate,
#       so it records source: manual with no answer text.
#
# The record lives beside the config it explains because the choice is
# cross-ticket and standing; a per-workspace copy would die at step 0 and
# reappear, wrongly dated, in every later ticket. It is OUTPUT: no check,
# verdict, or route reads it.
# Exit 0 persisted/printed, 2 invalid or missing input.
set -euo pipefail

CONFIG_DIR="$HOME/.config/recon"
CONFIG="$CONFIG_DIR/config"
EXCHANGES="$CONFIG_DIR/governance-exchanges.ndjson"

USAGE="usage: set-governance.sh question <tool>
       set-governance.sh answer <none|decree|auto> <tool> <verbatim answer>
       set-governance.sh <none|decree|auto>"

valid_value() {
  case "$1" in
    none | decree | auto) return 0 ;;
    *) return 1 ;;
  esac
}

render_question() {
  local tool="$1"
  printf 'This repo has %s set up. When a ticket is approved, how should recon hand off the work?\n' "$tool"
  printf -- '- Write %s docs (Recommended) — approved tickets route into this repo'"'"'s %s flow (the handoff prints its commands)\n' "$tool" "$tool"
  printf -- '- Plain briefs — approved tickets end at a standalone implementation brief; %s is never involved and its vocabulary never appears\n' "$tool"
  printf -- '- Follow each repo — %s docs wherever a repo has it set up, plain briefs everywhere else\n' "$tool"
}

persist() {
  mkdir -p "$CONFIG_DIR"
  printf 'governance=%s\n' "$1" > "$CONFIG"
}

# One JSON line per persisted answer; the file is append-only so a changed
# standing choice keeps the record of the choice it replaced.
append_exchange() {
  local value="$1" source="$2" tool="$3" question="$4" verbatim="$5"
  command -v python3 >/dev/null 2>&1 || { echo "python3 required (ships with macOS CLT)" >&2; exit 2; }
  mkdir -p "$CONFIG_DIR"
  DATE="$(date -u +%Y-%m-%d)" VALUE="$value" SOURCE="$source" TOOL="$tool" \
    QUESTION="$question" VERBATIM="$verbatim" python3 - <<'PY' >> "$EXCHANGES"
import json, os

row = {"date": os.environ["DATE"], "value": os.environ["VALUE"],
       "source": os.environ["SOURCE"]}
for key, name in (("TOOL", "tool"), ("QUESTION", "question"),
                  ("VERBATIM", "answer_verbatim")):
    if os.environ[key]:
        row[name] = os.environ[key]
print(json.dumps(row, separators=(",", ":")))
PY
}

CMD="${1:?$USAGE}"

case "$CMD" in
  question)
    TOOL="${2:?usage: set-governance.sh question <tool>}"
    render_question "$TOOL"
    exit 0
    ;;
  answer)
    V="${2:-}"; TOOL="${3:-}"; VERBATIM="${4:-}"
    valid_value "$V" || { echo "invalid governance value: '$V' (want none|decree|auto)" >&2; exit 2; }
    [ -n "$TOOL" ] || { echo "answer needs the tool the question named" >&2; exit 2; }
    [ -n "$(printf '%s' "$VERBATIM" | tr -d '[:space:]')" ] || {
      echo "answer needs the developer's exact words — nothing persisted" >&2; exit 2; }
    append_exchange "$V" gate "$TOOL" "$(render_question "$TOOL")" "$VERBATIM"
    persist "$V"
    echo "persisted: governance=$V -> $CONFIG"
    echo "recorded: the handoff-style exchange -> $EXCHANGES"
    ;;
  *)
    V="$CMD"
    valid_value "$V" || { echo "invalid governance value: '$V' (want none|decree|auto)" >&2; exit 2; }
    append_exchange "$V" manual "" "" ""
    persist "$V"
    echo "persisted: governance=$V -> $CONFIG"
    echo "recorded: a manual change (no gate exchange) -> $EXCHANGES"
    ;;
esac
