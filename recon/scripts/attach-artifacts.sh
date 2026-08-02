#!/bin/bash
# attach-artifacts.sh <TICKET-ID> <file>... — replace-not-accumulate (invariant 14).
# Deletes prior attachments named recon-*-<TICKET>.* on the issue, uploads the
# given files, writes triage/jira/attach-result.json (deleted ids + upload
# responses). Needs ~/.config/jira/env and python3. Run BEFORE posting the
# comment so [^filename] links resolve (duplicate names resolve to the OLDER
# attachment — verified). Exit 0 ok, 1 API failure, 2 usage/missing input.
# Safe to re-run after failure: a failed run leaves no recon attachments until retried.
set -euo pipefail

TICKET="${1:?usage: attach-artifacts.sh <TICKET-ID> <file>...}"; shift
[ "$#" -ge 1 ] || { echo "usage: attach-artifacts.sh <TICKET-ID> <file>..." >&2; exit 2; }
case "$TICKET" in
  *[!A-Za-z0-9-]* | "") echo "invalid ticket id: $TICKET" >&2; exit 2 ;;
esac
for f in "$@"; do [ -f "$f" ] || { echo "no such file: $f" >&2; exit 2; }; done
[ -f "$HOME/.config/jira/env" ] || { echo "no credentials: ~/.config/jira/env" >&2; exit 2; }

set -a; . "$HOME/.config/jira/env"; set +a
HOST="${JIRA_HOST#https://}"; HOST="${HOST%/}"
RECON_ROOT="${RECON_ROOT:-$HOME/.claude/recon}"
DIR="$RECON_ROOT/$TICKET/triage/jira"; mkdir -p "$DIR"
rm -f "$DIR/attach-result.json"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# 1. Find prior recon attachments (namespace recon-*-<TICKET>.*)
curl -sS -u "$JIRA_EMAIL:$JIRA_API_TOKEN" \
  "https://$HOST/rest/api/2/issue/$TICKET?fields=attachment" -o "$TMP/issue.json"
python3 -c '
import json, re, sys
t = sys.argv[1]
d = json.load(open(sys.argv[2]))
pat = re.compile(r"^recon-.*-" + re.escape(t) + r"\.")
for a in d["fields"]["attachment"]:
    if pat.match(a["filename"]):
        print(a["id"])
' "$TICKET" "$TMP/issue.json" > "$TMP/stale-ids.txt"

# 2. Delete them (replace, not accumulate)
: > "$TMP/deleted.txt"
while IFS= read -r id; do
  [ -n "$id" ] || continue
  code=$(curl -sS -o /dev/null -w "%{http_code}" -u "$JIRA_EMAIL:$JIRA_API_TOKEN" \
    -X DELETE "https://$HOST/rest/api/2/attachment/$id")
  printf '%s %s\n' "$id" "$code" >> "$TMP/deleted.txt"
  [ "$code" = "204" ] || { echo "delete failed: $id HTTP $code" >&2; exit 1; }
  echo "deleted: $id HTTP $code"
done < "$TMP/stale-ids.txt"

# 3. Upload the new files
i=0
for f in "$@"; do
  i=$((i + 1))
  code=$(curl -sS -o "$TMP/upload-$i.json" -w "%{http_code}" \
    -u "$JIRA_EMAIL:$JIRA_API_TOKEN" -X POST -H "X-Atlassian-Token: no-check" \
    -F "file=@$f" "https://$HOST/rest/api/2/issue/$TICKET/attachments")
  echo "uploaded: $(basename "$f") HTTP $code"
  [ "$code" = "200" ] || { echo "upload failed: $f" >&2; exit 1; }
done

# 4. Assemble attach-result.json
python3 -c '
import json, sys, glob
tmp = sys.argv[1]
deleted = []
for line in open(tmp + "/deleted.txt"):
    i, c = line.split()
    deleted.append({"id": i, "http": int(c)})
uploads = []
for p in sorted(glob.glob(tmp + "/upload-*.json")):
    uploads.extend(json.load(open(p)))
json.dump({"deleted": deleted, "uploaded": uploads},
          open(sys.argv[2], "w"), indent=2)
' "$TMP" "$DIR/attach-result.json"
echo "attach-result: $DIR/attach-result.json"
RECON_ROOT="$RECON_ROOT" \
  bash "$(cd "$(dirname "$0")" && pwd)/log-event.sh" "$TICKET" attachments_replaced "count=$#"
