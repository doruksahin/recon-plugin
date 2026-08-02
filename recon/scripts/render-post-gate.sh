#!/bin/bash
# render-post-gate.sh <TICKET-ID> <zip-path> — the posting gate's presentation
# rail (ADR 0003), the delivery-path analogue of render-gate.sh:
# triage/jira/post-gate-questions.txt is EMITTED from comment.txt (the exact
# bytes that will be posted), bundle-manifest.txt, the rendered dossier, and
# the staged zip — so the gate asks a rail-rendered question, never a model
# paraphrase, and verify-post-gate.sh can prove what was asked.
# Run AFTER package-artifacts.sh (it quotes the manifest), and again after
# every Edit-loop change before re-presenting.
# Exit 0 rendered, 2 missing inputs. RECON_ROOT overrides the workspace root
# (default ~/.claude/recon) — used by fixtures.
set -euo pipefail

TICKET="${1:?usage: render-post-gate.sh <TICKET-ID> <zip-path>}"
ZIP="${2:?usage: render-post-gate.sh <TICKET-ID> <zip-path>}"
case "$TICKET" in
  *[!A-Za-z0-9-]* | "") echo "invalid ticket id: $TICKET" >&2; exit 2 ;;
esac
ROOT="${RECON_ROOT:-$HOME/.claude/recon}"
case "$ROOT" in
  /*) ;;
  *) echo "RECON_ROOT must be an absolute path: $ROOT" >&2; exit 2 ;;
esac
DIR="${ROOT%/}/$TICKET"
[ -d "$DIR" ] || { echo "no workspace: $DIR" >&2; exit 2; }

COMMENT="$DIR/triage/jira/comment.txt"
MANIFEST="$DIR/triage/jira/bundle-manifest.txt"
DOSSIER="$DIR/report/dossier.html"
OUT="$DIR/triage/jira/post-gate-questions.txt"

[ -f "$COMMENT" ] || { echo "no comment draft: $COMMENT — run render-comment.sh first" >&2; exit 2; }
[ -f "$MANIFEST" ] || { echo "no bundle manifest: $MANIFEST — run package-artifacts.sh first" >&2; exit 2; }
[ -f "$DOSSIER" ] || { echo "no dossier: $DOSSIER — render it before the gate" >&2; exit 2; }
[ -f "$ZIP" ] || { echo "no delivery zip: $ZIP — use the ZIP: path from package-artifacts.sh" >&2; exit 2; }

DOSSIER_SIZE="$(wc -c < "$DOSSIER" | tr -d ' ')"
ZIP_SIZE="$(wc -c < "$ZIP" | tr -d ' ')"
BUNDLED="$(grep -c . "$MANIFEST" || true)"
# Both recon-owned attachments ride on the single "post" answer (invariant 6).
ATTACHMENTS=2

{
  printf '# Gate — %s: post to Jira?\n\n' "$TICKET"
  printf 'Answer with one of the options below, in your own words if you prefer.\n\n'
  printf -- '- Post to Jira now (comment + %s attachments)\n' "$ATTACHMENTS"
  printf -- '- Edit first\n'
  printf -- "- Don't post\n\n"
  printf '## COMMENT — the exact bytes that will be posted\n\n'
  cat "$COMMENT"
  printf '\n## ATTACHMENTS — replacing the recon-owned files on the ticket\n\n'
  printf -- '- recon-dossier-%s.html — %s bytes\n' "$TICKET" "$DOSSIER_SIZE"
  printf -- '- recon-artifacts-%s.zip — %s bytes (%s bundled file(s))\n' \
    "$TICKET" "$ZIP_SIZE" "$BUNDLED"
} > "$OUT"

echo "rendered: triage/jira/post-gate-questions.txt ($ATTACHMENTS attachment(s), $BUNDLED bundled file(s))"
