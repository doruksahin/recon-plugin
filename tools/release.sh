#!/bin/bash
# release.sh — cut a release from the commits since the last tag.
#
# commitizen does the decisions: it reads the commit types since the last tag,
# picks the next version (see CONTRIBUTING.md for the rules), prepends a section
# to CHANGELOG.md, writes the number into recon/.claude-plugin/plugin.json, and
# creates an annotated tag. This script adds only what commitizen does not:
#
#   1. GUARDS   — refuse on the wrong branch, a dirty tree, or an empty range,
#      because each of those produces a release that is wrong in a way you find
#      out about days later.
#   2. LINKS    — run check-links.sh up front. The bump is a real commit, so the
#      pre-commit hook fires mid-bump; failing there leaves CHANGELOG.md and
#      plugin.json edited but uncommitted. Failing first leaves nothing behind.
#   3. PREVIEW  — show the exact version and changelog, and require a yes.
#   4. PUBLISH  — push the tag and open the GitHub Release with this version's
#      section as the body. The annotated tag body is just the version string,
#      so --notes-from-tag would publish an empty release; the section is sliced
#      out of CHANGELOG.md instead.
#
# Exit 0 released, 1 refused or aborted, 2 missing tooling.
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel)" || { echo "not a git repo" >&2; exit 2; }
cd "$ROOT" || exit 2

CZ="$ROOT/tools/cz.sh"
BRANCH="$(git rev-parse --abbrev-ref HEAD)"

refuse() { echo "release refused: $1" >&2; exit 1; }

# ------------------------------------------------------------------- 1. guards
[ "$BRANCH" = master ] || refuse "on '$BRANCH', releases are cut from master"
[ -z "$(git status --porcelain)" ] || refuse "working tree is dirty — commit or stash first"

LAST_TAG="$(git describe --tags --abbrev=0 2>/dev/null)"
if [ -n "$LAST_TAG" ] && [ -z "$(git log "$LAST_TAG"..HEAD --oneline)" ]; then
  refuse "no commits since $LAST_TAG"
fi

# -------------------------------------------------------------------- 2. links
echo "[1/4] link check"
"$ROOT/tools/check-links.sh" >/dev/null || refuse "check-links.sh found drift — fix it before releasing"
echo "  ✓ clean"

# ------------------------------------------------------------------ 3. preview
echo
echo "[2/4] preview — ${LAST_TAG:-repo start}..HEAD"
echo
"$CZ" bump --changelog --dry-run
status=$?
[ "$status" -eq 2 ] && exit 2
[ "$status" -ne 0 ] && refuse "commitizen could not compute a bump (no releasable commits?)"

echo
printf 'release this? [y/N] '
read -r reply
[ "$reply" = y ] || [ "$reply" = Y ] || { echo "aborted"; exit 1; }

# --------------------------------------------------------------------- 4. bump
echo
echo "[3/4] bump"
"$CZ" bump --changelog || refuse "bump failed — nothing was tagged; check git status"

VERSION="$("$CZ" version -p)"
TAG="v$VERSION"

# ------------------------------------------------------------------ 5. publish
echo
echo "[4/4] publish $TAG"
git push --follow-tags || refuse "push failed — $TAG exists locally, re-run 'git push --follow-tags'"

if ! command -v gh >/dev/null 2>&1; then
  echo "  ! gh not installed — tag pushed, GitHub Release not created"
  echo "    gh release create $TAG --notes \"\$(awk '/^## /{n++} n==1' CHANGELOG.md)\""
  exit 0
fi

# The first '## ' heading is this release; stop at the second.
gh release create "$TAG" \
  --title "$TAG" \
  --notes "$(awk '/^## /{n++} n==1' CHANGELOG.md)" \
  || { echo "  ! GitHub Release failed — tag is pushed, create it by hand" >&2; exit 1; }

echo
echo "released $TAG"
