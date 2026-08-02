# Render the Jira comment from triage.yaml

> Generate comment.txt from triage.yaml by script — the model never writes it

- **Status:** shipped (v0.9.0) — implemented 1 Aug 2026 (`recon/scripts/render-comment.sh`
  + `triage-tools.py`, `owner_account_id` in the schema, posting-path steps 1/4/6
  rewritten; verified byte-identical against the comment actually posted to
  ATT-5107). The `judgment.yaml` dossier variant remains open.
- **Priority:** P2
- **Theme:** determinism rail
- **Origin:** ATT-5107 triage run, 1 Aug 2026 — the comment passed
  `verify-comment-shape.sh` first try, but the model still hand-transcribed every
  ask from yaml to comment, and the shape checker cannot see transcription drift.

## Problem

The posting path already declares the comment is "generated from `triage.yaml`
ONLY" — but "generated" means the model re-types it while re-reading a spec
("EXACT shape, n+4 non-empty lines…"). `verify-comment-shape.sh` catches structural
errors; it cannot catch the content errors transcription invites.

## Before (today)

A paraphrase that passes the shape rail:

```
*2. Video hosting* — [~accountid:712020:58e7d6f5-…]: could you clarify the hosting
situation for the new video when you get a chance?
```

`shape: clean` (line count right, ends in `?`) — but the ask lost its substance
(who uploads; video id + hash or CDN URL). The yaml says one thing, the ticket now
asks another, and no script compares them. Other unpreventable slips: a stray
flourish line, a display name instead of an accountId, a stale version suffix.

## After (proposed)

```
$ bash recon/scripts/render-comment.sh ATT-5107
rendered: ~/.claude/recon/ATT-5107/triage/jira/comment.txt (7 lines, 3 blockers)
```

producing, byte-for-byte from `triage.yaml` + `meta.yaml`, exactly what the
1 Aug run posted:

```
h2. Recon triage: BLOCKED — 3 blocker(s) (1 Aug)

*1. Updated design* — [~accountid:712020:738fd3d2-…]: deliver the updated design…
*2. Video hosting* — [~accountid:712020:58e7d6f5-…]: who uploads the new welcome…
*3. Tracking events undefined* — [~accountid:712020:738fd3d2-…]: which exact…

Full detail, options, and evidence: [^recon-dossier-ATT-5107.html] · [^recon-artifacts-ATT-5107.zip]
Reply here — answers on this ticket un-block the pipeline.
~recon-triage v0.7.0~
```

Heading date from `meta.yaml started`, version from `plugin_version`, accountIds
from `blockers[].owner` (resolved ids stored in the yaml at triage time). The
model's freedom in comment *execution* drops to zero — per pipeline.md's design
formula, exactly the defect class this repo says to eliminate.
`verify-comment-shape.sh` stays as a regression check on the renderer itself.

## Implementation sketch

- New `recon/scripts/render-comment.sh` (yaml + meta in, comment.txt out).
- `blockers[].owner` schema gains `owner_account_id:` so rendering needs no lookups
  (pairs with [owner-resolution-order](../../0.14.0/owner-resolution-order/README.md)).
- Posting path step 4 becomes: run renderer → show output at the gate. The `Edit
  first` loop edits `triage.yaml`, then re-renders — never `comment.txt` directly.
- Delete the hand-drafting spec from SKILL.md step 4 (the shape stays documented in
  the script).
- Same pattern later for the dossier: template filled by script, model contributes
  only `judgment.yaml` (headline + lede).

## Open questions

- Edit-vs-create (marker detection) stays in the skill or moves into a
  *post-comment.sh*? Moving it makes the whole delivery leg mechanical.
- Depends on: [validate-triage-yaml](../../0.14.0/validate-triage-yaml/README.md) — rendering
  garbage-in is pointless; validate first.
