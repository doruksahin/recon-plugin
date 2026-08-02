# recon/skills/ — the five skills

One directory per skill; each `SKILL.md` is authoritative for its own stage
(pipeline.md yields to it on conflict). Skills hold the JUDGMENT steps and
call the rails in `../scripts/` for everything mechanical. Adding a skill
directory without a role line below fails `tools/check-coherence.sh`.

| Directory | Stage | Role |
| --- | --- | --- |
| `recon-triage/` | 0–1 | Blocker triage: fresh workspace, ticket fetch, six checks with typed evidence, derived disposition (`verify-triage.sh`), and the BLOCKED/NEEDS_INFO posting path (render → shape → package → gate → attach-then-comment). |
| `recon-discovery/` | 2 | Code discovery for READY tickets: behavior contract (Gherkin), governance routing dispatch, implementer brief (`spec-draft.md`), approval gate. |
| `recon-repro/` | R | On-demand live repro: numbered human-re-runnable steps + annotated screenshots into `repro/`. Never fabricated — a failed repro is a reported finding. |
| `recon-report/` | D | The dossier: fills its `template.html` from current-run artifacts (a view, NO new facts). Render-only on the posting path; publishes a private artifact on demand. |
| `recon-decree/` | RT | Governance adapter for decree: same contract as `route-generic.sh` (writes `route/routing.yaml` incl. verbatim `handoff:`). ALL decree vocabulary is quarantined here — a `governance: none` run never loads it. |

New governance adapters follow the `recon-<governance>` convention with the
same contract as `recon-decree/` (pipeline.md Change protocol, item 6).
