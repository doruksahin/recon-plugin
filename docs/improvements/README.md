# Recon pipeline — improvement ideas

Index of proposed improvements. One line per idea; open the folder for the concrete
before/after. Conventions and template: [CLAUDE.md](CLAUDE.md).

Most ideas here originate from the ATT-5107 triage run (1 Aug 2026), which hit an
expired token, a duplicate-account trap, auth-walled evidence links, a removed Jira
API, and a delegation-vs-answer judgment call — all in one run.

## Design basis

The v0.15 review applied Skillshare's [Skill Design](https://skillshare.runkids.cc/docs/understand/philosophy/skill-design)
and [Skill Design Patterns](https://skillshare.runkids.cc/docs/understand/philosophy/skill-design-patterns):
keep routing metadata compact, disclose operational detail only after activation,
move repeatable decisions into deterministic commands, and compose authoring
skills with independent reviewer rails. Model judgment remains only where the
evidence needs semantic or visual interpretation.

## v0.15 verified company chain

The five v0.15 decisions compose one bounded handoff chain rather than five
isolated cleanups:

```text
attested plugin bytes → bounded routing metadata → atomic runtime snapshot
  → verified repro evidence → verified Discovery + gate + implementation handoff
```

Activation proves the company is running the released plugin; routing loads the
right narrow skill; startup gives that skill one coherent capability snapshot;
and the two artifact gates prevent bad evidence or a lost human decision from
reaching an implementer. Each boundary either fails mechanically or names the
remaining human judgment explicitly.

## Determinism rails

Move work from SKILL.md prose into scripts that fail. Goal: the only free text the
model writes is asks, detail packs, headline, lede — everything else is derived.

| Idea | Status | Prio | One-liner |
| --- | --- | --- | --- |
| [derive-disposition](derive-disposition/README.md) | shipped (v0.9.0) | P1 | Compute the verdict from the six checks by script; lint fails on mismatch |
| [ticket-ledger](ticket-ledger/README.md) | shipped (v0.13.0) | P2 | Append-only *history.ndjson* survives step 0; a rail logs each transition; nothing may read it as evidence |
| [validate-triage-yaml](validate-triage-yaml/README.md) | proposed | P1 | Schema + regex lint for triage.yaml: rule-7 identifier bans, length caps, ask shape |
| [verify-quotes](verify-quotes/README.md) | shipped (v0.9.0) | P1 | Type evidence lines; substring-check every quote against ticket.json |
| [render-comment](render-comment/README.md) | shipped (v0.9.0) | P2 | Generate comment.txt from triage.yaml by script — the model never writes it |
| [deterministic-decree-routing](deterministic-decree-routing/README.md) | proposed (policy needed) | P1 | Apply Decree routes from typed facts with a total, mechanically tested decision table |
| [render-dossier-rail](render-dossier-rail/README.md) | proposed (after schemas) | P1 | Render dossiers from artifacts; let the model author only headline and lede |
| [verify-discovery-package](verify-discovery-package/README.md) | implemented for v0.15.0 | P1 | Fail when visible scenarios, brief entries, gate decisions, and repro references do not agree |
| [verify-repro-evidence](verify-repro-evidence/README.md) | implemented for v0.15.0 | P1 | Verify every repro step is fresh, numbered, and visibly backed by a structurally valid in-workspace PNG |
| [proofshot-repro-runtime](proofshot-repro-runtime/README.md) | shipped (v0.16.0) | P1 | Run every repro under proofshot: action-log + video provenance; steps transcribed, not recalled |
| [skill-metadata-budget](skill-metadata-budget/README.md) | implemented for v0.15.0 (companion) | P2 | Keep every skill description under 200 characters and fail checks on overflow |
| [slop-lint](slop-lint/README.md) | proposed | P3 | Banned-phrase denylist + structural caps on the remaining free-text slots |
| [golden-fixtures](golden-fixtures/README.md) | proposed | P3 | Canned ticket.json fixtures + golden-output diffs; regression-test the pipeline |

## Operational robustness

Failure modes observed live that the skills don't handle or handle ambiguously.

| Idea | Status | Prio | One-liner |
| --- | --- | --- | --- |
| [doc-coherence-rail](doc-coherence-rail/README.md) | shipped (v0.9.0) | P1 | One owner per shared fact; check-coherence.sh fails commits whose mirrors drift |
| [governance-ux](governance-ux/README.md) | shipped (v0.10.0) | P2 | One-time question and reports phrased as handoff outcomes; ladder demoted to internals |
| [help-doctor-skill](help-doctor-skill/README.md) | shipped (v0.10.0) | P2 | recon-help + doctor.sh: orientation and setup checks, every fact derived live |
| [publish-skill](publish-skill/README.md) | shipped (v0.12.0) | P2 | recon-publish + activate-plugin.sh: gated release, cache activation, mirror republish |
| [credential-preflight](credential-preflight/README.md) | proposed | P1 | GET /myself before the ticket fetch; expired tokens fail loudly with a fix |
| [owner-resolution-order](owner-resolution-order/README.md) | proposed | P2 | Resolve accountIds from ticket data first; user search only as fallback |
| [answered-blocker-rule](answered-blocker-rule/README.md) | proposed | P2 | A reply closes a blocker only if it supplies the asked value; delegation ≠ answer |
| [evidence-ok-tristate](evidence-ok-tristate/README.md) | proposed | P2 | Split evidence_ok into true / auth-walled / broken; stop the permanent false flag |
| [step0-run-identity](step0-run-identity/README.md) | proposed | P3 | Key the fresh-workspace guard on a run token, not elapsed time |
| [jira-api-v3-search](jira-api-v3-search/README.md) | proposed | P3 | Migrate search references to /rest/api/3/search/jql; v2 search is removed |
| [state-canvas-skill](state-canvas-skill/README.md) | shipped (v0.13.0) | P2 | New skill renders a node-canvas artifact per ticket; state derived from file presence, one stable URL |
| [jira-delivery-rail](jira-delivery-rail/README.md) | proposed (dedicated release) | P1 | Bind Jira approval to exact bytes, then deliver attachments and one comment idempotently |
| [single-runtime-bootstrap](single-runtime-bootstrap/README.md) | implemented for v0.15.0 (narrow) | P2 | Resolve host, capabilities, root, and preflight with one atomic bootstrap command |
| [attested-codex-activation](attested-codex-activation/README.md) | implemented for v0.15.0 | P1 | Bind commit plus materialized plugin tree before/after install, then attest Codex's version/path |
