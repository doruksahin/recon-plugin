---
date: '2026-08-02'
governs:
- README.md
- docs/flow.html
- recon/scripts/
- recon/skills/
- recon/docs/hosts.md
- recon/docs/pipeline.md
- recon/docs/workspace-index.md
- tools/
id: SPEC-01KZ14Q6A2WB6J6TTX3XWQC5QJ
references:
- ADR-01KZ0ZK4WYVWRY0WJM2CZ7ZS8C
status: implemented
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
Existing scalar commands remain compatible. Seven pipeline and maintainer skills
call `start` once before their first mutation; `recon-help` continues using
`doctor.sh`.

### Repro contract and verifier

`repro/repro.md` gains fixed frontmatter fields: `recon: repro`, `ticket`,
`reproduced: true|false`, `start_state`, and `failure_reason`. A successful repro
contains contiguous numbered steps; every step visibly references one relative
`exhibits/<n>-<slug>.png`. An honest failure requires a non-empty reason and no
invented success evidence. Numbered steps are the only owners of exhibits: a
PNG reference elsewhere in the document is a violation, and a token hidden in
an HTML comment cannot satisfy a step or rescue an otherwise orphaned file.

`verify-repro.sh` delegates to a dependency-free Python engine. It accepts only
regular, non-symlinked inputs inside the current workspace and validates the
frontmatter, contiguous step numbering, comment-masked safe relative references,
PNG chunk bounds/order and CRCs, a complete IDAT zlib stream, terminal IEND, no
missing or orphan exhibits, and a coarse current-run mtime check. These are
structure and provenance signals only. The skill still reads each screenshot
and judges whether it visually shows the claimed state.

### Discovery contract and verifier

Every Discovery scenario has a visible stable H2 ID in one of three namespaces:
`REQ-N`, `REG-N`, or `OPEN-N`. A shared Markdown view prevents HTML comments,
fenced examples, and indented code from becoming structural headings, no-
scenario declarations, acceptance checkboxes, or problem-statement entries.
Rendered fenced Gherkin may still belong to a real visible scenario heading.
Implementation-brief checkboxes or problem-statement entries carry exactly the
same ID set as visible single-line joins. Gate resolution keys match the
`OPEN-N` IDs exactly; an approved resolution is copied verbatim into its visible
same-ID brief entry so the human choice cannot disappear before implementation.

Mandatory UI repro moves before brief generation. The repro verifier passes
before numbered steps are copied into Manual verification. A new
`verify-discovery.sh <TICKET> pre-gate|post-gate` command validates:

- visible scenario IDs are unique and each scenario has rendered Gherkin content;
- routing retains non-empty producer, matched-rule, unmatched-rule, governance,
  a full SHA-1/SHA-256 commit object ID, and block-scalar handoff fields with
  placeholders, malformed, duplicate, or unknown envelope fields rejected;
- implementation briefs have visible checkbox parity with all scenarios and
  contain the required sections, including Manual verification;
- problem statements contain their required sections, exact visible single-line
  scenario-entry parity, and one deterministic Open choices entry per OPEN ID;
- `brief_kind: none` has no brief requirement;
- pre-gate packages have a valid route and handoff;
- post-gate packages have a parseable approval record and exactly the OPEN
  resolutions required by the contract; approved outcomes match their same-ID
  destination verbatim.

Discovery runs pre-gate verification before asking for approval and post-gate
verification before printing handoff. `derive-state.sh` reads `brief_kind` and
treats a missing brief as valid for `none`, removing the current contradiction.

### Skill metadata budget

Shorten all eight descriptions to outcome-plus-trigger text no longer than 200
Unicode characters. Adapter generation rejects empty, duplicate, or over-budget
descriptions. User-facing skills require concrete trigger language; the internal
Decree adapter may use `Invoked by` instead. This is a bounded context reduction,
not proof of model activation quality.

### Activation attestation

Harden Codex activation so the report describes the materialized plugin bytes,
not the source checkout's intent. Read the configured marketplace root from
Codex's JSON. Clean same-origin source and configured checkouts must share the
released HEAD and version after synchronization. Reject ignored/untracked,
sparse/assume-unchanged, missing, or special plugin entries; deterministically
hash relative paths, regular-file bytes, symlink targets, and executable bits,
then require source/configured tree equality. Repeat HEAD, version, cleanliness,
path, and tree attestation after `codex plugin add`, then require Codex's JSON to
report the expected enabled version and attested source path. Repeat the complete
checkout and materialized-tree attestation after that query, immediately before
printing `activated`.

## Testing Strategy

Add `tools/test-artifact-verifiers.sh` with isolated fixtures covering successful
and failed repros, corrupt/truncated/stale/orphan, question-only, or symlinked
exhibits, READY/OPEN/rejected/no-scenario Discovery packages, both brief kinds,
scenario-ID and approved-resolution drift, the generic and Decree route shapes,
route-envelope omission/placeholder/malformed/duplicate/unknown cases, hidden
HTML-comment/code scenario and brief evidence, visible-heading fenced Gherkin,
missing Manual verification, and `brief_kind: none`. Extend
`tools/test-host-contract.sh` for the atomic start output and prove later events
still record changed host identity. Add a
fake-Codex activation contract covering a separate-clone fast-forward plus stale
installs, dirty checkouts, post-sync dirtiness, same-version/different-content
branches, ignored rogue skills, sparse/assume-unchanged entries, post-add
mutation, and list-time ignored mutation.

Run shell syntax, adapter generation/check, link check, coherence check, host
contract, artifact verifier fixtures, Decree lint/progress, and a workspace lint
smoke. No Jira mutation, artifact publication, or implementation handoff runs as
part of the tests.

## Acceptance Criteria

- [x] `reconctl.sh start base|triage` emits one coherent runtime/capability/preflight snapshot while all existing commands remain compatible.
- [x] Seven pipeline and maintainer skills use the atomic bootstrap and later rails retain current-host provenance.
- [x] Every skill description is non-empty, unique, at most 200 Unicode characters, and carries an appropriate trigger cue.
- [x] Successful repro packages pass structural/provenance validation before any caller consumes them.
- [x] Honest failed repros pass with a reason and without fabricated success exhibits.
- [x] Mandatory UI repro runs and verifies before Discovery drafts Manual verification.
- [x] Visible scenario IDs/declarations, both brief shapes, same-ID approved OPEN outcomes, the complete route producer/trace/full-Git-object envelope, route/brief shape, and block-scalar handoff are mechanically verified before gate and handoff.
- [x] `brief_kind: none` reaches the approval gate and handed-off state without requiring `spec-draft.md`.
- [x] Artifact-verifier fixtures cover clean and failing cases without network or user credentials.
- [x] Codex activation binds clean same-origin checkouts to the released HEAD/version, attests exact materialized plugin-tree equality before/after installation and after the install report, and verifies the actual enabled version/source path before success.
- [x] Adapter, link, coherence, host-contract, verifier, shell-syntax, Decree, and diff checks pass.

## Completed Outcome

Recon's company handoff now crosses two mechanical trust boundaries: live repro
evidence must be a contained, structurally valid current-run package, and the
Discovery contract, routed brief, human decision, and printed handoff must agree
on stable IDs and the approved outcome. Legitimate no-brief work reaches its
approval and handed-off states without a phantom draft requirement.

Validation completed on 2026-08-02. The isolated suite passed 69 clean and
adversarial artifact cases, including symlink escapes, malformed PNG containers,
question-only and comment-hidden exhibit references, both brief shapes, hidden
comment/code IDs and checkboxes, route-envelope omissions, malformed and
duplicate fields, and approved-resolution drift. The host contract passed with
seven atomic starts replacing 35 documented setup operations while preserving
later-host provenance. All eight descriptions
measured 1,477 characters, down 689 (31.8%), and the adapter gate proved every
description unique, cued, and at most 200 characters. A fake two-clone Codex
contract rejected dirty, stale, same-version/different-content, ignored-rogue,
sparse-omission, post-add-mutation, and list-time ignored-mutation cases. It
accepted only exact release-commit, materialized-tree, version, and path identity
through the final pre-success attestation.

A forward agent also ran the actual Discovery skill against a frozen READY
maintenance ticket with no behavioral scenario. It produced the direct/no-brief
route, passed pre-gate verification, workspace lint, and state derivation, then
stopped at the human approval gate without creating a fictional brief. Link,
coherence, shell/Python syntax, generated-adapter, Decree, and diff checks all
passed. No Jira mutation, release, activation, or artifact publication occurred
during implementation validation.

## Deferred

- [ ] Compile Decree routing after a company owner defines the missing semantic route policy.
- [ ] Render dossiers mechanically after Discovery and repro contracts prove stable in real runs.
- [ ] Build digest-bound Jira delivery in a dedicated release with fake-Jira concurrency and retry coverage.
