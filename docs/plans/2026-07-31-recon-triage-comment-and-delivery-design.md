# Recon triage — progressive-disclosure comments & artifact delivery (design)

Date: 2026-07-31
Status: approved (Doruk, this session)
Target version: v0.7.0

## Problem

Three improvement areas for the `/recon:recon-triage` flow:

1. **Jira comments are too long and dense.** The ATT-5107 BLOCKED comment (v0.6.0) is 15
   lines where each blocker carries its full history, options, technical values, and
   proposals inline. Root cause is structural: rule 7's concreteness standard forces all
   detail *into* the comment because the comment is the only surface colleagues can see.
2. **Jira MCP vs REST API** was an open question with no recorded decision.
3. **Artifacts** (dossier, yaml/md files) live only on the operator's machine
   (`~/.claude/recon/<TICKET>/`); colleagues mentioned in the comment cannot reach them.

Decisions were made via clarifying questions:
- Audience for deep detail: **anyone on the Jira ticket** (PMs, designers, BE), zero setup.
- Deliverable set: **dossier + raw artifact files (yaml/md)**, linked from the ticket.
- Link mechanism: **Jira attachments** — dossier + one `recon-artifacts.zip`.
- Blocker line depth: **title + mention + one-line ask**.
- MCP: **no strong driver** — record the decision so it stops resurfacing.

## Section A — Comment schema (progressive disclosure, layer 1)

The BLOCKED/NEEDS_INFO comment becomes mechanical in shape: **n + 4 lines**, generated
from `triage.yaml`, nothing else permitted.

```
h2. Recon triage: BLOCKED — 3 blockers (31 Jul)

*1. Updated design* — [~osman]: deliver the updated Onboarding design, or should I build to the attached PNG?
*2. Video hosting* — [~barim]: who uploads the video, and what are the resulting id and hash?
*3. AC #5 event spec* — [~osman]: exact event names and properties — or split AC #5 to a follow-up?

Full detail, options, and evidence: [^recon-dossier-ATT-5107.html] · [^recon-artifacts-ATT-5107.zip]
Reply here — answers on this ticket un-block the pipeline.
~recon-triage v0.7.0~
```

Rules:
- Each blocker is exactly one line: bold title, `[~accountid]` mention, one-sentence ask
  ending in a question mark.
- No history, no state narration, no stale-blocker notes, no technical values beyond what
  the ask needs — all of that moves to the dossier.
- Rule 7's ban on internal identifiers still applies to the ask line. The full
  concreteness pack (numbered repro steps from a stated start state, concrete entity
  names, before/after, options as user-observable outcomes) now applies to the
  **dossier's question packs**, not the comment.
- Split-scope proposals live inside the ask line when they fit ("…or split AC #5 to a
  follow-up?"), otherwise in the dossier.
- Edit-not-append and the `~recon-triage vX.Y.Z~` marker are unchanged.

Single source of truth: `triage.yaml` blocker entries grow structure; both the comment
and the dossier render from it (dossier keeps its NO NEW FACTS rule).

```yaml
blockers:
  - title: "Updated design"
    owner: osman              # display handle; resolved to accountId at post time
    ask: "deliver the updated Onboarding design, or should I build to the attached PNG?"
    detail:                   # rule-7 question pack — rendered only in the dossier
      state: "<where this blocker stands, with dates>"
      options: ["<user-observable outcome a>", "<user-observable outcome b>"]
      evidence: ["<quote/file:line/HTTP status>"]
      repro_ref: repro/exhibits/…   # when recon-repro ran
```

## Section B — Artifact delivery (layers 2 and 3)

On BLOCKED/NEEDS_INFO with posting approved, attach two files to the ticket, linked from
the comment:

1. **`recon-dossier-<TICKET>.html`** — `recon-report` gains a **blocked-run mode**:
   renders whatever stage dirs exist (often just `triage/`, maybe `repro/`), with a new
   *Blockers & question packs* section at the top. This changes recon-report from
   on-demand-only (v0.4.0) to auto-invoked on the BLOCKED posting path. It stays
   on-demand for every other use.
2. **`recon-artifacts-<TICKET>.zip`** — new plugin script `package-artifacts.sh` zips the
   workspace stage dirs (everything except `runs/`), printing a deterministic file list.

Mechanics (all rails):
- New `attach-artifacts.sh`: deletes prior attachments matching `recon-*-<TICKET>.*`,
  then uploads the new pair — **replace-not-accumulate**, mirroring edit-not-append.
- Attachments upload **before** the comment posts so `[^filename]` links resolve.
- The single approval gate expands to cover the package: AskUserQuestion shows the
  comment draft **plus the attachment manifest**; one "post" answer authorizes
  comment + attachments together. No posting path splits into multiple gates.
- Workspace contract: zip build + attach results stay under `triage/jira/`;
  `report/dossier.html` remains recon-report's declared artifact. `lint-workspace.sh`
  and pipeline.md's artifact registry get the new entries.

Ordering on a BLOCKED run:
triage checks → (recon-repro if UI blocker) → recon-report dossier → zip → gate →
attach → comment.

## Section C — ADR: REST API stays, MCP rejected

Write `recon/docs/decisions/0001-jira-rest-api-over-mcp.md`:

- **Decision:** the pipeline keeps Jira REST API v2 via curl rails.
- **Grounds:**
  1. *Determinism* — rails require byte-exact saved responses (`ticket.json`,
     `post-result.json`); MCP tool results flow through model context and would have to
     be transcribed by the model — the exact slop vector the pipeline eliminates.
  2. *Capability* — Atlassian's MCP lacks comment-edit and attachment upload/delete,
     both load-bearing for the marker and replace rules.
  3. *Portability* — OAuth-based MCP may be absent in headless runs and adds
     per-coworker setup without removing the env-file need.
- **Revisit triggers:** Atlassian MCP ships comment-edit + attachment CRUD; or API-token
  creation becomes a real onboarding blocker for coworkers.
- Also records considered-and-rejected: API v3/ADF `expand` collapsible sections
  (rejected in favor of attachment-based disclosure), GitHub Pages (public exposure /
  wrong audience), Google Drive (new credential system, weak determinism), Confluence
  page hub (best rendering, biggest build — could be revisited later).

## Section D — Rollout and spikes

Version **v0.7.0** (behavior change). Touched surfaces:
- `recon/skills/recon-triage/SKILL.md` — comment schema, triage.yaml blocker structure,
  gate scope, BLOCKED-path ordering (invoke recon-report + package + attach).
- `recon/skills/recon-report/SKILL.md` — blocked-run mode, Blockers & question packs
  section.
- `recon/docs/pipeline.md` — two new invariants: comment shape is n+4 lines;
  attachments replace-not-accumulate.
- New scripts: `recon/scripts/package-artifacts.sh`, `recon/scripts/attach-artifacts.sh`.
- `recon/scripts/lint-workspace.sh` — registry additions.
- `README.md` — flow diagram update.
- `recon/docs/decisions/0001-jira-rest-api-over-mcp.md` — new.

Spikes before implementation (~10 min each, against a sandbox ticket):
1. Attachment delete permissions with the operator token
   (`DELETE /rest/api/2/attachment/{id}`).
2. `[^filename]` attachment-link rendering in Jira Cloud comments.
3. Headless-Chrome PDF render of the dossier — if clean, attach the **PDF instead of the
   HTML** (Jira previews PDFs inline; attached HTML forces download-then-open).
