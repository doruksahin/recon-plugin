# 0002 — Verbatim gate exchanges with railed presentation

- Status: accepted
- Date: 2026-08-02
- Deciders: Doruk

## Context

The pipeline has two kinds of human gates, and only one of them is accountable. The asynchronous Jira path is fully railed: `render-comment.sh` emits the exact bytes from `triage.yaml`, `verify-comment-shape.sh` checks them, `post-result.json` records the byte-exact response, and the human's answer lives permanently on the ticket. The in-session gates are not: at discovery's approval gate (SKILL.md step 8) the model paraphrases each `OPEN-N` scenario into a chat question, improvises a recommendation that is written nowhere, receives a free-text answer, and maps it to an option — then records only the mapped conclusion in `discovery/gate.yaml`.

Concrete instance (ATT-5047): the gate asked *"Should clicking a hidden collection row select it and show its outputs, or leave it usable only for Show/Delete/reordering?"* — a paraphrase of `OPEN-1`. The user answered *"clicking a hidden collection should not do anything."* After the session expires, `gate.yaml` holds a resolution summary with no trail: the question as asked, the recommendation given, the user's exact words, and the faithfulness of the answer→option mapping are all unrecoverable.

By the design formula (pipeline.md: "a step where the model has freedom in *execution* is a defect"), the gate presentation is an existing defect, not just a missing feature: presenting the question is execution, and today the model has full freedom in it. A decision is needed now because per-ticket decision records were requested and any storage design that does not capture the exchange at gate time cannot be repaired later — you cannot derive what was never recorded.

## Decision

Make the in-session gate exchange a verbatim, verifier-checked artifact, with the presentation moved onto a rail. Scope: the discovery gate first; other in-session gates follow the same pattern later (see Revisit triggers).

1. **Recommendation on the record.** The gate recommendation for each `OPEN-N` is authored visibly in `discovery/discovery.md` as part of the scenario's options (e.g. a `(recommended)` marker on one option), not improvised in chat. Judgment stays in the model; it now leaves evidence.
2. **Railed presentation.** A new rail *render-gate.sh* emits `discovery/gate-questions.md` deterministically from `discovery/discovery.md` + `route/routing.yaml`: one block per `OPEN-N` (scenario, options, recommendation) plus the package block (`Approve / Edit / Reject`). The skill presents those bytes verbatim — the in-session analogue of `render-comment.sh`. It is never hand-edited; edits happen in `discovery.md` and re-render.
3. **Verbatim exchange record.** `discovery/gate.yaml` gains an `exchanges:` list — one entry per `OPEN-N` and one for `PACKAGE` — each carrying: `id`, `presented` (reference into `gate-questions.md`), `recommendation`, `answer_verbatim` (the user's exact words), and `resolution` (the mapped outcome, identical to the `open_scenario_resolutions` value). Both sides of the answer→option mapping now sit next to each other, permanently.
4. **Verified.** `verify-discovery.sh post-gate` additionally checks: `gate-questions.md` exists and covers every `OPEN-N`; every `OPEN-N` and `PACKAGE` has an exchange with a non-empty `answer_verbatim`; every exchange `resolution` matches its `open_scenario_resolutions` value (which invariant 17 already binds into the brief). New verifier behavior gets isolated clean and failing fixtures (Change protocol item 5).
5. **Output, not evidence.** The exchange record is output about the run — like `comment.txt` — never an input to any check, verdict, or route. No tension with invariants 3, 11, or 16; the artifact lives and dies with its run.
6. **Registered and mirrored.** `discovery/gate-questions.md` enters `recon/docs/registry.yaml` first; pipeline.md's registry mirror, trigger table, and rails-vs-judgment table, plus `workspace-index.md` and `docs/flow.html`, update in the same commit. The `gate.yaml` schema change is an artifact-contract change: one `feat(gate)!` with a `BREAKING CHANGE:` footer.

## Consequences

- Full audit chain in registered artifacts: question as rendered → recommendation → verbatim answer → mapped resolution → same-ID binding in the brief. A future reader of the workspace can judge whether the mapping was faithful — today's chat-only gap closes.
- Presentation drift is eliminated: what the user was asked is exactly what `discovery.md` says, byte-for-byte, every run.
- `discovery.md` gains an authoring requirement (a visible recommendation per OPEN scenario) that *render-gate.sh* and `verify-discovery.sh` enforce.
- Breaking release: `gate.yaml` consumers (`verify-discovery.sh`, recon-report decision cards) and golden fixtures (`docs/improvement-proposals/0.14.0/golden-fixtures/`) must move in the same commit.
- The other in-session gates (triage's post/edit/don't-post — where "Don't post" currently leaves no artifact at all — the governance one-time question, the state-canvas first publish) remain unrecorded until they adopt the pattern.
- A consolidated per-ticket "decisions" view becomes trivial later: it can be derived from exchange records + the Jira trail, because the data now exists.

## Affected files (one accountable commit)

- `recon/skills/recon-discovery/SKILL.md` — step 3 (visible recommendation per OPEN option), step 8 (present rendered bytes, record exchanges), gate.yaml schema block
- *recon/scripts/render-gate.sh* — new rail
- `recon/scripts/verify-discovery.sh` — post-gate exchange checks
- `recon/docs/registry.yaml` — `discovery/gate-questions.md` entry, first
- `recon/docs/pipeline.md` — registry mirror, trigger table, rails-vs-judgment table, invariant 17 wording
- `recon/docs/workspace-index.md` + `docs/flow.html` — registry mirrors
- `docs/improvement-proposals/0.14.0/golden-fixtures/` — clean + failing fixtures for each new verifier check

## Validation

- `bash tools/check-links.sh` and `bash tools/check-coherence.sh` pass — the new artifact token present in all three mirrors, verifier fixture cases counted.
- Fixtures: one clean case (exchanges complete, resolutions matching) and one failing case per new check (missing `gate-questions.md`, missing exchange, empty `answer_verbatim`, resolution mismatch) — `verify-discovery.sh post-gate` must fail each failing case in isolation.
- Determinism: rendering `gate-questions.md` twice from the same `discovery.md` + `routing.yaml` produces byte-identical output (`cmp` passes).
- End-to-end: a discovery run on a ticket with ≥1 OPEN scenario ends with `lint-workspace.sh <TICKET>` clean and `gate.yaml` carrying an exchange with a non-empty `answer_verbatim` for every `OPEN-N` and `PACKAGE`.

## Revisit triggers

- Extending the pattern to the remaining in-session gates (triage posting gate first — it already has a rail-rendered draft to reference).
- Demand for a single consolidated decisions view per ticket (derive it; do not create a second owner).
- Host-native interaction gaining a mechanism that captures presented text + answer automatically, which would let the harness replace parts of the rail.

## Considered and rejected

| Option | Reason rejected |
|---|---|
| `recon-decisions` skill owning a `decisions/decisions.yaml`, triage/discovery referencing decision IDs | Ownership migration breaks the coupling invariants 13/15 rely on (`render-comment.sh`/`verify-triage.sh` would join two files — the drift the one-owner rule exists to kill); for triage's async lifecycle the durable store is necessarily Jira (invariants 3, 11, 16 forbid a cross-run evidence file), so the file stores nothing new there; a skill whose behavior forks entirely by transport owns only a schema — wrong grain, this is rail work |
| Derived decisions view only (a *derive-decisions.sh* rail compiling from existing owners) | Cannot capture what was never recorded — the paraphrased question, recommendation, and verbatim answer exist only in chat; unable to fix accountability by construction |
| Record `answer_verbatim` without railing the presentation | Leaves the model free to paraphrase the question; the recorded answer would answer an unrecorded question — half the trail, and the design-formula defect stands |
| Do nothing (rely on chat transcripts) | Sessions expire and transcripts are not registered artifacts; the answer→option mapping stays unauditable |
