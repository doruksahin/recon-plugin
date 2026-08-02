# recon/skills/ — the skills

One directory per skill; each `SKILL.md` is authoritative for its own stage
(pipeline.md yields to it on conflict). Skills hold the JUDGMENT steps and
call the rails in `../scripts/` for everything mechanical. Adding a skill
directory without a role line below fails `tools/check-coherence.sh`.

| Directory | Stage | Role |
| --- | --- | --- |
| `recon-triage/` | 0–1 | Blocker triage: fresh workspace, ticket fetch, six checks with typed evidence, derived disposition (`verify-triage.sh`), verified UI-blocker repro evidence, and the BLOCKED/NEEDS_INFO posting path (render → shape → package → gate → attach-then-comment). |
| `recon-discovery/` | 2 | Code discovery for READY tickets: stable-ID Gherkin contract, governance routing, verified repro before the route-required brief, pre/post-gate package verification, package approval, then dossier/bundle delivery behind a distinct Jira gate and approval handoff. |
| `recon-repro/` | R | On-demand live repro inside a recorded proofshot session (`record-repro.sh`): fixed metadata, numbered human-rerunnable steps transcribed from the action log + screenshots into `repro/`, session bundle in `repro/session/`, then structural/provenance verification (incl. log cross-checks) and visual readback. Never fabricated — a failed repro is a verified finding. |
| `recon-report/` | D | Verifies generated evidence, then fills its dossier template from current-run artifacts. Always renders locally; publishes only when `publish_once` is available. |
| `recon-decree/` | RT | Governance adapter for decree: same contract as `route-generic.sh` (writes `route/routing.yaml` incl. verbatim `handoff:`). ALL decree vocabulary is quarantined here — a `governance: none` run never loads it. |
| `recon-state/` | S | Mechanical living state canvas. Always renders locally; creates/updates `state/artifact-url` only when `publish_stable_url` is available. Timeline is ledger view-only (invariant 16). |
| `recon-help/` | utility | Orientation + setup doctor (not a pipeline stage). Presents `doctor.sh` output verbatim — version, skill list, and setup checks are all derived live by the rail, so the help surface cannot drift. Writes nothing. |
| `recon-publish/` | utility | Release + distribute (not a pipeline stage): gated `release.sh --yes`, cache activation via `activate-plugin.sh`, marketplace-clone sync, republish of changed artifact mirrors, smoke test from the activated path. Parked here for later extraction to a shared devkit. |

New governance adapters follow the `recon-<governance>` convention with the
same contract as `recon-decree/` (pipeline.md Change protocol, item 6).
