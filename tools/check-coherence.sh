#!/bin/bash
# check-coherence.sh — repo-wide agreement check. Run by .githooks/pre-commit,
# after check-links.sh. Links prove files EXIST; this proves the facts that
# live in more than one place still AGREE. Ownership table: the Change
# protocol in recon/docs/pipeline.md.
#
# Six passes:
#   1. VERSION STAMPS — lines marked `coherence:version` must carry the exact
#      version in recon/.claude-plugin/plugin.json. Unmarked mentions (release
#      history, design-doc names) are untouched — the marker is what makes a
#      mention a claim about NOW. Caught live: docs/flow.html shipped a v0.7.0
#      chip while plugin.json said 0.8.0 (2026-08-01).
#   2. GENERATED VIEWS — native Codex manifest + skill UI metadata must exactly
#      match canonical metadata, and the replay-lab HTML must match live case,
#      oracle, command evidence, source references, and report generator bytes.
#   3. LOCAL CONTRACTS — isolated host/runtime, artifact-verifier, replay-lab,
#      and Codex activation tests pass; shared scripts and skills contain no
#      slash commands outside the single renderer.
#   4. REGISTRY MIRRORS — every `token` in recon/docs/registry.yaml (the
#      single-source artifact registry that lint-workspace.sh executes) must
#      appear in each doc that mirrors the registry: pipeline.md's table,
#      workspace-index.md, docs/flow.html's workspace table.
#   5. ROLE COVERAGE — every file in a directory that carries a role-doc
#      CLAUDE.md must be named in it. Docs must not outlive files
#      (check-links.sh); files must not outrun their role docs (this).
#   6. INVARIANT CITATIONS — every "invariant N" mention repo-wide must cite a
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
CODEX_PLUGIN_JSON="recon/.codex-plugin/plugin.json"
REGISTRY="recon/docs/registry.yaml"
PIPELINE="recon/docs/pipeline.md"
[ -f "$PLUGIN_JSON" ] || { echo "missing $PLUGIN_JSON" >&2; exit 2; }
[ -f "$CODEX_PLUGIN_JSON" ] || { echo "missing $CODEX_PLUGIN_JSON" >&2; exit 2; }
[ -f "$REGISTRY" ] || { echo "missing $REGISTRY" >&2; exit 2; }
[ -f "$PIPELINE" ] || { echo "missing $PIPELINE" >&2; exit 2; }

# ------------------------------------------------------------ 1. version stamps
echo "[1/6] version stamps → native plugin manifests"
VERSION="$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$PLUGIN_JSON" | head -1)"
[ -n "$VERSION" ] || { echo "cannot read version from $PLUGIN_JSON" >&2; exit 2; }
CODEX_VERSION="$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$CODEX_PLUGIN_JSON" | head -1)"
[ "$CODEX_VERSION" = "$VERSION" ] || say_fail "$CODEX_PLUGIN_JSON version $CODEX_VERSION != canonical $VERSION"
while IFS=: read -r file line content; do
  [ -n "$file" ] || continue
  case "$content" in
    *"v$VERSION"*) ;;
    *) say_fail "$file:$line — marked coherence:version but does not say v$VERSION (plugin.json)" ;;
  esac
done < <(grep -rn '<!-- coherence:version -->' --include='*.md' --include='*.html' . 2>/dev/null)

# ------------------------------------------------------ 2. generated adapters
echo "[2/6] generated adapters → canonical metadata"
if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required for adapter validation" >&2
  exit 2
fi
python3 tools/generate-adapters.py --check || say_fail "generated native adapters drifted"
python3 tools/render-decree-reports.py --check || say_fail "generated Decree reports contain non-portable document identities"
if ! bash tools/test-decree-reports.sh; then
  say_fail "tools/test-decree-reports.sh failed"
fi
python3 tools/render-replay-lab-report.py --check || say_fail "generated replay-lab report drifted"
if ! bash tools/test-replay-lab-report.sh; then
  say_fail "tools/test-replay-lab-report.sh failed"
fi
python3 tools/render-system-map.py --check || say_fail "generated system map drifted"
if ! bash tools/test-system-map.sh; then
  say_fail "tools/test-system-map.sh failed"
fi

# --------------------------------------------------------- 3. local contracts
echo "[3/6] local contracts → runtime + artifacts + activation"
if ! bash tools/test-host-contract.sh; then
  say_fail "tools/test-host-contract.sh failed"
fi
if ! bash tools/test-artifact-verifiers.sh; then
  say_fail "tools/test-artifact-verifiers.sh failed"
fi
if ! bash tools/test-comment-rendering.sh; then
  say_fail "tools/test-comment-rendering.sh failed"
fi
if ! bash tools/test-triage-verifier.sh; then
  say_fail "tools/test-triage-verifier.sh failed"
fi
if ! bash tools/test-replay-lab.sh; then
  say_fail "tools/test-replay-lab.sh failed"
fi
if ! bash tools/test-improvement-cycle.sh; then
  say_fail "tools/test-improvement-cycle.sh failed"
fi
if ! bash tools/test-pre-commit-check.sh; then
  say_fail "tools/test-pre-commit-check.sh failed"
fi
if ! bash tools/test-codex-activation.sh; then
  say_fail "tools/test-codex-activation.sh failed"
fi
HOST_LEAKS="$(rg -n '/recon:|/decree:' recon/scripts recon/skills --glob '!reconctl.sh' 2>/dev/null || true)"
if [ -n "$HOST_LEAKS" ]; then
  say_fail "host-specific slash command outside reconctl.sh"
  printf '%s\n' "$HOST_LEAKS" | sed 's/^/      /'
fi

# --------------------------------------------------------- 4. registry mirrors
echo "[4/6] registry tokens → mirror docs"
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

# ------------------------------------------------------------- 5. role coverage
echo "[5/6] role coverage → directory CLAUDE.md files"
for dir in recon/scripts recon/docs recon/skills tools docs evals; do
  roledoc="$dir/CLAUDE.md"
  [ -f "$roledoc" ] || { say_fail "$dir/ has no role doc ($roledoc)"; continue; }
  while IFS= read -r entry; do
    name="$(basename "$entry")"
    [ "$name" = "CLAUDE.md" ] && continue
    grep -qF "$name" "$roledoc" || say_fail "$dir/$name has no role entry in $roledoc"
  done < <(find "$dir" -mindepth 1 -maxdepth 1 ! -name '.*' | sort)
done
# Skills are also user-facing: each one must appear in the README (its table of
# commands), in plugin.json's skills array, and in the root CLAUDE.md's skill
# list when that file exists — a new skill nobody can discover is drift too.
while IFS= read -r entry; do
  name="$(basename "$entry")"
  grep -qF "$name" README.md || say_fail "recon/skills/$name is not mentioned in README.md"
  grep -qF "./skills/$name" recon/.claude-plugin/plugin.json || say_fail "recon/skills/$name is not registered in plugin.json skills[]"
  if [ -f CLAUDE.md ]; then
    grep -qF "$name" CLAUDE.md || say_fail "recon/skills/$name is not mentioned in the root CLAUDE.md skill list"
  fi
done < <(find recon/skills -mindepth 1 -maxdepth 1 -type d | sort)

# ------------------------------------------------------- 6. invariant citations
echo "[6/6] invariant citations → pipeline.md"
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
  echo "coherence: clean — version v$VERSION stamped, adapters generated, local contracts passed, registry mirrored, roles covered, citations valid"
  exit 0
else
  echo "coherence: DRIFT — fix the facts above before committing"
  exit 1
fi
