# Spike notes — v0.7.0 comment + delivery redesign

## Task 0 — target ticket

- Doruk's decision (2026-07-31): **no sandbox ticket**. All spikes run against the real
  blocked ticket **ATT-5107** (https://appier.atlassian.net/browse/ATT-5107).
- Low-noise constraints derived from that decision:
  - The `[^filename]` rendering check EDITS the existing recon marker comment
    (append link line → verify via `expand=renderedBody` → restore original body).
    Never a second comment (plugin rule 9: one marker comment per ticket).
  - Deletes touch ONLY attachments matching `recon-*-ATT-5107.*`. Colleagues' real
    attachments must be listed before/after and proven untouched.
  - All spike attachments are removed at the end of Task 1.

## Task 1 — Spike A: attachment semantics

Run 2026-07-31 against ATT-5107 (Jira REST API v2, API-token basic auth).

- **accumulate-confirmed: yes** — uploading `recon-dossier-ATT-5107.html` twice (both POSTs
  returned HTTP 200) produced two coexisting attachments with the same filename:
  ids **884412** and **884413**. Jira does not replace same-named attachments; v0.7.0's
  re-run flow must delete prior recon attachments explicitly before uploading.
- **link-renders: yes** — appended `Link test: [^recon-dossier-ATT-5107.html]` to the recon
  marker comment (id 2187653) and fetched it with `expand=renderedBody`. The wiki syntax
  rendered as a real anchor:

  ```html
  <a href="/rest/api/3/attachment/content/884412" title="recon-dossier-ATT-5107.html attached to ATT-5107" data-attachment-type="file" data-attachment-name="recon-dossier-ATT-5107.html" ... rel="noreferrer">recon-dossier-ATT-5107.html<sup><img class="rendericon" .../></sup></a>
  ```

  Caveat: with two same-named attachments present, the link resolved to the **older**
  one (884412), not the newest — another reason delete-then-upload must precede the
  comment link on re-runs.
- **delete-allowed: yes** — `DELETE /rest/api/2/attachment/884412` → **204**;
  `DELETE /rest/api/2/attachment/884413` → **204**. The API token may delete its own
  uploads; no 403 encountered.
- **restore-verified: yes** — marker comment 2187653 was PUT back to its saved original
  body (1997 chars) and re-fetched; python3 equality check confirmed a byte-exact match.
- **before/after attachment parity: confirmed** — the (filename, id) set is identical
  before and after the spike: `att-5107-thumbnail-crop-evidence.png` (883764) and
  `Screenshot 2026-07-27 at 15.21.22.png` (882376). Colleagues' attachments untouched;
  both spike uploads removed.

Note: the live marker comment ends in `~recon-triage v0.4.0~` (the plan text said
v0.6.0); it is the ticket's single recon marker comment either way.

## Task 2 — Spike B: PDF render decision

Run 2026-07-31, local only (no Jira calls).

- **Fixture rendered:** `~/.claude/recon/ATT-5047/report.html` — a real **filled** dossier
  (title "ATT-5047 — Recon Dossier", 1.1 MB, 5 embedded JPEG exhibits as `data:` URIs).
  No workspace contains a file literally named `dossier.html`; ATT-5047's `report.html`
  is the same artifact under the older filename, and it is a current-run file (not under
  `runs/`). The unfilled template fallback was not needed.
- **Command that worked** (exact command from the plan):

  ```bash
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
    --headless --disable-gpu --print-to-pdf=<out>.pdf \
    --no-pdf-header-footer "file://$HOME/.claude/recon/ATT-5047/report.html"
  ```

- **Result of the exact command:** 6 pages, 538 KB. Everything *visible* renders cleanly —
  light "paper" theme (headless Chrome prints the light scheme), verdict chips, seven-slot
  table, stage timeline, evidence tables, callouts all intact; page breaks land readably.
  **But the dossier's five `<details class="fold">` sections print collapsed**, so the PDF
  contains only their one-line summaries and silently drops: all 5 exhibit screenshots,
  the triage six-checks evidence table, the discovery code excerpts, the six Gherkin
  scenarios, and the routing rules table. That is most of the dossier's evidentiary content.

- **`PDF: rejected — the exact Chrome command drops all exhibit screenshots and four other
  evidence sections (they live inside collapsed `<details>` folds, which print closed);
  missing content fails the adoption rule. Size and visible-layout quality were fine
  (538 KB, 6 pages, no broken sections among what did print).**

- Secondary data point (informational, does not change the decision): a variant with
  `open` force-added to every `<details class="fold">` prints everything — 12 pages,
  1.49 MB, all 5 exhibits full-width and readable — with only minor right-edge clipping
  of a few wide `<pre>` lines (Gherkin comments, decree intent-check paths), since
  `overflow-x: auto` blocks cannot scroll on paper. Adopting PDF would therefore require
  mutating the dossier HTML (or a print stylesheet + template change forcing folds open
  and wrapping code), not "this exact Chrome command" — out of scope for v0.7.0.
  **Consequence for later tasks: skip the "(PDF variant)" branches; the ticket gets the
  HTML dossier.**
