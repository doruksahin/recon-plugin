#!/bin/bash
# verify-comment-shape.sh <TICKET-ID> — invariant 13 as a rail.
# triage/jira/comment.txt has one deterministic shape per disposition:
# BLOCKED/NEEDS_INFO are n+4 progressive-disclosure lines; READY is a six-line
# approved-Discovery delivery index. Exit 0 clean, 1 shape violation, 2 missing
# inputs.
set -euo pipefail

TICKET="${1:?usage: verify-comment-shape.sh <TICKET-ID>}"
case "$TICKET" in
  *[!A-Za-z0-9-]* | "") echo "invalid ticket id: $TICKET" >&2; exit 2 ;;
esac
RECON_ROOT="${RECON_ROOT:-$HOME/.claude/recon}"
DIR="$RECON_ROOT/$TICKET"
C="$DIR/triage/jira/comment.txt"
Y="$DIR/triage/triage.yaml"
[ -f "$C" ] || { echo "no comment draft: $C" >&2; exit 2; }
[ -f "$Y" ] || { echo "no triage.yaml: $Y" >&2; exit 2; }

n=$(grep -c '^  - title:' "$Y" || true)
lines=$(grep -c . "$C" || true)
fail=0

disposition=$(sed -n 's/^disposition: *//p' "$Y" | head -1)
fail=0

if grep -q $'\r' "$C"; then
  echo "SHAPE: comment contains CRLF line endings — use LF only"; fail=1
fi

if [ "$disposition" = "READY" ]; then
  [ "$n" -eq 0 ] || { echo "SHAPE: READY delivery requires zero blockers"; fail=1; }
  [ "$lines" -eq 6 ] || { echo "SHAPE: $lines non-empty lines, want 6 for READY delivery"; fail=1; }
  grep -q '^h2\. Recon discovery: READY — ' "$C" || { echo "SHAPE: READY header is missing"; fail=1; }
  grep -q '^\*Outcome:\* ' "$C" || { echo "SHAPE: READY outcome line is missing"; fail=1; }
  grep -q '^\*Approval:\* Discovery package approved; [0-9][0-9]* open decision(s) recorded\.$' "$C" || { echo "SHAPE: READY approval line is missing"; fail=1; }
  grep -q '^\*Route:\* .*(rule .*)\.$' "$C" || { echo "SHAPE: READY route line is missing"; fail=1; }
  grep -q '^[^*].*\[\^recon-dossier-.*\.html\] · \[\^recon-artifacts-.*\.zip\]$' "$C" || { echo "SHAPE: READY attachment-links line is missing"; fail=1; }
  [ "$(grep . "$C" | tail -1 | cut -c1-15)" = "~recon-triage v" ] || { echo "SHAPE: marker line must be the last non-empty line (~recon-triage v…)"; fail=1; }
  if [ "$fail" -eq 0 ]; then
    echo "shape: clean — $lines lines, READY delivery"
  else
    exit 1
  fi
  exit 0
fi

[ "$disposition" = "BLOCKED" ] || [ "$disposition" = "NEEDS_INFO" ] || { echo "SHAPE: unsupported disposition '$disposition'"; exit 1; }
[ "$n" -ge 1 ] || { echo "SHAPE: posting path requires >=1 structured blocker in triage.yaml (nothing to ask ⇒ re-check disposition, do not post)"; fail=1; }
want=$((n + 4))

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
