#!/bin/bash
# activate-codex-plugin.sh — refresh and reinstall Recon from a configured
# Codex marketplace. Never edits Codex config directly. If the marketplace is
# not configured, prints the exact setup command and exits cleanly.
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "not a git repo" >&2; exit 2; }
MARKETPLACE_JSON="$ROOT/.agents/plugins/marketplace.json"
PLUGIN_JSON="$ROOT/recon/.codex-plugin/plugin.json"
[ -f "$MARKETPLACE_JSON" ] || { echo "missing $MARKETPLACE_JSON" >&2; exit 2; }
[ -f "$PLUGIN_JSON" ] || { echo "missing $PLUGIN_JSON" >&2; exit 2; }
command -v codex >/dev/null 2>&1 || { echo "codex: SKIPPED — Codex CLI is not installed"; exit 0; }

readarray_values="$(python3 - "$MARKETPLACE_JSON" "$PLUGIN_JSON" <<'PY'
import json, sys
marketplace = json.load(open(sys.argv[1]))
plugin = json.load(open(sys.argv[2]))
print(marketplace["name"])
print(plugin["name"])
print(plugin["version"])
PY
)" || { echo "invalid Codex marketplace/plugin JSON" >&2; exit 2; }
MARKETPLACE="$(printf '%s\n' "$readarray_values" | sed -n '1p')"
PLUGIN="$(printf '%s\n' "$readarray_values" | sed -n '2p')"
VERSION="$(printf '%s\n' "$readarray_values" | sed -n '3p')"

configured="$(codex plugin marketplace list --json | python3 -c '
import json, sys
name = sys.argv[1]
rows = json.load(sys.stdin).get("marketplaces", [])
print("yes" if any(row.get("name") == name for row in rows) else "no")
' "$MARKETPLACE")"

if [ "$configured" != yes ]; then
  echo "codex: SKIPPED — marketplace '$MARKETPLACE' is not configured"
  echo "codex: setup — codex plugin marketplace add $ROOT"
  echo "codex: install — codex plugin add $PLUGIN@$MARKETPLACE"
  exit 0
fi

# Local marketplaces already see the working tree; Git marketplaces need an
# explicit refresh. Upgrade is safe for either configured source, but older
# clients can reject it for local sources, so ignore only that local case.
if ! codex plugin marketplace upgrade "$MARKETPLACE" >/dev/null 2>&1; then
  echo "codex: marketplace '$MARKETPLACE' is local or did not require upgrade"
else
  echo "codex: marketplace '$MARKETPLACE' upgraded"
fi
codex plugin add "$PLUGIN@$MARKETPLACE" --json >/dev/null
echo "codex: activated $PLUGIN@$MARKETPLACE v$VERSION"
