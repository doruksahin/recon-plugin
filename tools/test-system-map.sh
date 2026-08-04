#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAP="$ROOT/docs/system-map.html"
python3 "$ROOT/tools/render-system-map.py" >/dev/null
python3 "$ROOT/tools/render-system-map.py" --check >/dev/null
STATE_JSON="$(python3 "$ROOT/tools/improvement-cycle.py" state \
  "$ROOT/docs/improvement-proposals/0.22.0/requirement-closure-coverage" --json)"
CURRENT_STATE="$(python3 -c 'import json, sys; print(json.load(sys.stdin)["state"])' <<<"$STATE_JSON")"
NEXT_ACTION="$(python3 -c 'import json, sys; print(json.load(sys.stdin)["next_action"])' <<<"$STATE_JSON")"
for text in 'Shipped plugin' 'Private version review' 'Replay laboratory' 'Improvement loop' 'COLLECTING' 'SYNTHESIZED' 'ATT-4845' 'RCTRL-1' 'Reference ledger' 'evals/version-reviews/schema.yaml' 'tools/version-review.py'; do
  rg -q "$text" "$MAP" || { echo "missing map content: $text" >&2; exit 1; }
done
rg -Fq "Now: $CURRENT_STATE" "$MAP" || { echo "missing current map state: $CURRENT_STATE" >&2; exit 1; }
rg -Fq "$NEXT_ACTION" "$MAP" || { echo "missing current next action: $NEXT_ACTION" >&2; exit 1; }
if rg -q 'oracle/|decisions.json' "$MAP"; then echo 'map leaked oracle path' >&2; exit 1; fi
cp "$MAP" "$MAP.test-backup"
printf 'drift' >> "$MAP"
if python3 "$ROOT/tools/render-system-map.py" --check >/dev/null 2>&1; then echo 'expected drift failure' >&2; exit 1; fi
mv "$MAP.test-backup" "$MAP"
python3 "$ROOT/tools/render-system-map.py" --check >/dev/null
echo 'system map controls: PASS'
