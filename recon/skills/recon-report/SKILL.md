---
name: recon-report
description: Render a Recon workspace as a self-contained HTML dossier. Use when a run finishes, a Jira delivery path needs render-only output, or someone asks for a report, dossier, or shareable summary.
---

# Recon Report

Turns the current-run artifacts of `$RECON_ROOT/<TICKET>/` into one designed, self-contained HTML page — verdict chips, seven-slot facts, blockers & question packs, stage-by-stage narrative, evidence tables, screenshot exhibits, gate decisions, handoff. On a host with `publish_once`, an on-demand run may publish the page as a **private** artifact the user can choose to share; every other run returns the file on disk. When the user explicitly supplies an absolute task-packet store config, the same run also saves the complete current workspace through the delivery rail in `../../scripts/store-dossier.sh`.

## Host setup

Before the first path or tool action, read `../../docs/hosts.md`, then run
`reconctl.sh start base` once. Retain its root, host, surface, capabilities, and
preflight snapshot for the run. A failed preflight is a hard STOP. Use
`publish_once` only when it is declared available; otherwise return the local
dossier path as render-only. Later rails still detect current runtime identity.

## Contract

- **Input:** ticket ID (precondition: current run exists — root `meta.yaml` + `triage/triage.yaml`); optionally, an explicit absolute task-packet store config path
- **Reads:** current-run artifacts in `$RECON_ROOT/<TICKET>/` (never `runs/`), the shipped `template.html`
- **Writes:** ONLY inside `$RECON_ROOT/<TICKET>/report/` — `dossier.html`. Create the directory before writing. Anything else fails `lint-workspace.sh`
- **External side effects:** only when on-demand mode and `publish_once` are both active, publishes `report/dossier.html` as a private artifact visible only to the user. When and only when an absolute store config was explicitly supplied, saves the complete current run under `stages/10-recon/runs/vN/` and returns its actual locations. Every other path renders and STOPS with no publishing or storage. In every mode this skill never posts to Jira and never touches the repo.

---

## ⚠️ CRITICAL: Rules

1. **NO NEW FACTS.** The dossier is a *view*, not a re-derivation. Every claim, number, link, and caption MUST trace to a workspace artifact. You may compress wording; you MUST NOT add findings, opinions, severity judgments, or links that no artifact contains. A template slot with no source artifact reads `None` or `not run — <reason from artifacts>` — never invented content. Judgment is confined to exactly two places: the headline sentence and the lede.
2. **Fixed template.** Fill the `«SLOT: …»` markers of the `template.html` shipped next to this SKILL.md. Do NOT redesign, restyle, reorder sections, or drop the instruction comments' constraints. Same seven facts slots, same order, every dossier.
3. **NEVER read `runs/`.** The dossier documents the current run only. Prior runs are invisible (pipeline invariant 3).
4. **Pin code links mechanically.** GitHub links use the commit from `route/routing.yaml` `evidence.repo_commit`. If that field is absent, write file paths as plain `code` (or `.pathcopy` buttons) with the footer noting `unpinned` — NEVER guess a SHA or link to a branch.
5. **Self-contained page.** Screenshots are embedded as `data:` URIs (external hosts are blocked by the artifact CSP). Recompress each PNG to JPEG before embedding: `sips -s format jpeg -s formatOptions 72 --resampleWidth 1600 <in>.png --out <tmp>.jpg` (fall back to the raw PNG only when `sips` is unavailable and the file is < 300 KB). Keep the final page under ~3 MB.
6. **Private when publishing is available.** On-demand with `publish_once`: publish, print the URL, stop. Sharing the link is the user's action — never post the URL to Jira or anywhere else. Without that capability, or in explicit render-only mode, publishing is SKIPPED entirely — there is no URL; the local file is the result. On a BLOCKED/NEEDS_INFO or approved READY delivery path, the Jira attachment (uploaded behind that path's delivery gate) is the delivery.
7. **BLOCKED runs get dossiers too.** Chips show the real disposition; discovery/repro/gate sections read `not run` with the reason; the handoff block shows the re-entry instruction. Do not skip the report because the pipeline stopped early. On BLOCKED/NEEDS_INFO runs the Blockers & question packs section is the dossier's lead content, rendered from the structured `blockers[]` in `triage.yaml` — the layer of detail the short Jira comment points readers to.
8. **Verify generated evidence before rendering it.** When `repro/repro.md`
   exists, require `verify-repro.sh` to print `verify: clean`. When a routed
   Discovery package exists, run `verify-discovery.sh` in `post-gate` mode if
   `gate.yaml` exists, otherwise `pre-gate`. A verifier failure is an artifact
   defect to report and stop on, never content to beautify into a dossier.
9. **Storage is explicit and separate.** Never infer a store from host, Jira,
   a vault, repository files, or prior runs. If the user supplied an absolute
   store config, run `store-dossier.sh` after the dossier and workspace lint
   succeed. A storage failure is the report outcome; never fall back to a local
   success claim. Saving does not publish an artifact, post to Jira, or grant a
   later delivery approval.

---

## Slot map (template ← artifacts)

| Template slot | Source (verbatim facts) |
|---|---|
| TICKET, Jira URL | `meta.yaml` ticket + `JIRA_HOST` from `~/.config/jira/env` |
| Verdict chips | `triage/triage.yaml` disposition · `repro/repro.md` frontmatter `reproduced` · `route/routing.yaml` route/matched_rule · `discovery/gate.yaml` approved |
| headline + lede | judgment (rule 1) — facts only from `triage.yaml`/`discovery.md` |
| Seven facts: Verdict / Where / Reuse / Scope / Decided / Open / Next | `triage/triage.yaml` + repro outcome · root-cause `file:line` from `discovery/discovery.md` · `route/routing.yaml` `evidence.reuses_existing_contract` · `evidence.blast_radius` · `discovery/gate.yaml` resolutions · open items/findings · route + verbatim handoff |
| repo_commit link, footer | `route/routing.yaml` `evidence.repo_commit`, `meta.yaml` plugin_version + started |
| Blockers & question packs | `triage/triage.yaml` `blockers[]` — each entry's title / owner / one-line ask / `detail` pack (state · options as a list · typed evidence entries: each entry's `text` verbatim, labeled by its `kind` · `repro_ref` → link to the repro exhibit); empty → `None` |
| Pipeline stages 0–5 | `meta.yaml` (step 0), each stage's directory; a missing stage directory ⇒ `not run — <reason>` |
| Six-checks table | `triage.yaml` checks + matching `evidence:` lines, one row each |
| Cross-checks table | `triage.yaml` `status_drift`, `stale_blocker_note` |
| Discovery body + excerpts | `discovery/discovery.md`, `route/routing.yaml` (incl. `rules_not_matched` if quoted) |
| Repro env + exhibits | `repro/repro.md` frontmatter `start_state` + numbered steps as captions; `repro/exhibits/<n>-<slug>.png` in step order |
| Repro session pointer | `repro/session/` presence — one line naming `viewer.html` + `session.webm` and where they travel (the attached `recon-artifacts-<TICKET>.zip` on the posting path; the workspace path otherwise); no bundle → omit the line |
| Decision cards | `discovery/gate.yaml` |
| Handoff block | `route/routing.yaml` `handoff:` — VERBATIM (it is data, never recomposed), or the BLOCKED re-entry line |

## Modes

- **On-demand** (default — the user asked for a report/dossier/shareable summary): run workflow steps 1–7. Save only when the user supplied a store config. Publish only when `publish_once` is available; otherwise the run ends with the rendered local file or stored receipt.
- **Render-only** (auto-invoked by `recon:recon-triage` on its BLOCKED/NEEDS_INFO posting path or by `recon:recon-discovery` after an approved READY package): run workflow steps 1–5 — verify workspace, read artifacts, prepare exhibits, fill the template, write + lint — then STOP unless that caller also passed an explicit store config. SKIP host publication: no private artifact, no Jira mutation. The caller separately uploads `report/dossier.html` behind its own delivery gate. Report `Rendered (render-only): <path> (<size>)` plus the Lint line and, only when explicitly requested, the storage receipt.

## Workflow

1. **Verify the workspace.** Root `meta.yaml` + `triage/triage.yaml` must exist. If missing, stop: render the Triage invocation with `reconctl.sh invocation recon.triage <TICKET>` and tell the user to run it first — never reconstruct from memory or `runs/`. If repro evidence exists, run `verify-repro.sh`. If `discovery/discovery.md` and `route/routing.yaml` exist, run `verify-discovery.sh` in `post-gate` mode when `discovery/gate.yaml` exists and `pre-gate` otherwise. Require every applicable rail to print `verify: clean` before continuing.
2. **Read every current-run artifact** across the stage directories (registry in `../../docs/pipeline.md`, and each workspace carries its own `index.md`). A stage ran ⇔ its directory exists.
3. **Prepare exhibits** per rule 5 (use the session scratchpad for temp JPEGs).
4. **Fill the template** slot by slot per the map. Strip the instruction comments (`«SLOT: …»` markers and the leading file comment) from the output.
5. **Write** `$RECON_ROOT/<TICKET>/report/dossier.html`, then run `bash "<skill base dir>/../../scripts/lint-workspace.sh" <TICKET>` and fix any violation.
6. **Store when explicitly requested.** If no absolute store config was supplied, skip this step without probing for one. Otherwise run the delivery rail with the current workspace root as `--source` and retain its one-line JSON receipt verbatim:

   ```bash
   bash "<skill base dir>/../../scripts/store-dossier.sh" \
     --store <absolute-store-config.json> \
     --ticket <TICKET> \
     --source "$RECON_ROOT/<TICKET>"
   ```

   Require exit 0 and a receipt with the stored run plus primary, run-record,
   and snapshot locations. On any failure, report it and STOP; do not print a
   successful persistence line. The full command and receipt contract live in
   `../../docs/storage.md`.
7. **Publish when available** — on-demand mode ONLY. If `publish_once` is unavailable, STOP after the applicable storage step and print the render-only report. Otherwise publish as an artifact: title `<TICKET> — Recon Dossier`, favicon `🗂️` (keep both stable across redeploys of the same ticket). If the environment requires a prerequisite skill before publishing, load it first. After a successful publish, log `bash "<skill base dir>/../../scripts/log-event.sh" <TICKET> dossier_published` (invariant 16).

## Report

On-demand with a successful publish, print:

```
Wrote: $RECON_ROOT/<TICKET>/report/dossier.html (<size>)
Verify: <applicable repro/discovery verifier verdict lines, verbatim>
Lint: <lint-workspace.sh verdict line, verbatim>
Published: <artifact URL> (private — sharing is your call)
Coverage: <stages included> · <n> exhibits · commit <sha|unpinned>
Stored: <store-dossier.sh JSON receipt verbatim, only when explicitly requested>
```

Without `publish_once`, or in explicit render-only mode (including either Jira delivery path), print — no Published line, nothing was published:

```
Rendered (render-only): $RECON_ROOT/<TICKET>/report/dossier.html (<size>)
Verify: <applicable repro/discovery verifier verdict lines, verbatim>
Lint: <lint-workspace.sh verdict line, verbatim>
Stored: <store-dossier.sh JSON receipt verbatim, only when explicitly requested>
```

---

## Reference

- Whole-chain spec (stages, invariants, artifact registry, trigger table): `../../docs/pipeline.md` relative to this skill's base directory. On conflict, this SKILL.md wins.
- Two ways in: on-demand (the user asks — always render, publish only with `publish_once`), AND auto-invoked in render-only mode by `recon:recon-triage` on its BLOCKED/NEEDS_INFO delivery path or `recon:recon-discovery` after an approved READY package — there the delivery is the Jira attachment the caller uploads, never artifact publishing.
