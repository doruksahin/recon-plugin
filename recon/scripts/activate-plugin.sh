#!/bin/bash
# activate-plugin.sh [<source-repo-root>] — activate the locally built version
# of every plugin in this marketplace repo, so new Claude Code sessions load it
# without the interactive /plugin flow.
#
# Plugin-agnostic on purpose (parked in recon, built for extraction): all
# identity comes from the SOURCE repo's own files —
#   .claude-plugin/marketplace.json   marketplace name + plugin list
#   <plugin>/.claude-plugin/plugin.json   each plugin's name + version
#
# Per plugin it: copies the plugin dir into
# ~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/ (dotfiles included,
# previously pinned version dirs NEVER deleted — a live session may hold script
# paths into them), then repoints the <plugin>@<marketplace> entry in
# ~/.claude/plugins/installed_plugins.json (installPath, version, gitCommitSha,
# lastUpdated). That file is Claude Code INTERNAL format: the structure is
# validated first and any surprise fails loudly rather than being written over.
# Finally, if known_marketplaces.json points this marketplace at a git clone
# other than the source repo, that clone is fast-forwarded to origin/master.
#
# Exit 0 activated, 1 refused (validation/sync failure), 2 missing inputs.
set -uo pipefail

ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null)}"
[ -n "$ROOT" ] && [ -d "$ROOT" ] || { echo "not in a git repo and no <source-repo-root> given" >&2; exit 2; }
MP_JSON="$ROOT/.claude-plugin/marketplace.json"
[ -f "$MP_JSON" ] || { echo "no marketplace manifest: $MP_JSON — run from a marketplace repo" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required" >&2; exit 2; }
SHA="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo unknown)"

python3 - "$ROOT" "$SHA" <<'EOF'
import json, shutil, subprocess, sys
from datetime import datetime, timezone
from pathlib import Path

root, sha = Path(sys.argv[1]), sys.argv[2]
plugins_home = Path.home() / ".claude" / "plugins"
mp = json.loads((root / ".claude-plugin" / "marketplace.json").read_text())
mp_name = mp.get("name")
if not mp_name or not isinstance(mp.get("plugins"), list):
    sys.exit(f"REFUSED: {root}/.claude-plugin/marketplace.json has no name/plugins[]")

installed_path = plugins_home / "installed_plugins.json"
installed = json.loads(installed_path.read_text())
if installed.get("version") != 2 or not isinstance(installed.get("plugins"), dict):
    sys.exit("REFUSED: installed_plugins.json is not the expected version-2 shape — "
             "Claude Code's internal format changed; update activate-plugin.sh before writing")

for p in mp["plugins"]:
    src = (root / p["source"]).resolve()
    pj = json.loads((src / ".claude-plugin" / "plugin.json").read_text())
    name, version = pj["name"], pj["version"]
    key = f"{name}@{mp_name}"
    entries = installed["plugins"].get(key)
    if not entries or not isinstance(entries, list) or "installPath" not in entries[0]:
        sys.exit(f"REFUSED: {key} not installed (or unexpected entry shape) — "
                 f"install it once via /plugin, then re-run")
    dest = plugins_home / "cache" / mp_name / name / version
    dest.mkdir(parents=True, exist_ok=True)      # old version dirs stay untouched
    shutil.copytree(src, dest, dirs_exist_ok=True)
    e = entries[0]
    e["installPath"] = str(dest)
    e["version"] = version
    e["gitCommitSha"] = sha
    e["lastUpdated"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"
    print(f"activated: {key} v{version} ({sha[:12]})")
    print(f"cache: {dest}")

installed_path.write_text(json.dumps(installed, indent=1))

# Sync the marketplace clone when it is a separate git checkout of this repo.
try:
    known = json.loads((plugins_home / "known_marketplaces.json").read_text())
    loc = Path(known.get(mp_name, {}).get("installLocation", ""))
    if loc and loc.exists() and loc.resolve() != root.resolve() and (loc / ".git").exists():
        r = subprocess.run(["git", "-C", str(loc), "pull", "--ff-only"],
                           capture_output=True, text=True)
        state = "synced" if r.returncode == 0 else f"SYNC FAILED — {r.stderr.strip().splitlines()[-1] if r.stderr else 'see git output'}"
        print(f"clone: {loc} {state}")
    else:
        print("clone: n/a (marketplace served from the source repo or no separate clone)")
except (OSError, json.JSONDecodeError) as exc:
    print(f"clone: skipped ({exc})")
EOF
