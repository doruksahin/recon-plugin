#!/bin/bash
# check-links.sh — repo-wide anti-drift check. Run by .githooks/pre-commit.
#
# Three passes, because a link checker alone would miss most of this repo:
#   1. SELF-LINKS  — github.com/…/blob/master/<path> URLs (docs/flow.html and
#      friends) are resolved against the WORKING TREE, not the network. Master
#      lags a pre-commit run, so the local tree is the authority.
#   2. PATH REFS   — the docs name files in backticks (`package-artifacts.sh`,
#      `../../docs/pipeline.md`), which no link checker sees. A renamed script
#      would silently orphan a dozen doc references; this pass catches that.
#   3. LYCHEE      — real markdown/HTML links, incl. external URLs. Skipped with
#      a warning when the network is unreachable, so commits work offline.
#
# Runtime-workspace paths (triage/…, discovery/…, meta.yaml — files that live in
# ~/.claude/recon/<TICKET>/, never in this repo) are NOT checked here; that tree
# is lint-workspace.sh's job.
#
# Exit 0 clean, 1 drift found, 2 missing tooling.
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel)" || { echo "not a git repo" >&2; exit 2; }
cd "$ROOT" || exit 2

SELF_PREFIX="https://github.com/doruksahin/recon-plugin/blob/master/"
SCAN=(--include='*.md' --include='*.html' --exclude-dir=.git)
fail=0
checked=0

say_fail() { echo "  ✗ $1"; fail=1; }

# Docs address files from two frames: the repo root (`recon/docs/pipeline.md`)
# and the plugin root (`docs/workspace-index.md`, written from inside recon/).
# Both are legitimate, so a reference resolves if either base finds it — a
# renamed file still fails under both.
resolves() { [ -e "$1" ] || [ -e "recon/$1" ]; }

# ---------------------------------------------------------------- 1. self-links
echo "[1/3] self-links → working tree"
while IFS= read -r url; do
  [ -n "$url" ] || continue
  path="${url#"$SELF_PREFIX"}"
  path="${path%%#*}"
  checked=$((checked + 1))
  [ -e "$path" ] || say_fail "$path — linked from a doc, not in the working tree ($url)"
done < <(grep -rhoE "${SELF_PREFIX//./\\.}[^ \")<>\`']+" "${SCAN[@]}" . 2>/dev/null | sed 's/[.,)]*$//' | sort -u)

# ------------------------------------------------------------- 2. path refs
echo "[2/3] backticked path references → working tree"

# 2a. every *.sh named in the docs must exist somewhere in the tree. Matching by
# basename keeps `foo.sh`, `scripts/foo.sh` and `recon/scripts/foo.sh` — all three
# spellings the docs use — under one rule, and spans recon/scripts/ + tools/.
SH_INDEX="$(find . -name '*.sh' -not -path './.git/*' -exec basename {} \; | sort -u)"
while IFS= read -r name; do
  [ -n "$name" ] || continue
  checked=$((checked + 1))
  grep -qxF "$name" <<<"$SH_INDEX" || say_fail "$name — referenced in docs, no such script in the repo"
done < <(grep -rhoE '`[a-zA-Z0-9_./-]*[a-zA-Z0-9_-]+\.sh`' "${SCAN[@]}" . 2>/dev/null \
         | tr -d '`' | xargs -n1 basename 2>/dev/null | sort -u)

# 2b. root-relative refs (recon/… docs/… tools/…) must exist from the repo root
while IFS= read -r path; do
  [ -n "$path" ] || continue
  checked=$((checked + 1))
  resolves "$path" || say_fail "$path — referenced in docs, missing from the repo"
done < <(grep -rhoE '`(recon|docs|tools)/[a-zA-Z0-9_./-]+`' "${SCAN[@]}" . 2>/dev/null \
         | tr -d '`' | grep -vE '/<|>' | sort -u)

# 2c. ../-relative refs resolve against the file that contains them
while IFS= read -r f; do
  d="$(dirname "$f")"
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    checked=$((checked + 1))
    [ -e "$d/$rel" ] || say_fail "$rel — referenced in $f, resolves to a missing path"
  done < <(grep -ohE '`\.\./[a-zA-Z0-9_./-]+`' "$f" 2>/dev/null | tr -d '`' | sort -u)
done < <(find . -name '*.md' -not -path './.git/*' | sort)

# ------------------------------------------------------------------- 3. lychee
echo "[3/3] lychee — markdown/HTML links"
if ! command -v lychee >/dev/null 2>&1; then
  echo "  ! lychee not installed (brew install lychee) — external links unchecked"
elif ! curl -sS --max-time 5 -o /dev/null https://github.com 2>/dev/null; then
  echo "  ! network unreachable — external links unchecked this run"
else
  lychee --no-progress --include-fragments . || fail=1
fi

# ------------------------------------------------------------------- verdict
echo
if [ "$fail" -eq 0 ]; then
  echo "links: clean — $checked repo reference(s) resolved"
else
  echo "links: DRIFT — fix the paths above before committing"
  exit 1
fi
