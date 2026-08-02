#!/bin/bash
# check-coherence.sh — repo-wide agreement check. Run by .githooks/pre-commit,
# after check-links.sh. Links prove files EXIST; this proves the facts that
# live in more than one place still AGREE. Ownership table: the Change
# protocol in recon/docs/pipeline.md.
#
# Four passes:
#   1. VERSION STAMPS — lines marked `coherence:version` must carry the exact
#      version in recon/.claude-plugin/plugin.json. Unmarked mentions (release
#      history, design-doc names) are untouched — the marker is what makes a
#      mention a claim about NOW. Caught live: docs/flow.html shipped a v0.7.0
#      chip while plugin.json said 0.8.0 (2026-08-01).
#   2. REGISTRY MIRRORS — every `token` in recon/docs/registry.yaml (the
#      single-source artifact registry that lint-workspace.sh executes) must
#      appear in each doc that mirrors the registry: pipeline.md's table,
#      workspace-index.md, docs/flow.html's workspace table.
#   3. ROLE COVERAGE — every file in a directory that carries a role-doc
#      CLAUDE.md must be named in it. Docs must not outlive files
#      (check-links.sh); files must not outrun their role docs (this).
#   4. INVARIANT CITATIONS — every "invariant N" mention repo-wide must cite a
#      number that exists in pipeline.md's Invariants section (renumbering or
#      deleting an invariant fails here, not silently).
#
# Exit 0 clean, 1 drift found, 2 missing tooling/inputs.
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel)" || { echo "not a git repo" >&2; exit 2; }
cd "$ROOT" || exit 2

fail=0
say_fail() { echo "  ✗ $1"; fail=1; }

PLUGIN_JSON="recon/.claude-plugin/plugin.json"
REGISTRY="recon/docs/registry.yaml"
PIPELINE="recon/docs/pipeline.md"
[ -f "$PLUGIN_JSON" ] || { echo "missing $PLUGIN_JSON" >&2; exit 2; }
[ -f "$REGISTRY" ] || { echo "missing $REGISTRY" >&2; exit 2; }
[ -f "$PIPELINE" ] || { echo "missing $PIPELINE" >&2; exit 2; }

# ------------------------------------------------------------ 1. version stamps
echo "[1/4] version stamps → plugin.json"
VERSION="$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$PLUGIN_JSON" | head -1)"
[ -n "$VERSION" ] || { echo "cannot read version from $PLUGIN_JSON" >&2; exit 2; }
while IFS=: read -r file line content; do
  [ -n "$file" ] || continue
  case "$content" in
    *"v$VERSION"*) ;;
    *) say_fail "$file:$line — marked coherence:version but does not say v$VERSION (plugin.json)" ;;
  esac
done < <(grep -rn '<!-- coherence:version -->' --include='*.md' --include='*.html' . 2>/dev/null)

# --------------------------------------------------------- 2. registry mirrors
echo "[2/4] registry tokens → mirror docs"
MIRRORS=("$PIPELINE" "recon/docs/workspace-index.md" "docs/flow.html")
for m in "${MIRRORS[@]}"; do
  [ -f "$m" ] || { echo "missing registry mirror $m" >&2; exit 2; }
done
while IFS= read -r token; do
  [ -n "$token" ] || continue
  for m in "${MIRRORS[@]}"; do
    grep -qF "$token" "$m" || say_fail "registry token '$token' missing from $m"
  done
done < <(sed -n 's/^  token: *"\(.*\)"$/\1/p' "$REGISTRY")

# ------------------------------------------------------------- 3. role coverage
echo "[3/4] role coverage → directory CLAUDE.md files"
for dir in recon/scripts recon/docs recon/skills tools docs; do
  roledoc="$dir/CLAUDE.md"
  [ -f "$roledoc" ] || { say_fail "$dir/ has no role doc ($roledoc)"; continue; }
  while IFS= read -r entry; do
    name="$(basename "$entry")"
    [ "$name" = "CLAUDE.md" ] && continue
    grep -qF "$name" "$roledoc" || say_fail "$dir/$name has no role entry in $roledoc"
  done < <(find "$dir" -mindepth 1 -maxdepth 1 ! -name '.*' | sort)
done

# ------------------------------------------------------- 4. invariant citations
echo "[4/4] invariant citations → pipeline.md"
MAX_INV="$(awk '/^## Invariants/{f=1;next} /^## /{f=0} f && /^[0-9]+\./{n=$1} END{sub(/\./,"",n); print n}' "$PIPELINE")"
if [ -z "$MAX_INV" ]; then
  say_fail "cannot determine invariant count from $PIPELINE"
else
  while IFS=: read -r file line match; do
    [ -n "$file" ] || continue
    while IFS= read -r num; do
      if [ "$num" -lt 1 ] || [ "$num" -gt "$MAX_INV" ]; then
        say_fail "$file:$line cites invariant $num — pipeline.md has 1..$MAX_INV"
      fi
    done < <(printf '%s\n' "$match" | grep -oE '[0-9]+')
  done < <(grep -rnoiE 'invariants? [0-9]+([–—-][0-9]+)?' --include='*.md' --include='*.html' --include='*.sh' --include='*.py' --include='*.yaml' . 2>/dev/null | grep -v '^\./tools/check-coherence.sh')
fi

if [ "$fail" -eq 0 ]; then
  echo "coherence: clean — version v$VERSION stamped, registry mirrored, roles covered, citations valid"
  exit 0
else
  echo "coherence: DRIFT — fix the facts above, or commit with --no-verify"
  exit 1
fi
