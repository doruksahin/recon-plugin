# Verify the discovery package as one contract

> Fail discovery when scenarios, brief, gate, and repro references do not agree

- **Status:** in-progress
- **Priority:** P1
- **Theme:** determinism rail
- **Origin:** Static artifact audit on 2 Aug 2026 found that workspace lint checks
  filenames but cannot detect a scenario/acceptance-criterion mismatch. It also
  found that Discovery drafts the brief before invoking mandatory UI repro even
  though the brief must copy those repro steps.

## Problem

Discovery promises acceptance criteria derived 1:1 from Gherkin scenarios and a
self-sufficient Manual verification section. Those are prose invariants. A package
with three scenarios, two checkboxes, and no repro steps still passes workspace
lint because every filename is declared.

The implementer then receives an incomplete contract: tests can pass while one
approved behavior is never implemented or manually checked.

There is a second concrete contradiction: `brief_kind: none` tells Discovery to
skip `spec-draft.md`, while `derive-state.sh` currently treats that missing brief
as permanently in progress and rejects a gate without it.

## Before (today)

```text
discovery/discovery.md: Scenario REQ-1, REQ-2, REG-1
discovery/spec-draft.md: [ ] REQ-1, [ ] REQ-2
Manual verification: section absent
route/routing.yaml: brief_kind=implementation-brief

workflow order: draft brief → run mandatory UI repro
result: repro steps arrive after the brief that must contain them

$ bash recon/scripts/lint-workspace.sh ATT-6001
lint: clean
```

`REG-1` disappeared and the brief is not self-sufficient, but nothing fails.

## After (proposed)

```text
$ recon verify discovery ATT-6001
contract: FAIL — scenario REG-1 has no acceptance checkbox
brief: FAIL — Manual verification section missing
route: PASS — implementation-brief requires spec-draft.md
gate: SKIP — not answered yet
verify-discovery: 2 violation(s)
```

Success requires 1:1 scenario IDs, explicit treatment of every OPEN resolution,
the correct brief shape for `brief_kind`, and valid manual-verification references.

## Implementation sketch

- Give every required, regression, and OPEN scenario a stable ID carried into
  acceptance checkboxes and gate resolutions.
- Move mandatory repro before brief generation, then verify the repro before its
  steps are copied into Manual verification.
- Add *verify-discovery.sh* plus a small parser with commands for pre-gate and
  post-gate validation.
- Check scenario/checkbox parity, route/brief compatibility, forbidden prose
  unknowns, required evidence syntax, Manual verification, and handoff presence.
- Invoke it before presenting the gate and again before printing the handoff.
- Add golden READY, OPEN, rejected, no-scenario, and failed-repro fixtures.
- Teach state derivation that `brief_kind: none` legitimately has no
  `spec-draft.md`.

## Open questions

- Regression scenarios should remain acceptance checkboxes because "must not
  change" is implementation scope, but they can be visually grouped separately.
