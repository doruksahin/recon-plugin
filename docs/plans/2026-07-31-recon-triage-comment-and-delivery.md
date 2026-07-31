# Progressive-Disclosure Comments + Jira Attachment Delivery — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Recon triage posts a short n+4-line Jira comment (blocker title + mention + one-line ask each) and attaches the full detail — dossier + artifact bundle — to the ticket, replacing prior recon attachments on re-runs; the Jira-MCP question is closed with an ADR.

**Architecture:** All new behavior lands as rails per the pipeline design formula: two new shell scripts (`package-artifacts.sh`, `attach-artifacts.sh`), one shape-verifier rail (`verify-comment-shape.sh`), schema growth in `triage.yaml` (structured `blockers`), a new dossier template section, and doc/invariant updates. `recon-report` gains a render-only mode auto-invoked on the BLOCKED posting path. Design doc: `docs/plans/2026-07-31-recon-triage-comment-and-delivery-design.md` (approved).

**Tech Stack:** bash (POSIX-leaning, `find`-based checks), curl + Jira REST API v2, python3 for JSON parsing inside scripts (present on macOS dev machines via CLT), zip, optional headless Chrome for PDF.

**Repo:** `~/Desktop/ADCREATIVE/recon-plugin` (work on `master`, per the plugin's change protocol — no worktree; this repo is docs+scripts only).

**Version:** bump `recon/.claude-plugin/plugin.json` 0.6.0 → **0.7.0** in the final task.

---

## Conventions for this plan

- `$REPO` = `~/Desktop/ADCREATIVE/recon-plugin`.
- "Fixture workspace" = a fake ticket workspace at `~/.claude/recon/ZZZ-999` created by the task and deleted at its end (`rm -rf ~/.claude/recon/ZZZ-999`).
- Scripts have no formal test harness; TDD here means: write the assertion commands first, watch them fail (script missing), implement, watch them pass.
- Commit after every task, conventional commits, from `$REPO`.

---

### Task 0: Preflight — sandbox ticket + credentials

**Step 1:** Ask Doruk (AskUserQuestion) which Jira ticket to use as the **sandbox** for attachment spikes (needs: safe to attach/delete files and post one throwaway comment; a test-project issue is ideal). Record the ID as `$SANDBOX` in `docs/plans/2026-07-31-spike-notes.md` (create the file with a `# Spike notes` header).

**Step 2:** Verify credentials work:

```bash
set -a && source ~/.config/jira/env && set +a
HOST="${JIRA_HOST#https://}"; HOST="${HOST%/}"
curl -sS -o /dev/null -w "%{http_code}\n" -u "$JIRA_EMAIL:$JIRA_API_TOKEN" \
  "https://$HOST/rest/api/2/issue/$SANDBOX?fields=summary"
```

Expected: `200`.

**Step 3:** Commit spike-notes scaffold: `git add docs/plans/2026-07-31-spike-notes.md && git commit -m "docs(plans): spike notes scaffold for v0.7.0 delivery work"`.

---

### Task 1: Spike A — attachment upload, `[^filename]` link, delete (replace semantics)

**Files:** Modify: `docs/plans/2026-07-31-spike-notes.md` (results only; no plugin code).

**Step 1: Upload a dummy file twice under the recon naming convention**

```bash
echo "recon spike $(date -u +%FT%TZ)" > /tmp/recon-dossier-$SANDBOX.html
curl -sS -u "$JIRA_EMAIL:$JIRA_API_TOKEN" -X POST -H "X-Atlassian-Token: no-check" \
  -F "file=@/tmp/recon-dossier-$SANDBOX.html" \
  "https://$HOST/rest/api/2/issue/$SANDBOX/attachments"
```

Expected: `200` with a JSON array containing `id` and `filename`. Run twice — confirm Jira **accumulates** duplicates (two attachments, same filename) rather than replacing; this is why the delete rail exists.

**Step 2: Post a comment with an attachment link and check rendering**

```bash
curl -sS -u "$JIRA_EMAIL:$JIRA_API_TOKEN" -X POST -H "Content-Type: application/json" \
  -d '{"body":"spike: link test [^recon-dossier-'$SANDBOX'.html] ~recon-triage spike~"}' \
  "https://$HOST/rest/api/2/issue/$SANDBOX/comment"
```

Open the ticket in the browser (preview tools). Expected: the `[^…]` renders as a clickable attachment link. If it renders as literal text, record that and fall back to the attachment's `content` URL (from the upload response) as a plain link in the comment schema.

**Step 3: Delete by id — the permission check**

```bash
curl -sS -o /dev/null -w "%{http_code}\n" -u "$JIRA_EMAIL:$JIRA_API_TOKEN" \
  -X DELETE "https://$HOST/rest/api/2/attachment/<id-from-step-1>"
```

Expected: `204`. If `403`: record it — the replace rail degrades to "upload new + comment always links by direct `content` URL of the newest upload" (no delete). Delete the second duplicate too, and delete the spike comment (`DELETE /rest/api/2/issue/$SANDBOX/comment/<commentId>`).

**Step 4:** Record all three outcomes (accumulate-confirmed?, link-renders?, delete-allowed?) in spike-notes with HTTP codes. Commit: `docs(plans): spike A results — attachment semantics`.

---

### Task 2: Spike B — PDF render of the dossier

**Files:** Modify: `docs/plans/2026-07-31-spike-notes.md`.

**Step 1:** Find an existing dossier (`find ~/.claude/recon -name dossier.html ! -path "*/runs/*"`); if none, use `$REPO/recon/skills/recon-report/template.html`.

**Step 2:**

```bash
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  --headless --disable-gpu --print-to-pdf=/tmp/dossier-spike.pdf --no-pdf-header-footer \
  "file://<path-to-dossier.html>"
open /tmp/dossier-spike.pdf
```

**Step 3: Decide and record.** PDF is **adopted** iff: renders without clipped sections/broken layout AND file size stays under ~5 MB with embedded exhibits. If adopted → the ticket attachment is `recon-dossier-<TICKET>.pdf` **instead of** the HTML (Jira previews PDF inline; HTML forces download). If not → attach the HTML. Record the decision as `PDF: adopted|rejected — <reason>`; every later task that says "(PDF variant)" follows this decision. Commit: `docs(plans): spike B result — PDF render decision`.

---

### Task 3: `package-artifacts.sh` — bundle rail

**Files:**
- Create: `recon/scripts/package-artifacts.sh`
- Fixture: `~/.claude/recon/ZZZ-999` (temp)

**Step 1: Write the failing assertions.** Build the fixture, then run the script (doesn't exist yet → fails):

```bash
mkdir -p ~/.claude/recon/ZZZ-999/{triage/jira,report,runs/20260101-000000}
echo "y: 1" > ~/.claude/recon/ZZZ-999/triage/triage.yaml
echo "{}"  > ~/.claude/recon/ZZZ-999/triage/ticket.json
echo "<html/>" > ~/.claude/recon/ZZZ-999/report/dossier.html
echo "old" > ~/.claude/recon/ZZZ-999/runs/20260101-000000/stale.txt
echo "m: 1" > ~/.claude/recon/ZZZ-999/meta.yaml
bash "$REPO/recon/scripts/package-artifacts.sh" ZZZ-999
```

Expected now: `No such file or directory`.

**Step 2: Implement**

```bash
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
DIR="$HOME/.claude/recon/$TICKET"
[ -d "$DIR" ] || { echo "no workspace: $DIR" >&2; exit 2; }

OUT="${RECON_BUNDLE_DIR:-${TMPDIR:-/tmp}}/recon-artifacts-$TICKET.zip"
rm -f "$OUT"
mkdir -p "$DIR/triage/jira"
MANIFEST="$DIR/triage/jira/bundle-manifest.txt"
: > "$MANIFEST"

while IFS= read -r f; do
  rel="${f#"$DIR"/}"
  case "$rel" in
    runs/* | triage/jira/bundle-manifest.txt) continue ;;
  esac
  size=$(wc -c < "$f" | tr -d ' ')
  printf '%s %s\n' "$size" "$rel" >> "$MANIFEST"
done < <(find "$DIR" -type f ! -path "$DIR/runs/*" | LC_ALL=C sort)

[ -s "$MANIFEST" ] || { echo "no artifacts to bundle: $DIR" >&2; exit 2; }

(cd "$DIR" && cut -d' ' -f2- "$MANIFEST" | zip -q -X "$OUT" -@)
echo "MANIFEST: $MANIFEST ($(grep -c . "$MANIFEST") files)"
echo "ZIP: $OUT ($(wc -c < "$OUT" | tr -d ' ') bytes)"
```

`chmod +x recon/scripts/package-artifacts.sh`.

**Step 3: Verify against the fixture**

```bash
bash "$REPO/recon/scripts/package-artifacts.sh" ZZZ-999
unzip -l "${TMPDIR:-/tmp}/recon-artifacts-ZZZ-999.zip"
cat ~/.claude/recon/ZZZ-999/triage/jira/bundle-manifest.txt
```

Expected: MANIFEST + ZIP lines print; zip lists `meta.yaml`, `triage/triage.yaml`, `triage/ticket.json`, `report/dossier.html` and **not** `runs/…` nor `bundle-manifest.txt`; manifest has 4 lines (size + path). Re-run the script — output identical (idempotent). Then `rm -rf ~/.claude/recon/ZZZ-999`.

**Step 4: Commit** — `feat(scripts): package-artifacts.sh delivery-bundle rail`.

---

### Task 4: `attach-artifacts.sh` — replace-not-accumulate rail

**Files:**
- Create: `recon/scripts/attach-artifacts.sh`
- Uses: `$SANDBOX` from Task 0; adjust per Spike A results (if delete was 403, implement the recorded fallback instead of the delete loop).

**Step 1: Failing assertion** — `bash "$REPO/recon/scripts/attach-artifacts.sh" $SANDBOX /tmp/x.html` → `No such file or directory`.

**Step 2: Implement**

```bash
#!/bin/bash
# attach-artifacts.sh <TICKET-ID> <file>... — replace-not-accumulate (invariant 14).
# Deletes prior attachments named recon-*-<TICKET>.* on the issue, uploads the
# given files, writes triage/jira/attach-result.json (deleted ids + upload
# responses). Needs ~/.config/jira/env and python3. Run BEFORE posting the
# comment so [^filename] links resolve. Exit 0 ok, 1 API failure, 2 usage.
set -euo pipefail

TICKET="${1:?usage: attach-artifacts.sh <TICKET-ID> <file>...}"; shift
[ "$#" -ge 1 ] || { echo "usage: attach-artifacts.sh <TICKET-ID> <file>..." >&2; exit 2; }
case "$TICKET" in
  *[!A-Za-z0-9-]* | "") echo "invalid ticket id: $TICKET" >&2; exit 2 ;;
esac
for f in "$@"; do [ -f "$f" ] || { echo "no such file: $f" >&2; exit 2; }; done

set -a; . "$HOME/.config/jira/env"; set +a
HOST="${JIRA_HOST#https://}"; HOST="${HOST%/}"
DIR="$HOME/.claude/recon/$TICKET/triage/jira"; mkdir -p "$DIR"
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
  echo "deleted: $id HTTP $code"
  printf '%s %s\n' "$id" "$code" >> "$TMP/deleted.txt"
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
```

`chmod +x`.

**Step 3: Verify on the sandbox — the replace semantics are the test**

```bash
echo one > /tmp/recon-dossier-$SANDBOX.html
bash "$REPO/recon/scripts/attach-artifacts.sh" $SANDBOX /tmp/recon-dossier-$SANDBOX.html
echo two > /tmp/recon-dossier-$SANDBOX.html
bash "$REPO/recon/scripts/attach-artifacts.sh" $SANDBOX /tmp/recon-dossier-$SANDBOX.html
curl -sS -u "$JIRA_EMAIL:$JIRA_API_TOKEN" \
  "https://$HOST/rest/api/2/issue/$SANDBOX?fields=attachment" | \
  python3 -c 'import json,sys; print([a["filename"] for a in json.load(sys.stdin)["fields"]["attachment"]])'
```

Expected: second run prints one `deleted:` line + one `uploaded:` line; final attachment list contains exactly **one** `recon-dossier-$SANDBOX.html`. `attach-result.json` exists under `~/.claude/recon/$SANDBOX/triage/jira/`. Clean up: run the delete call for the remaining spike attachment and `rm -rf ~/.claude/recon/$SANDBOX` (spike workspace, not a real run).

**Step 4: Commit** — `feat(scripts): attach-artifacts.sh replace-not-accumulate rail`.

---

### Task 5: `verify-comment-shape.sh` — comment shape rail

**Files:**
- Create: `recon/scripts/verify-comment-shape.sh`
- Fixture: `~/.claude/recon/ZZZ-999`

**Step 1: Failing assertions.** Fixture: `triage.yaml` with two `  - title:` blocker entries, plus a **good** `comment.txt` (6 non-empty lines: header, 2 blocker lines like `*1. Design* — [~osman]: which layout ships?`, links line containing `[^recon-`, reply line, marker line `~recon-triage v0.7.0~`) and run the (missing) script.

**Step 2: Implement**

```bash
#!/bin/bash
# verify-comment-shape.sh <TICKET-ID> — invariant 13 as a rail.
# triage/jira/comment.txt must be exactly n+4 non-empty lines for n blockers
# in triage/triage.yaml: header, n one-line blockers ("*i. Title* — [~user]:
# … ?"), attachment-links line, reply-here line, marker line. Exit 0 clean,
# 1 shape violation, 2 missing inputs.
set -euo pipefail

TICKET="${1:?usage: verify-comment-shape.sh <TICKET-ID>}"
DIR="$HOME/.claude/recon/$TICKET"
C="$DIR/triage/jira/comment.txt"
Y="$DIR/triage/triage.yaml"
[ -f "$C" ] || { echo "no comment draft: $C" >&2; exit 2; }
[ -f "$Y" ] || { echo "no triage.yaml: $Y" >&2; exit 2; }

n=$(grep -c '^  - title:' "$Y" || true)
lines=$(grep -c . "$C" || true)
want=$((n + 4))
fail=0

[ "$lines" -eq "$want" ] || { echo "SHAPE: $lines non-empty lines, want $want (n=$n blockers + 4)"; fail=1; }

blocker_lines=$(grep -c '^\*[0-9][0-9]*\. ' "$C" || true)
[ "$blocker_lines" -eq "$n" ] || { echo "SHAPE: $blocker_lines blocker lines, want $n"; fail=1; }

while IFS= read -r l; do
  case "$l" in
    *'?') ;;
    *) echo "SHAPE: blocker line does not end in a question: ${l%% —*}"; fail=1 ;;
  esac
  case "$l" in
    *'[~'*) ;;
    *) echo "SHAPE: blocker line has no [~mention]: ${l%% —*}"; fail=1 ;;
  esac
done < <(grep '^\*[0-9][0-9]*\. ' "$C" || true)

grep -qF '[^recon-' "$C" || { echo "SHAPE: missing attachment-links line ([^recon-…])"; fail=1; }
grep -q '^~recon-triage v' "$C" || { echo "SHAPE: missing marker line"; fail=1; }

if [ "$fail" -eq 0 ]; then
  echo "shape: clean — $lines lines, $n blocker(s)"
else
  exit 1
fi
```

`chmod +x`.

**Step 3: Verify** — good fixture → `shape: clean — 6 lines, 2 blocker(s)`, exit 0. Then break it three ways and confirm exit 1 with the right SHAPE line each time: (a) add a 7th non-empty line, (b) strip the `?` from one blocker line, (c) remove the marker line. Restore between checks. `rm -rf ~/.claude/recon/ZZZ-999`.

**Step 4: Commit** — `feat(scripts): verify-comment-shape.sh comment rail (n+4)`.

---

### Task 6: `lint-workspace.sh` registry additions

**Files:** Modify: `recon/scripts/lint-workspace.sh:26-31` (the case patterns).

**Step 1: Failing assertion.** Fixture ZZZ-999 with `triage/jira/bundle-manifest.txt` (and `report/dossier.pdf` if Spike B adopted PDF); run lint → expect `VIOLATION` lines (that's the failing test).

**Step 2: Implement.** In the registry `case`:
- change line 27 to include the manifest: `triage/jira/comment.txt | triage/jira/post-result.json | triage/jira/attach-result.json | triage/jira/bundle-manifest.txt) ;;`
- (PDF variant) change line 31 to: `report/dossier.html | report/dossier.pdf) ;;`

**Step 3: Verify** — same fixture now lints `clean`; an unregistered `triage/jira/rogue.txt` still yields a VIOLATION. `rm -rf ~/.claude/recon/ZZZ-999`.

**Step 4: Commit** — `feat(scripts): register bundle-manifest (+ dossier.pdf) in workspace lint`.

---

### Task 7: recon-triage SKILL.md — schema, comment, gate, ordering

**Files:** Modify: `recon/skills/recon-triage/SKILL.md` (sections: Contract, workflow step 3 schema, workflow step 4 BLOCKED branch, Report, Reference).

**Step 1: Contract block (line ~13).** Add to Writes: `triage/jira/bundle-manifest.txt`. Add note: the delivery zip is staged in a temp dir by `package-artifacts.sh`, never inside the workspace. Extend "May invoke" with `recon:recon-report` (render-only, BLOCKED posting path). External side effects becomes: at most one Jira comment (create/edit) **plus the replacement of recon-owned attachments (`recon-*-<TICKET>.*`)** — both behind the single gate.

**Step 2: triage.yaml schema (step 3).** Replace the `blockers: []` line with:

```yaml
blockers: []          # each entry:
#  - title: "Updated design"            # ≤5 words, names the blocker
#    owner: osman                       # handle; resolve to accountId at post time
#    ask: "deliver the updated Onboarding design, or should I build to the attached PNG?"
#                                       # ONE sentence, ends in "?", rule-7 clean
#    detail:                            # rule-7 question pack — rendered ONLY in the dossier
#      state: "<where this blocker stands, dated>"
#      options: ["<user-observable outcome a>", "<user-observable outcome b>"]
#      evidence: ["<quote / file:line / HTTP status>"]
#      repro_ref: repro/exhibits/…      # when recon-repro ran
```

**Step 3: Rewrite the BLOCKED/NEEDS_INFO branch (step 4)** to this exact flow:

1. Build `triage.yaml` with structured blockers (rule 7 applies to `ask` and `detail` both; internal identifiers banned from `ask`).
2. If any blocker concerns observable UI → `recon:recon-repro` first (unchanged).
3. Invoke `recon:recon-report` in **render-only mode** → `report/dossier.html` (+ `report/dossier.pdf` under the PDF variant). No artifact publishing on this path.
4. Draft the comment — **exact shape, n+4 non-empty lines, generated from `triage.yaml` only**:

```
h2. Recon triage: <DISPOSITION> — <n> blockers (<d MMM>)

*1. <title>* — [~accountid:…]: <ask>
*…one line per blocker…*

Full detail, options, and evidence: [^recon-dossier-<TICKET>.<ext>] · [^recon-artifacts-<TICKET>.zip]
Reply here — answers on this ticket un-block the pipeline.
~recon-triage v<plugin_version from meta.yaml>~
```

No history, no stale-blocker narration, no technical values beyond what an ask needs — that all lives in the dossier. Split-scope proposals only inside an ask line ("…or split AC #5 to a follow-up?"). Save to `triage/jira/comment.txt`, then run `bash "<skill base dir>/../../scripts/verify-comment-shape.sh" <TICKET>` — fix and re-run until `shape: clean`.

5. Run `bash "<skill base dir>/../../scripts/package-artifacts.sh" <TICKET>` — quote its MANIFEST/ZIP lines.
6. **Gate (single, expanded):** AskUserQuestion shows the comment draft AND the attachment manifest (two filenames + sizes + bundle file count). Options: `Post to Jira now (comment + 2 attachments) / Edit first / Don't post`. One "post" answer authorizes both.
7. On "post": run `attach-artifacts.sh <TICKET> <dossier> <zip>` FIRST (so `[^…]` links resolve), then create/edit the comment (edit-vs-create per rule 9, unchanged). Save `post-result.json`. Then STOP.

**Step 4: Report + Reference sections.** Report `Wrote:` line gains `bundle-manifest.txt`; add `Shape: <verify-comment-shape.sh verdict line, verbatim>`. Reference: add one line — attachments are recon-owned when named `recon-*-<TICKET>.*`; they are replaced, never accumulated (`attach-artifacts.sh`).

**Step 5: Verify** — reread the diff: every new mechanical step names its script; no step leaves execution freedom to the model (design formula). Commit: `feat(triage): n+4 progressive-disclosure comment + attachment delivery path`.

---

### Task 8: recon-report — render-only mode + Blockers section

**Files:**
- Modify: `recon/skills/recon-report/SKILL.md`
- Modify: `recon/skills/recon-report/template.html`

**Step 1: template.html.** Read the template first; following its existing card/table idiom, add a **"Blockers & question packs"** section directly after the verdict/facts area, with an instruction comment + `«SLOT: blockers»` marker: one card per `triage.yaml` blocker — title, owner, the ask, then the `detail` pack (state; options as a list; evidence lines; repro exhibit link when `repro_ref` set). Empty blockers → the single word `None` (fixed-template rule: section always present).

**Step 2: SKILL.md.**
- Contract Writes: `report/dossier.html` (+ `report/dossier.pdf` under the PDF variant, produced via the exact headless-Chrome command from Spike B).
- Contract/External side effects: publishing is **skipped when invoked render-only by recon-triage** (delivery is the Jira attachment); on-demand runs still publish private.
- Slot map: add row `Blockers & question packs ← triage/triage.yaml blockers[] (title/owner/ask/detail)`.
- Reference line 72: replace "on-demand only" with: on-demand, **and auto-invoked render-only by recon-triage on the BLOCKED/NEEDS_INFO posting path**.

**Step 3: Verify** — template still has every original `«SLOT: …»` marker (`grep -c 'SLOT:' template.html` = old count + 1). Commit: `feat(report): blockers question-pack section + render-only mode`.

---

### Task 9: pipeline.md — state machine, invariants 13–14, registry, triggers

**Files:** Modify: `recon/docs/pipeline.md`.

**Step 1:** State machine: stage 1 exit becomes `BLOCKED/NEEDS_INFO → repro? → dossier (render-only) → package → gate → attach + comment → STOP`; stage D entry becomes `on demand after any STOP, or auto (render-only) from stage 1's BLOCKED posting path`.

**Step 2:** Invariants — append:

- **13. Comment shape is mechanical.** A triage comment is exactly n+4 non-empty lines (header, n one-line blockers `*i. Title* — [~mention]: ask?`, attachment-links line, reply line, marker). Verified by `recon/scripts/verify-comment-shape.sh` before the gate. Detail lives in the dossier, never the comment.
- **14. Attachments replace, never accumulate.** Files named `recon-*-<TICKET>.*` are recon-owned; `attach-artifacts.sh` deletes stale ones before uploading, and runs BEFORE the comment posts so `[^…]` links resolve. Same authority as invariant 6: only behind the in-session gate.

**Step 3:** Artifact registry — add rows:

| File | Producer | Consumers | Notes |
|---|---|---|---|
| `triage/jira/bundle-manifest.txt` | `package-artifacts.sh` | audit, gate display | size + rel path per bundled file; zip itself staged in temp, contents = this workspace |
| `report/dossier.pdf` *(PDF variant)* | recon-report (render-only) | Jira attachment | print of dossier.html |

**Step 4:** Trigger table — add: `BLOCKED delivery | disposition ∈ {BLOCKED, NEEDS_INFO} and posting path entered | recon-report render-only → package-artifacts.sh → gate → attach-artifacts.sh → comment` and update the Dossier row ("never automatic" → "auto render-only on the BLOCKED posting path; on demand otherwise"). Rails table: add `comment shape (verify-comment-shape.sh)` and `attachment replace (attach-artifacts.sh)` under rails.

**Step 5:** Commit — `docs(pipeline): invariants 13-14, blocked-delivery stage flow`.

---

### Task 10: workspace-index.md + README flow

**Files:** Modify: `recon/docs/workspace-index.md`, `README.md`.

**Step 1:** workspace-index: add entries for `triage/jira/bundle-manifest.txt` (+ `report/dossier.pdf` variant) mirroring the registry notes.

**Step 2:** README mermaid: BLOCKED branch now flows `triage -->|BLOCKED| repro? --> dossier --> gate{post?} --> attach --> comment`; keep the rails-blue/judgment-yellow/gate-red convention.

**Step 3:** Commit — `docs: workspace index + README flow for attachment delivery`.

---

### Task 11: ADR 0001 — REST API over MCP

**Files:** Create: `recon/docs/decisions/0001-jira-rest-api-over-mcp.md`.

**Step 1:** Write the ADR with the exact content from the design doc Section C (status: accepted, date 2026-07-31): decision, three grounds (determinism/byte-exact artifacts; MCP capability gaps — comment-edit + attachment CRUD; portability/headless), revisit triggers, considered-and-rejected list (ADF/v3 expand sections, GitHub Pages, Google Drive, Confluence hub — with one-line reasons each).

**Step 2:** Commit — `docs(adr): 0001 jira rest api over mcp`.

---

### Task 12: Version bump, push, sync clones, activate

**Step 1:** `recon/.claude-plugin/plugin.json` version → `0.7.0`. Commit `chore(plugin): v0.7.0` and push `origin master`.

**Step 2:** Sync the marketplace clone: `git -C ~/.claude/plugins/marketplaces/recon-plugin pull`.

**Step 3:** Activate per change protocol (pipeline.md §Change protocol): copy `recon/` to `~/.claude/plugins/cache/recon-plugin/recon/0.7.0/`, repoint the `recon@recon-plugin` entry (installPath, version, gitCommitSha) in `~/.claude/plugins/installed_plugins.json`. Do **not** delete the 0.6.0 cache dir.

**Step 4:** Verify: `python3 -c 'import json; d=json.load(open("'$HOME'/.claude/plugins/installed_plugins.json")); print(d)' | grep -o '0\.7\.0'` shows the new version, and the cache dir contains `scripts/package-artifacts.sh`.

---

### Task 13: Live validation — one real BLOCKED run

**Step 1:** In a **fresh session**, run `/recon:recon-triage ATT-5107` (known BLOCKED; answers may have arrived — any disposition is fine, the delivery path is what's under test; if it comes out READY, pick another blocked ticket with Doruk).

**Step 2:** Verify against the ticket in the browser: comment is n+4 lines, one line per blocker with mention + ask; the two `[^recon-…]` links resolve; prior marker comment was EDITED not duplicated; attachments show exactly one dossier + one zip (no accumulation from re-runs); dossier's Blockers section carries the question packs.

**Step 3:** Record the run's `Lint:` and `Shape:` report lines in `docs/plans/2026-07-31-spike-notes.md` as the acceptance evidence. Commit — `docs(plans): v0.7.0 live validation evidence`.
