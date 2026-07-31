---
description: Render a ticket's recon workspace into a self-contained HTML dossier and publish it as a private artifact. Use after a recon run finishes (gate answered, or BLOCKED comment handled), or when asked for a recon report, dossier, or shareable summary of a recon run.
---

# Recon Report

Turns the current-run artifacts of `~/.claude/recon/<TICKET>/` into one designed, self-contained HTML page — verdict chips, seven-slot facts, stage-by-stage narrative, evidence tables, screenshot exhibits, gate decisions, handoff — published as a **private** artifact the user can choose to share.

## Contract

- **Input:** ticket ID (precondition: current run exists — root `meta.yaml` + `triage/triage.yaml`)
- **Reads:** current-run artifacts in `~/.claude/recon/<TICKET>/` (never `runs/`), the shipped `template.html`
- **Writes:** ONLY inside `~/.claude/recon/<TICKET>/report/` — `dossier.html`. Create the directory before writing. Anything else fails `lint-workspace.sh`
- **External side effects:** publishes `report/dossier.html` as a private artifact (visible only to the user). Nothing else — never posts to Jira, never touches the repo.

---

## ⚠️ CRITICAL: Rules

1. **NO NEW FACTS.** The dossier is a *view*, not a re-derivation. Every claim, number, link, and caption MUST trace to a workspace artifact. You may compress wording; you MUST NOT add findings, opinions, severity judgments, or links that no artifact contains. A template slot with no source artifact reads `None` or `not run — <reason from artifacts>` — never invented content. Judgment is confined to exactly two places: the headline sentence and the lede.
2. **Fixed template.** Fill the `«SLOT: …»` markers of the `template.html` shipped next to this SKILL.md. Do NOT redesign, restyle, reorder sections, or drop the instruction comments' constraints. Same seven facts slots, same order, every dossier.
3. **NEVER read `runs/`.** The dossier documents the current run only. Prior runs are invisible (pipeline invariant 3).
4. **Pin code links mechanically.** GitHub links use the commit from `route/routing.yaml` `evidence.repo_commit`. If that field is absent, write file paths as plain `code` (or `.pathcopy` buttons) with the footer noting `unpinned` — NEVER guess a SHA or link to a branch.
5. **Self-contained page.** Screenshots are embedded as `data:` URIs (external hosts are blocked by the artifact CSP). Recompress each PNG to JPEG before embedding: `sips -s format jpeg -s formatOptions 72 --resampleWidth 1600 <in>.png --out <tmp>.jpg` (fall back to the raw PNG only when `sips` is unavailable and the file is < 300 KB). Keep the final page under ~3 MB.
6. **Private by default.** Publish, print the URL, stop. Sharing the link is the user's action — never post the URL to Jira or anywhere else.
7. **BLOCKED runs get dossiers too.** Chips show the real disposition; discovery/repro/gate sections read `not run` with the reason; the handoff block shows the re-entry instruction. Do not skip the report because the pipeline stopped early.

---

## Slot map (template ← artifacts)

| Template slot | Source (verbatim facts) |
|---|---|
| TICKET, Jira URL | `meta.yaml` ticket + `JIRA_HOST` from `~/.config/jira/env` |
| Verdict chips | `triage/triage.yaml` disposition · `repro/repro.md` outcome · `route/routing.yaml` route/matched_rule · `discovery/gate.yaml` approved |
| headline + lede | judgment (rule 1) — facts only from `triage.yaml`/`discovery.md` |
| Seven facts: Verdict / Where / Reuse / Scope / Decided / Open / Next | `triage/triage.yaml` + repro outcome · root-cause `file:line` from `discovery/discovery.md` · `route/routing.yaml` `evidence.reuses_existing_contract` · `evidence.blast_radius` · `discovery/gate.yaml` resolutions · open items/findings · route + verbatim handoff |
| repo_commit link, footer | `route/routing.yaml` `evidence.repo_commit`, `meta.yaml` plugin_version + started |
| Pipeline stages 0–5 | `meta.yaml` (step 0), each stage's directory; a missing stage directory ⇒ `not run — <reason>` |
| Six-checks table | `triage.yaml` checks + matching `evidence:` lines, one row each |
| Cross-checks table | `triage.yaml` `status_drift`, `stale_blocker_note` |
| Discovery body + excerpts | `discovery/discovery.md`, `route/routing.yaml` (incl. `rules_not_matched` if quoted) |
| Repro env + exhibits | `repro/repro.md` start state + numbered steps as captions; `repro/exhibits/<n>-<slug>.png` in step order |
| Decision cards | `discovery/gate.yaml` |
| Handoff block | `route/routing.yaml` `handoff:` — VERBATIM (it is data, never recomposed), or the BLOCKED re-entry line |

## Workflow

1. **Verify the workspace.** Root `meta.yaml` + `triage/triage.yaml` must exist. If missing, stop: tell the user to run `/recon:recon-triage <TICKET>` first — never reconstruct from memory or `runs/`.
2. **Read every current-run artifact** across the stage directories (registry in `../../docs/pipeline.md`, and each workspace carries its own `index.md`). A stage ran ⇔ its directory exists.
3. **Prepare exhibits** per rule 5 (use the session scratchpad for temp JPEGs).
4. **Fill the template** slot by slot per the map. Strip the instruction comments (`«SLOT: …»` markers and the leading file comment) from the output.
5. **Write** `~/.claude/recon/<TICKET>/report/dossier.html`, then run `bash "<skill base dir>/../../scripts/lint-workspace.sh" <TICKET>` and fix any violation.
6. **Publish** as an artifact: title `<TICKET> — Recon Dossier`, favicon `🗂️` (keep both stable across redeploys of the same ticket). If the environment requires a prerequisite skill before publishing (e.g. `artifact-design`), load it first. Re-running for the same ticket republishes the same file path — pass the existing artifact URL if this session didn't create it.

## Report

Print:

```
Wrote: ~/.claude/recon/<TICKET>/report/dossier.html (<size>)
Lint: <lint-workspace.sh verdict line, verbatim>
Published: <artifact URL> (private — sharing is your call)
Coverage: <stages included> · <n> exhibits · commit <sha|unpinned>
```

---

## Reference

- Whole-chain spec (stages, invariants, artifact registry, trigger table): `../../docs/pipeline.md` relative to this skill's base directory. On conflict, this SKILL.md wins.
- This skill is on-demand only — no pipeline stage auto-invokes it.
