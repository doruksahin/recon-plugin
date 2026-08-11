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

# A release rewrites flow.html's version stamps inside the bump commit, whose
# pre-commit hook runs check-coherence.sh before this map could be regenerated.
# If a renumbered stamp moved a reference hash, every release would refuse
# itself, so a simulated bump must stay clean while real drift still fails.
FLOW="$ROOT/docs/flow.html"
cp "$FLOW" "$FLOW.test-backup"
python3 - "$FLOW" <<'PY'
import re, sys
from pathlib import Path
path = Path(sys.argv[1])
lines = []
for text in path.read_text(encoding="utf-8").splitlines(keepends=True):
    if "coherence:version" in text or "~recon-triage v" in text:
        text = re.sub(r"\d+\.\d+\.\d+", "99.99.99", text)
    lines.append(text)
path.write_text("".join(lines), encoding="utf-8")
PY
if ! python3 "$ROOT/tools/render-system-map.py" --check >/dev/null 2>&1; then
  cp "$FLOW.test-backup" "$FLOW"; rm -f "$FLOW.test-backup"
  echo 'bump-stamp renumbering must not drift the map' >&2; exit 1
fi
printf '\n<!-- unmarked drift -->\n' >> "$FLOW"
if python3 "$ROOT/tools/render-system-map.py" --check >/dev/null 2>&1; then
  cp "$FLOW.test-backup" "$FLOW"; rm -f "$FLOW.test-backup"
  echo 'expected unmarked flow.html drift failure' >&2; exit 1
fi
mv "$FLOW.test-backup" "$FLOW"
python3 "$ROOT/tools/render-system-map.py" --check >/dev/null
echo 'system map controls: PASS'
