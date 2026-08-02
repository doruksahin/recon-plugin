# Verify the discovery package as one contract

> Fail discovery when scenarios, brief, gate, and repro references do not agree

- **Status:** shipped (v0.15.0)
- **Priority:** P1
- **Theme:** determinism rail
- **Origin:** Static artifact audit on 2 Aug 2026 found that workspace lint checks
  filenames but cannot detect a scenario/acceptance-criterion mismatch. It also
  found that Discovery drafts the brief before invoking mandatory UI repro even
  though the brief must copy those repro steps.

## Problem

In v0.14.1, Discovery promised acceptance criteria derived 1:1 from Gherkin
scenarios and a self-sufficient Manual verification section. Those were prose
invariants. A package with three scenarios, two checkboxes, and no repro steps
still passed workspace lint because every filename was declared.

The implementer then received an incomplete contract: tests could pass while one
approved behavior was never implemented or manually checked.

The first verifier draft exposed a second P1 bypass: it counted raw ID tokens
and checkboxes. An agent could put a required ID in an HTML comment, a fenced
example, or four-space-indented code and still receive `verify: clean`, even
though the implementer-facing Markdown showed no acceptance entry. The same
shadow-content problem let hidden scenario headings create the source contract.

There was a second concrete contradiction: `brief_kind: none` told Discovery to
skip `spec-draft.md`, while `derive-state.sh` treated that missing brief as
permanently in progress and rejected a gate without it.

## Before (v0.14.1 and the first verifier draft)

```text
discovery/discovery.md: Scenario REQ-1, REQ-2, REG-1
discovery/spec-draft.md: [ ] REQ-1, [ ] REQ-2
Manual verification: section absent
route/routing.yaml: brief_kind=implementation-brief

workflow order: draft brief → run mandatory UI repro
result: repro steps arrived after the brief that had to contain them

$ bash recon/scripts/lint-workspace.sh ATT-6001
lint: clean
```

`REG-1` disappeared and the brief was not self-sufficient, but nothing failed.

The initial parity check could also be satisfied by content that Markdown does
not present as the contract:

````markdown
<!-- REQ-1 — hidden requirement -->

```markdown
- [ ] REG-1 — example only
```

    OPEN-1 — A — Collection2 becomes selected
````

All three IDs were found in raw text, and the indented OPEN line could even bind
the approved resolution. The human-visible handoff still omitted all three.

## After (implemented)

```text
$ RECON_ROOT=/tmp/recon bash recon/scripts/verify-discovery.sh ATT-6001 pre-gate
DISCOVERY: acceptance criteria missing scenario IDs: REG-1
DISCOVERY: spec-draft.md missing required section 'Manual verification'

$ RECON_ROOT=/tmp/recon bash recon/scripts/verify-discovery.sh ATT-6001 post-gate
DISCOVERY: approved resolution for OPEN-1 is not copied verbatim into its same-ID brief entry

$ RECON_ROOT=/tmp/recon bash recon/scripts/verify-discovery.sh ATT-6001 post-gate
DISCOVERY: problem statement missing scenario IDs: OPEN-1, REG-1, REQ-1

$ RECON_ROOT=/tmp/recon bash recon/scripts/verify-discovery.sh ATT-6001 pre-gate
DISCOVERY: routing.matched_rule must be non-empty
DISCOVERY: routing.evidence.repo_commit must be a full 40- or 64-character lowercase Git object ID

$ bash tools/test-artifact-verifiers.sh
artifact verifiers: PASS — 69 isolated cases
```

Success requires visible scenario headings/declarations, exact visible
scenario-ID parity in either brief shape, a verbatim visible same-ID destination
for every approved OPEN resolution, the correct structure for `brief_kind`, a
complete producer/rule-trace route envelope with a full SHA-1/SHA-256 commit
object ID, and a Manual verification section that copies verified repro evidence
and cannot predate it. Hidden comments and code examples cannot become contract
evidence; rendered fenced Gherkin remains valid beneath a real heading. Missing,
malformed, duplicate, or invented route fields fail without asking the verifier
to judge the producer's semantic rule choice. The outcome is direct: every
approved behavior is visible to the implementer and test author, rather than
merely discoverable by a regex.

## Implementation sketch

- Give every required, regression, and OPEN scenario a visible stable H2 ID
  carried into visible single-line implementation checkboxes or problem-
  statement entries and gate resolutions.
- Move mandatory repro before brief generation, then verify the repro before its
  steps are copied into Manual verification.
- Add *verify-discovery.sh* plus a small parser with commands for pre-gate and
  post-gate validation.
- Check H2 scenario parity for both brief kinds, the fixed route envelope and
  full nested Git object ID, route/brief compatibility, required sections, exact
  approved-resolution joins, repro/brief copy and mtime ordering, safe
  non-symlinked paths, and a block-scalar handoff.
- Derive structural and join checks from one semantic Markdown view that masks
  comments and excludes fenced/indented examples while retaining rendered code
  for section content and Gherkin beneath a real heading.
- Invoke it before presenting the gate and again before printing the handoff.
- Add golden READY, Decree-route, OPEN-approved, OPEN-rejected, problem-statement,
  resolution-drift, route-envelope omission/placeholder/malformed/duplicate/unknown,
  hidden-comment/fenced/indented evidence, missing/unknown ID, no-scenario,
  repro-drift, and symlink fixtures.
- Teach state derivation that `brief_kind: none` legitimately has no
  `spec-draft.md`.

Implemented under
*SPEC-01KZ14Q6A2WB6J6TTX3XWQC5QJ Recon 0.15.0 Verified Handoff Chain*.

## Open questions

- Regression scenarios should remain acceptance checkboxes because "must not
  change" is implementation scope, but they can be visually grouped separately.
