---
date: '2026-08-05'
governs:
- AGENTS.md
- CLAUDE.md
- README.md
- lychee.toml
- evals/AGENTS.md
- evals/CLAUDE.md
- evals/README.md
- evals/skills/AGENTS.md
- evals/skills/recon-version-review/
- evals/version-reviews/
- tools/version-review.py
- tools/test-version-review.sh
- tools/check-links.sh
- tools/check-coherence.sh
- tools/CLAUDE.md
- docs/plans/2026-08-05-version-scoped-team-review-laboratory.md
- docs/improvement-proposals/README.md
- docs/improvement-proposals/0.23.0/
- tools/render-system-map.py
- tools/test-system-map.sh
- docs/system-map.html
- docs/replay-lab-report.html
- docs/flow.html
- docs/CLAUDE.md
- recon/docs/workspace-index.md
- docs/improvement-proposals/0.18.0/ready-jira-delivery/README.md
- docs/improvement-proposals/0.19.0/real-ticket-replay-lab/README.md
- docs/improvement-proposals/0.20.0/offline-valid-replay-verification/README.md
- docs/improvement-proposals/0.21.0/decision-closure-triage/README.md
- docs/improvement-proposals/0.22.0/requirement-closure-coverage/README.md
id: SPEC-01KZ7E7FXK0T0W83PKGWPMC0ZW
references:
- ADR-01KZ0ZK4WYVWRY0WJM2CZ7ZS8C
status: implemented
---

# SPEC-01KZ7E7FXK0T0W83PKGWPMC0ZW Recon Version-Scoped Team Review Laboratory

## Overview

Recon v0.19.0 is ready for controlled Jira-ticket use, but the repository has
no durable workflow for a team to review many locally rendered dossiers under
the exact plugin version that produced them. The runtime workspace is
intentionally closed to arbitrary files, the replay laboratory freezes only
selected sanitized cases, and the improvement loop starts only after a bounded
proposal exists. Team feedback therefore has no version identity, immutable
report receipt, cross-review consensus, or deterministic bridge into a future
proposal.

**Falsifiable claim:** Given an external private review root and locally
rendered Recon workspaces from one published plugin version, a repository-only
rail can initialize the exact version tree, capture immutable minimal report
evidence without Jira mutation artifacts or raw Jira inputs, validate
independent reviews and consensus against the captured report hash, retain one
cross-ticket synthesis, and close the version cycle without overwriting prior
runs.

This extends the evidence boundaries established by
`SPEC-01KZ5TE6QP704T8G2HJNXSP58W` and the state-first approach in
`SPEC-01KZ69A6YY6Z5MTW88XP815WJ7`; it does not replace replay scoring or the
proposal improvement loop. It does not claim that a reviewed report is
correct, that teammate agreement proves an improvement, or that private Jira
material is safe to commit to this public repository.

## Technical Design

### Ownership and location

`tools/version-review.py` is the sole mutation and validation owner. It writes
only beneath an operator-supplied external root at
`<review-root>/versions/v<plugin-version>/`. The root must be a real,
symlink-free directory and must not overlap the source Recon workspace. No
live review output is stored under `evals/`, `$RECON_ROOT`, or a target
repository.

`evals/version-reviews/schema.yaml` owns required keys, enums, capture paths,
and lifecycle transitions. Authored examples under
`evals/version-reviews/templates/` are validated against that schema by the
same rail. `evals/version-reviews/README.md` explains the folder model and
links to the schema, CLI, operator skill, replay lab, improvement loop, and
workspace registry rather than restating their contracts.

### External version tree

Each actual published plugin version owns one append-only review cycle:

```text
versions/vX.Y.Z/
  version.yaml
  manifest.yaml
  tickets/<TICKET>/ticket.yaml
  tickets/<TICKET>/runs/<run-id>/
    receipt.yaml
    manifest.json
    artifacts/<registered-minimal-current-run-files>
    reviews/<review-id>.yaml
    consensus.yaml
  synthesis/{findings.yaml,themes.yaml,decisions.yaml}
  outcomes/proposal-links.yaml
  closure.yaml
```

`version.yaml` pins version, tag, release commit, lifecycle status, creation
time, and explicit non-claims. `manifest.yaml` is rail-generated and indexes
runs plus review/consensus/synthesis state. Every captured run is immutable;
the same ticket may receive a new run ID, but no file is replaced.

### Rail commands and lifecycle

The standard-library/PyYAML CLI exposes:

1. `init` creates a new `COLLECTING` version root from a SemVer, matching tag,
   full release commit, and UTC timestamp. Existing destinations fail.
2. `capture` verifies `meta.yaml`, `triage/triage.yaml`, and
   `report/dossier.html`; requires the stamped plugin version and ticket to
   match; rejects any successful Jira response artifacts; copies only the
   dossier and registered minimal current-run evidence; writes hashes,
   receipt, run manifest, ticket index, and version manifest atomically.
3. `begin-review` closes collection after at least one capture. No later
   capture is accepted for that version cycle.
4. `add-review` imports one schema-valid authored review, requires its ticket,
   run, and dossier hash to match the receipt, validates unique finding IDs,
   and refuses overwrite.
5. `add-consensus` imports one schema-valid consensus after at least one
   review, validates every accepted/disputed finding reference, and refuses a
   second consensus for the run.
6. `synthesize` atomically imports findings, themes, and decisions only after
   every captured run has consensus. Occurrences must resolve to retained
   ticket/run/review/finding identities; themes and decisions must reference
   existing normalized findings.
7. `close` imports one closure only after synthesis. Counts must equal derived
   run/review/theme/decision totals, and proposal links must stay repository-
   relative under `docs/improvement-proposals/`.
8. `state` and `validate` perform no mutation. They validate hashes and schema,
   derive the current lifecycle, print allowed next commands, and exit 2 on a
   contract failure.

Lifecycle transitions are fixed:

```text
COLLECTING -> REVIEWING -> SYNTHESIZED -> CLOSED
```

Semantic freedom remains with reviewers: observations, expectations, impact,
evidence, consensus reasoning, normalized themes, and propose/monitor/reject
decisions. The model or human may author those files from checked-in templates
but may never write version indexes, receipts, manifests, hashes, lifecycle
state, or closure counts directly.

### Privacy and Jira boundary

Capture rejects `triage/jira/post-result.json` or
`triage/jira/attach-result.json`; a present posting-gate record must end in a
declined outcome. The minimal capture excludes `ticket.json`, every `aux-*`
fetch, Jira drafts/results, `history.ndjson`, and `runs/`. This supports the
declared no-Jira-delivery review flow while keeping raw Jira source material
out of the public repository. The external review root is still private and
may contain quoted ticket information already rendered in the dossier.

### 2026-08-05 amendment: canonical ownership and private Git storage

The company-owned canonical source is `AdCreative-ai/recon-plugin`; the public
`doruksahin/recon-plugin` repository is its personal-profile fork. Canonical
install, source, release, historical PR, and generated flow links point to the
organization repository. The fork remains a distribution and portfolio mirror,
never the review evidence store.

Live review evidence belongs to a distinct private GitHub repository, initially
`AdCreative-ai/recon-team-reviews`. Before `init`, the rail proves that the
operator-supplied review root is the top level of a real Git worktree, its
`origin` resolves to a GitHub `owner/repository` identity, the identity is not
the canonical or personal public plugin repository, and a live `gh repo view`
reports `PRIVATE`. It pins provider, repository identity, visibility, remote,
and verification time under `version.yaml.storage`.

Every later mutating command revalidates the current worktree identity, origin,
and live private visibility before writing. Read-only `state` and `validate`
prove the local root/origin still match the pinned storage identity without
requiring network access. A visibility change, remote swap, nested checkout,
missing GitHub CLI, unavailable visibility lookup, public repository, or path
inside the plugin source fails closed with exit 2 before any destination is
created or replaced. Tests inject a fake `gh` executable through a bounded
test-only environment override; production defaults to the real `gh` command.

### Routing and progressive disclosure

Root and evaluation `AGENTS.md` files route version-review work to the
repository-local `recon-version-review` skill. Narrow nested `AGENTS.md` files
link upward to the shared hard boundaries and sideways to the schema/rail
owners; they do not duplicate field lists or commands. The skill always runs
`state` first, invokes only rail-owned mutations, and hands semantic templates
to teammates without posting to Jira.

Accepted cross-ticket themes do not mutate Recon directly. `proposal-links`
points to a future planning cohort under `docs/improvement-proposals/`; selected
private evidence must be sanitized into `evals/cases/` before the existing
replay and improvement-loop skills can make a bounded change claim.

### Interface record

| Decision | Contract |
| --- | --- |
| Trigger | Operator asks to collect or review reports produced by one published Recon version. |
| Inputs | External root, SemVer/tag/release commit, verified current-run workspace, schema-valid semantic YAML. |
| Outputs | Version tree above, immutable hashes, derived state and exact allowed actions. |
| Freedom | Semantic feedback and synthesis only; no improvised paths, identities, hashes, or state transitions. |
| Side effects | Local external-root writes only; no Jira, target-repository, installed-plugin, release, or publication mutation. |
| Failure | Exit 2 with stable diagnostic; no partial destination or overwrite. |
| Verification | Focused clean/fault controls, generated-view checks, Decree lint, and full pre-commit guardrail. |

## Testing Strategy

`tools/test-version-review.sh` uses isolated temporary workspaces and review
roots to prove the complete clean lifecycle plus bounded failures: invalid
version/tag/commit identities, source/version/ticket drift, missing dossier,
Jira mutation artifacts, non-declined posting gates, symlink leaves and
ancestors, overlapping roots, duplicate capture/review/consensus/synthesis,
tampered artifacts or manifests, review hash drift, unknown finding references,
premature synthesis/closure, unsafe proposal paths, derived-count mismatch,
and exception cleanup.

The control must also verify that raw `ticket.json`, auxiliary responses, Jira
delivery files, history, and archived runs never enter a capture; a second run
for one ticket remains distinct; `state` reports each lifecycle; and all
checked-in templates validate. `tools/check-coherence.sh` runs the focused
control as a universal repository check. System-map generation and its focused
test must render the new repository-only layer from live source references.

The private-Git amendment adds controls for a clean private origin plus missing
Git, nested root, plugin-contained root, malformed/non-GitHub origin, origin
identity drift, unavailable `gh`, invalid visibility output, public visibility,
and a repository that becomes public between lifecycle mutations. It also
checks the pinned storage receipt, proves read-only state remains locally
derivable after the live visibility command becomes unavailable, and clears
inherited Git-hook repository variables before addressing the external review
worktree so a hook cannot redirect or mutate the plugin repository.

After focused controls, run links, coherence, adapters, all existing replay and
improvement controls, Decree lint/progress, and `bash tools/pre-commit-check.sh`.
Synthetic controls establish rail correctness only. A real workflow claim
requires at least three representative ticket reports reviewed under one
plugin version, with retained private receipts and independent teammate input.

## Acceptance Criteria

- [x] A version-scoped external tree and schema own all lifecycle states, fields, enums, and minimal capture paths.
- [x] Init, capture, begin-review, add-review, add-consensus, synthesize, close, state, and validate implement the fixed interface and stable exit behavior.
- [x] Captures are immutable, hash-verified, symlink-safe, version/ticket-bound, and exclude every declared raw/Jira/history/archive path.
- [x] Review, consensus, synthesis, proposal-link, and closure references fail closed on unknown or drifted identities.
- [x] Root plus nested agent routers link to authoritative owners without duplicating schema or mutation rules.
- [x] The repository-local operator skill keeps live review roots outside the repository and routes selected findings into existing replay/improvement rails.
- [x] The v0.23 planning cohort, proposal record, implementation plan, evals entry docs, tool ownership table, and generated system map describe one consistent bounded workflow.
- [x] Focused controls exercise the complete lifecycle and every bounded failure class, including no-overwrite and exception cleanup.
- [x] Decree intent-check names this SPEC as authoritative for every changed path, and Decree lint/progress pass.
- [x] The full pre-commit guardrail passes without modifying shipped Recon runtime, plugin versions, retained replay evidence, or published artifacts.
- [x] Canonical install, source, flow, release, PR, and commit links resolve through `AdCreative-ai/recon-plugin`, while `doruksahin/recon-plugin` remains its public fork.
- [x] `init` accepts only a top-level private GitHub review repository outside the plugin source and pins its verified storage identity in `version.yaml`.
- [x] Every version-review mutation revalidates live private visibility and fails before writes when Git, origin, identity, visibility lookup, or privacy drifts.
- [x] Read-only `state` and `validate` remain network-independent while proving the local worktree and origin match the pinned storage identity.
- [x] Focused controls cover clean private storage, public and malformed origins, nested/plugin roots, lookup failure, identity drift, privacy drift, and no-partial-write behavior.
- [x] `AdCreative-ai/recon-team-reviews` is private, initialized at `versions/v0.19.0`, and contains only generic cycle metadata before live ticket capture.
- [x] The amended generated views, Decree completion report, links, coherence controls, and full pre-commit guardrail pass.

### Deferred

- [ ] Demonstrate the workflow on three private real-ticket reports with independent teammate reviews before claiming team-review quality.
- [ ] Automate shared-drive or private-repository synchronization; v1 owns only local external-root structure and validation.
