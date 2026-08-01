#!/bin/bash
# verify-comment-shape.sh <TICKET-ID> — invariant 13 as a rail.
# triage/jira/comment.txt must be exactly n+4 non-empty lines for n blockers
# in triage/triage.yaml: header, n one-line blockers ("*i. Title* — [~user]:
# … ?"), attachment-links line, reply-here line, marker line. Exit 0 clean,
# 1 shape violation, 2 missing inputs.
set -euo pipefail

TICKET="${1:?usage: verify-comment-shape.sh <TICKET-ID>}"
case "$TICKET" in
  *[!A-Za-z0-9-]* | "") echo "invalid ticket id: $TICKET" >&2; exit 2 ;;
esac
DIR="$HOME/.claude/recon/$TICKET"
C="$DIR/triage/jira/comment.txt"
Y="$DIR/triage/triage.yaml"
[ -f "$C" ] || { echo "no comment draft: $C" >&2; exit 2; }
[ -f "$Y" ] || { echo "no triage.yaml: $Y" >&2; exit 2; }

n=$(grep -c '^  - title:' "$Y" || true)
lines=$(grep -c . "$C" || true)
want=$((n + 4))
fail=0

[ "$n" -ge 1 ] || { echo "SHAPE: posting path requires >=1 structured blocker in triage.yaml"; fail=1; }

if grep -q $'\r' "$C"; then
  echo "SHAPE: comment contains CRLF line endings — use LF only"; fail=1
fi

[ "$lines" -eq "$want" ] || { echo "SHAPE: $lines non-empty lines, want $want (n=$n blockers + 4)"; fail=1; }

blocker_lines=$(grep -c '^\*[0-9][0-9]*\. ' "$C" || true)
[ "$blocker_lines" -eq "$n" ] || { echo "SHAPE: $blocker_lines blocker lines, want $n"; fail=1; }

if [ "$n" -gt 0 ]; then
  nums=$(grep -o '^\*[0-9][0-9]*\.' "$C" | tr -d '*.' || true)
  [ "$nums" = "$(seq 1 "$n")" ] || { echo "SHAPE: blocker numbering must be 1..n in order"; fail=1; }
fi

while IFS= read -r l; do
  case "$l" in
    *'?') ;;
    *) echo "SHAPE: blocker line does not end in a question: ${l%% —*}"; fail=1 ;;
  esac
  case "$l" in
    *'[~'*) ;;
    *) echo "SHAPE: blocker line has no [~mention]: ${l%% —*}"; fail=1 ;;
  esac
done < <(grep '^\*[0-9][0-9]*\. ' "$C" || true)

grep -q '^[^*].*\[\^recon-' "$C" || { echo "SHAPE: missing attachment-links line ([^recon-…])"; fail=1; }
[ "$(grep . "$C" | tail -1 | cut -c1-15)" = "~recon-triage v" ] || { echo "SHAPE: marker line must be the last non-empty line (~recon-triage v…)"; fail=1; }

if [ "$fail" -eq 0 ]; then
  echo "shape: clean — $lines lines, $n blocker(s)"
else
  exit 1
fi
