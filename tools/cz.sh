#!/bin/bash
# cz.sh — run commitizen, however it happens to be available on this machine.
#
# Prefers an installed `cz`. Falls back to `uvx`, which needs no install but
# does need network on its first run (uv caches the environment after that).
# Used by .githooks/commit-msg and tools/release.sh so neither has to care.
#
# Exit code is commitizen's own, except 2 = commitizen is not reachable at all.
set -uo pipefail

command -v cz   >/dev/null 2>&1 && exec cz "$@"
command -v uvx  >/dev/null 2>&1 && exec uvx --from commitizen cz "$@"

echo "commitizen not found — 'brew install uv' or 'pipx install commitizen'" >&2
exit 2
