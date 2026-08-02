---
date: '2026-08-02'
governs:
- recon/scripts/
- recon/skills/
- recon/docs/hosts.md
- recon/docs/pipeline.md
- tools/
id: SPEC-01KZ14Q6A2WB6J6TTX3XWQC5QJ
references:
- ADR-01KZ0ZK4WYVWRY0WJM2CZ7ZS8C
status: approved
---

# SPEC-01KZ14Q6A2WB6J6TTX3XWQC5QJ Recon 0.15.0 Verified Handoff Chain

## Overview

Strengthen the company-facing Recon chain at the boundary where model-authored
evidence becomes an approved implementation handoff. Add mechanical validation
for live repro evidence and Discovery packages, fix Discovery's current ordering
so mandatory repro runs before the brief that consumes it, and fix state
derivation for legitimate no-brief routes.

As small enabling changes, collapse the repeated host bootstrap into one
pure-output `reconctl.sh start <base|triage>` command and constrain skill
descriptions to a measured routing-metadata budget. These do not freeze runtime
identity: every later rail and ledger event continues detecting its current host
and surface.

Decree route automation, deterministic dossier rendering, and Jira delivery are
explicitly out of scope. Agent review found that they require, respectively, a
company routing-policy decision, stable verified source schemas, and a dedicated
fake-Jira retry/concurrency design.

## Technical Design

### Atomic bootstrap

Add an additive `start` command to `reconctl.sh`. It resolves root, host, surface,
and capabilities once, then runs the requested preflight in the same process. It
prints stable key-value output and creates no context file or durable state.
Existing scalar commands remain compatible. Seven stage skills call `start` once
before their first mutation; `recon-help` continues using `doctor.sh`.

### Repro contract and verifier

`repro/repro.md` gains fixed frontmatter fields: `recon: repro`, `ticket`,
`reproduced: true|false`, `start_state`, and `failure_reason`. A successful repro
contains contiguous numbered steps; every step references one relative
`exhibits/<n>-<slug>.png`. An honest failure requires a non-empty reason and no
invented success evidence.

`verify-repro.sh` delegates to a dependency-free Python engine. It validates the
frontmatter, contiguous step numbering, safe relative references, PNG signature
and IHDR dimensions, no missing or orphan exhibits, and a coarse current-run
mtime check. These are structure and provenance signals only. The skill still
reads each screenshot and judges whether it visually shows the claimed state.

### Discovery contract and verifier

Every Discovery scenario has a stable ID in one of three namespaces: `REQ-N`,
`REG-N`, or `OPEN-N`. Implementation-brief acceptance checkboxes carry the same
IDs. Gate resolution keys match the `OPEN-N` IDs exactly.

Mandatory UI repro moves before brief generation. The repro verifier passes
before numbered steps are copied into Manual verification. A new
`verify-discovery.sh <TICKET> pre-gate|post-gate` command validates:

- scenario IDs are unique and each scenario has Gherkin content;
- implementation briefs have checkbox parity with all scenarios and contain the
  required sections, including Manual verification;
- problem statements contain their required sections;
- `brief_kind: none` has no brief requirement;
- pre-gate packages have a valid route and handoff;
- post-gate packages have a parseable approval record and exactly the OPEN
  resolutions required by the contract.

Discovery runs pre-gate verification before asking for approval and post-gate
verification before printing handoff. `derive-state.sh` reads `brief_kind` and
treats a missing brief as valid for `none`, removing the current contradiction.

### Skill metadata budget

Shorten all eight descriptions to outcome-plus-trigger text no longer than 200
Unicode characters. Adapter generation rejects empty, duplicate, or over-budget
descriptions. User-facing skills require concrete trigger language; the internal
Decree adapter may use `Invoked by` instead. This is a bounded context reduction,
not proof of model activation quality.

## Testing Strategy

Add `tools/test-artifact-verifiers.sh` with isolated fixtures covering successful
and failed repros, corrupt/stale/orphan exhibits, READY/OPEN/rejected/no-scenario
Discovery packages, scenario/checkbox drift, missing Manual verification, and
`brief_kind: none`. Extend `tools/test-host-contract.sh` for the atomic start
output and prove later events still record changed host identity.

Run shell syntax, adapter generation/check, link check, coherence check, host
contract, artifact verifier fixtures, Decree lint/progress, and a workspace lint
smoke. No Jira mutation, artifact publication, or implementation handoff runs as
part of the tests.

## Acceptance Criteria

- [ ] `reconctl.sh start base|triage` emits one coherent runtime/capability/preflight snapshot while all existing commands remain compatible.
- [ ] Seven stage skills use the atomic bootstrap and later rails retain current-host provenance.
- [ ] Every skill description is non-empty, unique, at most 200 Unicode characters, and carries an appropriate trigger cue.
- [ ] Successful repro packages pass structural/provenance validation before any caller consumes them.
- [ ] Honest failed repros pass with a reason and without fabricated success exhibits.
- [ ] Mandatory UI repro runs and verifies before Discovery drafts Manual verification.
- [ ] Scenario IDs, brief checkboxes, OPEN resolutions, route/brief shape, and handoff are mechanically verified before gate and handoff.
- [ ] `brief_kind: none` reaches the approval gate and handed-off state without requiring `spec-draft.md`.
- [ ] Artifact-verifier fixtures cover clean and failing cases without network or user credentials.
- [ ] Adapter, link, coherence, host-contract, verifier, shell-syntax, Decree, and diff checks pass.

## Deferred

- [ ] Compile Decree routing after a company owner defines the missing semantic route policy.
- [ ] Render dossiers mechanically after Discovery and repro contracts prove stable in real runs.
- [ ] Build digest-bound Jira delivery in a dedicated release with fake-Jira concurrency and retry coverage.
