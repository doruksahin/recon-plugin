#!/bin/bash
# package-artifacts.sh <TICKET-ID> — build the delivery bundle for a recon run.
# Zips every current-run file (never runs/) into a temp zip and writes the
# deterministic manifest to triage/jira/bundle-manifest.txt (size + rel path
# per line, sorted). The zip is staged OUTSIDE the workspace (its contents ARE
# the workspace; keeping it inside would self-include and bloat re-archives).
# Symlinks are intentionally omitted (find -type f), matching lint-workspace.sh.
# Prints MANIFEST/ZIP lines. Exit 0 ok, 2 bad ticket-id / no workspace / nothing to bundle.
set -euo pipefail

TICKET="${1:?usage: package-artifacts.sh <TICKET-ID>}"
case "$TICKET" in
  *[!A-Za-z0-9-]* | "") echo "invalid ticket id: $TICKET" >&2; exit 2 ;;
esac
RECON_ROOT="${RECON_ROOT:-$HOME/.claude/recon}"
DIR="$RECON_ROOT/$TICKET"
[ -d "$DIR" ] || { echo "no workspace: $DIR" >&2; exit 2; }

OUT="${RECON_BUNDLE_DIR:-${TMPDIR:-/tmp}}/recon-artifacts-$TICKET.zip"
rm -f "$OUT"
mkdir -p "$DIR/triage/jira"
MANIFEST="$DIR/triage/jira/bundle-manifest.txt"
: > "$MANIFEST"

# Per-file size guard: a long session.webm may exceed Jira attachment limits;
# an oversized file degrades the bundle (visible SKIPPED line), never the
# delivery. Override with RECON_BUNDLE_MAX_FILE_SIZE (bytes).
MAX_FILE_SIZE="${RECON_BUNDLE_MAX_FILE_SIZE:-20971520}"

while IFS= read -r f; do
  rel="${f#"$DIR"/}"
  case "$rel" in
    runs/* | triage/jira/bundle-manifest.txt) continue ;;
  esac
  size=$(wc -c < "$f" | tr -d ' ')
  if [ "$size" -gt "$MAX_FILE_SIZE" ]; then
    echo "SKIPPED: $rel ($size bytes > $MAX_FILE_SIZE limit)"
    continue
  fi
  printf '%s %s\n' "$size" "$rel" >> "$MANIFEST"
done < <(find "$DIR" -type f ! -path "$DIR/runs/*" | LC_ALL=C sort)

[ -s "$MANIFEST" ] || { echo "no artifacts to bundle: $DIR" >&2; exit 2; }

(cd "$DIR" && cut -d' ' -f2- "$MANIFEST" | zip -q -X "$OUT" -@)
echo "MANIFEST: $MANIFEST ($(grep -c . "$MANIFEST") files)"
echo "ZIP: $OUT ($(wc -c < "$OUT" | tr -d ' ') bytes)"
