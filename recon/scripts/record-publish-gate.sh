#!/bin/bash
# record-publish-gate.sh <TICKET-ID> question
# record-publish-gate.sh <TICKET-ID> answer <published|declined> <verbatim>
#
# The state-canvas publish gate's rail (ADR 0003). It OWNS the question and the
# record: `question` prints the exact bytes recon-state presents, `answer`
# appends one exchange to state/publish-gate.yaml — the date, the question as
# this rail renders it, the options, the user's exact words, and the outcome
# they were mapped to. Because the question is a fixed string there is no
# separate rendered-questions artifact: the model supplies only the answer.
#
# Without the record, an absent state/artifact-url means three different
# things at once (never asked · asked and declined · host cannot publish).
# With it, recon-state can tell them apart. Only hosts with publish_stable_url
# reach this rail; a render-only host never asks and never writes the file.
# Exit 0 printed/recorded, 2 invalid or missing input.
# RECON_ROOT overrides the workspace root (fixture tests).
set -euo pipefail

TICKET="${1:?usage: record-publish-gate.sh <TICKET-ID> question | answer <published|declined> <verbatim>}"
CMD="${2:?usage: record-publish-gate.sh <TICKET-ID> question | answer <published|declined> <verbatim>}"
case "$TICKET" in
  *[!A-Za-z0-9-]* | "") echo "invalid ticket id: $TICKET" >&2; exit 2 ;;
esac

OPTIONS="Publish / Not now"
question() {
  printf 'Publish a private state canvas for %s? (creates its stable URL)\n' "$TICKET"
  printf 'Options: %s\n' "$OPTIONS"
}

if [ "$CMD" = "question" ]; then
  question
  exit 0
fi
[ "$CMD" = "answer" ] || { echo "unknown command: $CMD (want question|answer)" >&2; exit 2; }

OUTCOME="${3:-}"
VERBATIM="${4:-}"
case "$OUTCOME" in
  published | declined) ;;
  *) echo "invalid outcome: '${OUTCOME:-missing}' (want published|declined)" >&2; exit 2 ;;
esac
[ -n "$(printf '%s' "$VERBATIM" | tr -d '[:space:]')" ] || {
  echo "answer needs the user's exact words — nothing recorded" >&2; exit 2; }
case "$VERBATIM" in
  *'"'*) echo "answer must not contain a double quote (the record is a flat scalar)" >&2; exit 2 ;;
esac

DIR="${RECON_ROOT:-$HOME/.claude/recon}/$TICKET"
[ -d "$DIR" ] || { echo "no workspace: $DIR" >&2; exit 2; }
RECORD="$DIR/state/publish-gate.yaml"
mkdir -p "$DIR/state"

# Append-only: a ticket asked again after a decline keeps both answers.
if [ ! -f "$RECORD" ]; then
  printf 'publish_gate:\n  exchanges:\n' > "$RECORD"
fi
{
  printf -- '    - date: %s\n' "$(date -u +%Y-%m-%d)"
  printf '      question: "%s"\n' "$(question | head -1)"
  printf '      options: "%s"\n' "$OPTIONS"
  printf '      answer_verbatim: "%s"\n' "$VERBATIM"
  printf '      outcome: %s\n' "$OUTCOME"
} >> "$RECORD"

echo "recorded: $OUTCOME -> state/publish-gate.yaml"
