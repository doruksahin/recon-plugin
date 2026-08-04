#!/bin/bash
# check-commit-msg.sh — reject a subject line commitizen cannot parse.
# Run by .githooks/commit-msg.
#
# CHANGELOG.md is generated from commit subjects, so an unparseable subject is
# not a style nit: it vanishes from the changelog entirely, and it is missing
# from the release notes rather than visibly wrong in them. That is the failure
# mode nobody notices, so it is worth a hook.
#
# Missing tooling warns instead of blocking, matching check-links.sh — a fresh
# clone without uv should still be able to commit.
#
# Exit 0 parseable (or unchecked), 1 rejected.
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel)" || exit 0

"$ROOT/tools/cz.sh" check --commit-msg-file "$1"
status=$?

if [ "$status" -eq 2 ]; then
  echo "  ! commitizen unavailable — commit message unchecked this run"
  exit 0
fi

if [ "$status" -ne 0 ]; then
  cat >&2 <<'EOF'

  Expected:  type(scope): subject
  Types:     feat fix perf refactor revert docs chore ci build test style
  Breaking:  feat(scope)!: subject   + a BREAKING CHANGE: footer

  Only feat, fix, perf and refactor reach CHANGELOG.md.
  See CONTRIBUTING.md and correct the message before committing.
EOF
  exit 1
fi
