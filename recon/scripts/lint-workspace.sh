#!/bin/bash
# lint-workspace.sh <TICKET-ID> — recon invariant 10 as a rail.
#
# Compares the current-run workspace tree against the artifact registry
# (recon/docs/registry.yaml — the single source of truth; the pipeline.md
# table is a checked mirror of it). Every file must match a registered
# pattern; anything else is an undeclared artifact — a contract violation.
# runs/ is archived history and is skipped entirely. Exit 0 = clean,
# 1 = violations, 2 = no workspace or broken install.
set -euo pipefail

TICKET="${1:?usage: lint-workspace.sh <TICKET-ID>}"
case "$TICKET" in
  *[!A-Za-z0-9-]* | "") echo "invalid ticket id: $TICKET" >&2; exit 2 ;;
esac

DIR="$HOME/.claude/recon/$TICKET"
[ -d "$DIR" ] || { echo "no workspace: $DIR" >&2; exit 2; }

# Match patterns come from the registry data file that ships next to this
# script — registering a new artifact means adding an entry THERE, never here.
REGISTRY="$(cd "$(dirname "$0")" && pwd)/../docs/registry.yaml"
[ -f "$REGISTRY" ] || { echo "no artifact registry: $REGISTRY — broken plugin install" >&2; exit 2; }
PATTERNS=()
while IFS= read -r p; do
  PATTERNS+=("$p")
done < <(sed -n 's/^- pattern: *"\(.*\)"$/\1/p' "$REGISTRY")
[ "${#PATTERNS[@]}" -ge 1 ] || { echo "artifact registry has no patterns: $REGISTRY" >&2; exit 2; }

violations=0
checked=0
while IFS= read -r f; do
  rel="${f#"$DIR"/}"
  checked=$((checked + 1))
  matched=0
  for p in "${PATTERNS[@]}"; do
    # shellcheck disable=SC2254  # $p is a glob on purpose — case matches it as a pattern
    case "$rel" in
      $p) matched=1; break ;;
    esac
  done
  if [ "$matched" -eq 0 ]; then
    echo "VIOLATION: $rel — not in the artifact registry (recon/docs/registry.yaml)"
    violations=$((violations + 1))
  fi
done < <(find "$DIR" -type f ! -path "$DIR/runs/*" | sort)

# Vocabulary fence: when this run resolved governance to "none", no artifact may
# contain governance-system vocabulary — the developer opted out (or never opted
# in) and must not see it. Verified by grep, not by trust.
RY="$DIR/route/routing.yaml"
if [ -f "$RY" ] && grep -qE '^[[:space:]]*governance: none$' "$RY"; then
  while IFS= read -r f; do
    rel="${f#"$DIR"/}"
    hits="$( { grep -nIiE '\bdecree\b' "$f" 2>/dev/null || true; grep -nIE '\bSPEC\b|\bPRD\b|\bADR\b' "$f" 2>/dev/null || true; } | head -3 )"
    if [ -n "$hits" ]; then
      echo "FENCE VIOLATION: $rel contains governance vocabulary despite governance: none —"
      printf '%s\n' "$hits" | sed 's/^/    /'
      violations=$((violations + 1))
    fi
  done < <(find "$DIR" -type f ! -path "$DIR/runs/*" | sort)
fi

if [ "$violations" -eq 0 ]; then
  echo "lint: clean — $checked file(s), all registered"
else
  echo "lint: $violations violation(s) out of $checked file(s) — register the artifact or remove it"
  exit 1
fi
