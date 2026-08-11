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
printf 'x' >>"$FLOW"
python3 - "$FLOW" <<'PY'
import sys
from pathlib import Path
path = Path(sys.argv[1])
path.write_bytes(path.read_bytes().rstrip(b"\nx"))
PY
if python3 "$ROOT/tools/render-system-map.py" --check >/dev/null 2>&1; then
  cp "$FLOW.test-backup" "$FLOW"; rm -f "$FLOW.test-backup"
  echo 'removing a trailing newline must drift the map' >&2; exit 1
fi
mv "$FLOW.test-backup" "$FLOW"
python3 "$ROOT/tools/render-system-map.py" --check >/dev/null

# Normalization is derived from .cz.toml, so a newly bump-stamped file cannot
# silently become a whole-file-hashed reference again (the bug that made every
# release refuse itself). Assert the derivation covers every hashed ref.
# -B: importing the generator must not leave tools/__pycache__ behind, which the
# role-coverage check would report as an undocumented directory.
python3 -B - "$ROOT" <<'PY'
import importlib.util, re, sys
from pathlib import Path
root = Path(sys.argv[1])
generator = root / "tools" / "render-system-map.py"
spec = importlib.util.spec_from_file_location("rsm", generator)
rsm = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rsm)
stamped = set(rsm.bump_stamped_markers())
if "docs/flow.html" not in stamped:
    raise SystemExit("derivation lost docs/flow.html — check .cz.toml version_files")
refs = set(re.findall(r'ref\("R\d+", "[^"]*", "([^"]+)"', generator.read_text(encoding="utf-8")))
covered = sorted(refs & stamped)
for path in covered:
    print(f"  hashed ref is bump-stamped and normalized: {path}")
config = (root / ".cz.toml").read_text(encoding="utf-8")
declared = {line.split(":")[0].strip().strip('",') for line in config.splitlines() if line.strip().startswith('"')}
unnormalized = sorted((refs & declared) - stamped)
if unnormalized:
    raise SystemExit(f"hashed refs are bump-stamped without normalization: {unnormalized}")
PY
echo 'system map controls: PASS'
