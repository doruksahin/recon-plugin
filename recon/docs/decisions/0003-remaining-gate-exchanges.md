# 0003 — Verbatim exchanges at the remaining in-session gates

- Status: accepted
- Date: 2026-08-02
- Deciders: Doruk

## Context

[ADR 0002](0002-verbatim-gate-exchanges.md) made the discovery approval gate accountable — rail-rendered questions in `discovery/gate-questions.md`, the user's exact answer next to its mapped resolution in `discovery/gate.yaml` — and named the three in-session gates that still leave no exchange artifact. They are all live defects by the same design formula (pipeline.md: "a step where the model has freedom in *execution* is a defect"):

1. **Triage posting gate** (recon-triage posting path). The `Post to Jira now / Edit first / Don't post` answer is recorded nowhere. A run where the human said "don't post" is byte-for-byte indistinguishable on disk from a session that crashed before reaching the gate: both leave a rendered `comment.txt`, a bundle manifest, and no `post-result.json`. The presented bytes largely exist already (`triage/jira/comment.txt` is rail-rendered, `bundle-manifest.txt` is rail-written), but the question *around* them — attachment names, their sizes, the bundle file count, the three options — is composed by the model at gate time, and the Edit loop can re-present it any number of times with nothing recording that it happened.
2. **Governance one-time question** (recon-discovery step 4 → `set-governance.sh`). Only the mapped value survives, as `governance=<value>` in `~/.config/recon/config`. The question as asked, the options shown, and the developer's exact words are lost, so a standing choice that shapes every future ticket's handoff has no record of how it was obtained.
3. **State-canvas first publish** (recon-state rule 2). A declined publish writes nothing, so the absence of `state/artifact-url` is three different situations at once — never asked, asked and declined, or a host without `publish_stable_url` — and the skill cannot tell them apart on its next invocation.

ADR 0002 already settled the alternatives that apply to all of these (a central `decisions/` owner, a derived-only view, recording an answer without railing the question, and doing nothing); see its Considered-and-rejected table. What ADR 0002 did *not* settle is how much presentation machinery each remaining gate needs. Its answer for discovery — a dedicated renderer emitting a registered artifact — is the right shape for a question whose content is authored per run, and the wrong shape for a question that is a constant.

## Decision

Extend the verbatim-exchange pattern to all three gates, and settle the per-gate presentation question with one rule.

**The rule.** How a question gets on the record follows from where its content comes from:

- **Per-run authored content** (composed from this run's artifacts, so the model could paraphrase it) → a *rendering rail* emits a registered artifact, the skill presents those bytes word-for-word, the model authors the exchange record, and a verifier proves the two agree. This is ADR 0002's shape; the triage posting gate takes it.
- **Fixed content** (a constant string with a mechanical substitution) → the *recording rail owns the question text*: it prints the question on request and writes its own copy of that text into the record, so the model supplies only the answer and has nothing to paraphrase. No second artifact, no second owner of the same bytes. The governance question and the state-canvas publish gate take this shape.

Both shapes satisfy ADR 0002's requirement that presentation be railed. They differ only in whether the presented bytes need to exist as a file that a verifier can compare against something else.

1. **Triage posting gate.** A new rail *render-post-gate.sh* emits `triage/jira/post-gate-questions.txt` from `comment.txt` + `bundle-manifest.txt` + the staged zip: the exact comment bytes, the attachment lines with real sizes, the bundle file count, and the three fixed options. It runs after `package-artifacts.sh` (it quotes the manifest) and re-runs after every Edit-loop change. The exchange goes to `triage/jira/post-gate.yaml` as an ordered `exchanges:` list — one entry per presentation, each with `answer_verbatim` and an `outcome` of `posted`, `edited`, or `declined`. `edited` entries are non-terminal; exactly one terminal entry ends the list. A new rail *verify-post-gate.sh* proves the rendered question carried the posted comment bytes verbatim, the schema holds, every answer is non-empty, the terminal entry is last, and the outcome agrees with what is on disk (`posted` requires `post-result.json`; `declined` forbids it and `attach-result.json`).
2. **Ledger and derived state follow the record.** `log-event.sh`'s closed vocabulary gains `post_declined` — a declined delivery changes what the ticket did and did not receive, which is exactly the kind of fact the cross-run ledger exists to tell. `derive-state.sh` gains the matching stop (`post-declined`) and node status (`declined`), so the state canvas stops telling a human to approve a gate they already answered.
3. **Governance question.** `set-governance.sh` becomes the governance exchange rail with two subcommands: `question <tool>` prints the exact question and options; `answer <value> <tool> <verbatim>` persists the config as before **and** appends one JSON line to `~/.config/recon/governance-exchanges.ndjson` carrying the date, the tool, the rail's own re-render of the question, the developer's exact words, and the mapped value. The record lives beside the config it explains because the choice is cross-ticket and standing — a per-workspace copy would die with the run and mislead every later ticket. The bare `set-governance.sh <value>` form still works for a developer changing their standing choice from a shell; it records an exchange with `source: manual` and no answer text, because a CLI invocation is not a gate.
4. **State-canvas publish gate.** A new rail *record-publish-gate.sh* owns the question (`question <TICKET>`) and the record (`answer <TICKET> <published|declined> <verbatim>` → `state/publish-gate.yaml`, an append-only `exchanges:` list of date, question, options, `answer_verbatim`, `outcome`). recon-state's publish step becomes a four-row decision table over `publish_stable_url`, `state/artifact-url`, and the last recorded outcome: incapable hosts never ask and never write the file; a saved URL republishes without asking; no record means ask; a recorded decline is reported instead of silently re-asked. The three states ADR 0002 called ambiguous are now distinct on disk.
5. **Output, not evidence.** Every record here is output about a run, like `comment.txt` and `discovery/gate.yaml` before them. No check, verdict, route, or disposition reads one. The state gate's own record is the single exception to "nothing reads it", and only within its own run: recon-state reads its last outcome to decide whether to re-ask, which is the defect being fixed, not evidence about the ticket.
6. **Registered and mirrored.** `triage/jira/post-gate-questions.txt`, `triage/jira/post-gate.yaml`, and `state/publish-gate.yaml` enter `recon/docs/registry.yaml` first; pipeline.md's registry mirror, trigger table, and rails-vs-judgment table, plus `workspace-index.md` and `docs/flow.html`, move in the same commits. `~/.config/recon/governance-exchanges.ndjson` is outside every workspace and therefore outside the registry. A new pipeline invariant, landing with the first of these gates, states the general rule — every in-session gate leaves a verbatim exchange record — so future gates inherit it by citation rather than by memory.

## Consequences

- All four in-session gates now produce the same audit chain as the async Jira path: question as presented → the user's exact words → the mapped outcome. "Nothing happened" and "a human said no" stop looking identical on disk.
- Three `feat(gate)!` releases: a posting-path run without the rendered question and exchange record fails *verify-post-gate.sh*; recon-discovery must obtain the governance answer through the rail; recon-state must record its publish answer.
- The Edit loop becomes visible. Today a gate re-presented four times leaves one comment draft; from now on it leaves four exchange entries, which is what actually happened.
- `post-gate-questions.txt` and `post-gate.yaml` are written after `package-artifacts.sh`, so they are not inside the delivery zip. That is correct — the zip is what ships to Jira, the gate record is what stays in the workspace — but it means the bundle manifest and the gate record are never a complete mirror of each other.
- The state-canvas decline is per-run: step 0 archives `state/` wholesale, so the record (like `state/artifact-url` itself) does not survive into the next run. Cross-run publish identity is a pre-existing defect of its own, not something this ADR repairs — see Revisit triggers.
- `~/.config/recon/` gains a second file. A developer who has never hit the governance question still has none.

## Affected files (three accountable commits, one per gate)

- *recon/scripts/render-post-gate.sh*, *recon/scripts/verify-post-gate.sh* — new rails; `recon/scripts/triage-tools.py` — the `verify-post-gate` engine
- `recon/scripts/log-event.sh` (`post_declined`), `recon/scripts/derive-state.sh` + `recon/scripts/render-state-canvas.sh` (declined stop/status/chip/timeline label)
- `recon/scripts/set-governance.sh` — question/answer subcommands and the exchange record
- *recon/scripts/record-publish-gate.sh* — new rail
- `recon/skills/recon-triage/SKILL.md` (posting path), `recon/skills/recon-discovery/SKILL.md` (step 4), `recon/skills/recon-state/SKILL.md` (rule 2 + publish step)
- `recon/docs/registry.yaml` first, then `recon/docs/pipeline.md` (registry mirror, trigger table, rails table, the new gate-record invariant), `recon/docs/workspace-index.md`, `docs/flow.html`
- `recon/scripts/CLAUDE.md` role lines, `tools/CLAUDE.md` fixture coverage line, `README.md` (the governance sentence)
- `tools/test-artifact-verifiers.sh` — clean and failing fixtures per new rail

## Validation

- `bash tools/check-links.sh` and `bash tools/check-coherence.sh` pass: new registry tokens present in all three mirrors, role lines present, invariant citations valid.
- Fixtures, isolated: the post-gate renderer is byte-deterministic and refuses a missing comment draft or zip; *verify-post-gate.sh* fails independently on a missing rendered question, comment-bytes drift, an empty `answer_verbatim`, an unknown outcome, a non-terminal last entry, `posted` without `post-result.json`, and `declined` with one.
- Fixtures, isolated: `set-governance.sh question` renders deterministically; `answer` writes both the config and the exchange line; a missing verbatim answer or an invalid value exits 2 and writes nothing.
- Fixtures, isolated: `record-publish-gate.sh question` renders deterministically; `answer` appends an exchange; an unknown outcome exits 2; a declined record leaves `state/artifact-url` absent and `lint-workspace.sh` clean.
- `derive-state.sh` reports `stop: post-declined` for a declined delivery and exits 1 on the contradiction of a declined record beside a `post-result.json`.

## Revisit triggers

- Cross-run publish identity: step 0 archives `state/artifact-url` with the rest of `state/`, so a ticket's "stable" canvas URL is re-created on every run. Fixing that (a preserved-across-runs list like `history.ndjson`) would also make the publish decline durable.
- A fourth gate appearing anywhere in the pipeline — apply the rule above rather than re-deciding it.
- A consolidated per-ticket decisions view: derive it from the four records plus the Jira trail; do not create a second owner (ADR 0002 settled this).

## Considered and rejected

| Option | Reason rejected |
|---|---|
| Extend `render-gate.sh` to render all four gates | It renders from `discovery.md` + `routing.yaml` and is owned by discovery; a triage, config, or state question has different inputs and a different owner. One rail per owner is why `render-comment.sh` lives with triage — joining them recreates the cross-file coupling the one-owner rule exists to kill |
| Give the fixed-string gates their own rendered-questions artifact too | Their question has no per-run authored content, so the artifact would be a constant re-written every run and a second owner of bytes the rail already holds. Having the recording rail print and store its own question text gives the same no-paraphrase guarantee with one fewer artifact |
| Store the governance exchange in the workspace (e.g. `route/`) | The answer is standing and cross-ticket; a per-workspace copy dies at step 0 and reappears — wrongly dated — in every later ticket's workspace. The record belongs beside the config it explains |
| Record the exchanges as ledger events instead of artifacts | Invariant 16 makes the ledger output that no check may read. recon-state must read its last publish outcome to stop re-asking, which would turn the ledger into evidence. The ledger still gets `post_declined` as a story event, not as the record |
| Reuse `discovery/gate.yaml`'s exact schema for the triage gate | Its shape is `OPEN-N` + `PACKAGE` resolutions joined to a contract; the posting gate has one repeatable question and an Edit loop. Forcing one schema onto both would mean fields that are always empty on one side |
| Keep the triage gate recording-only (no renderer), since `comment.txt` is already railed | The comment bytes are railed; the question around them — attachment names, sizes, bundle count, options — is not, and the Edit loop re-presents it. ADR 0002 already rejected recording an answer to an unrailed question |
