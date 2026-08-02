# Verify live repro evidence

> Verify every repro step is fresh, numbered, and backed by a valid screenshot

- **Status:** in-progress
- **Priority:** P1
- **Theme:** determinism rail
- **Origin:** Static repro audit on 2 Aug 2026 found no content validator between
  screenshot capture and use in a gate, dossier, SPEC smoke check, or PR.

## Problem

`recon-repro` correctly bans fabrication, but enforcement ends at workspace file
names. A zero-byte PNG, an exhibit not referenced by any step, a missing start
state, or a `repro.md` link to the wrong screenshot can pass workspace lint.

The same evidence is reused by four company-facing consumers, so one bad capture
propagates into the approval gate, implementer brief, dossier, and eventual PR.

## Before (today)

```text
repro/repro.md: 1. Open Collections → baseline [exhibits/1-baseline.png]
repro/exhibits/1-baseline.png: 0 bytes
repro/exhibits/2-old-run.png: valid but unreferenced

$ bash recon/scripts/lint-workspace.sh ATT-6002
lint: clean
```

The artifact registry is satisfied even though the evidence is unusable.

## After (proposed)

```text
$ recon verify repro ATT-6002
start state: PASS — command + route present
steps: PASS — 1 contiguous numbered action
exhibit 1: FAIL — PNG is empty or undecodable
orphan exhibit: FAIL — exhibits/2-old-run.png is not referenced
freshness: FAIL — exhibit predates meta.yaml started
verify-repro: 3 violation(s)
```

Success means every step references existing decodable evidence whose basic file
provenance is consistent with the current run, every exhibit is used, and a
failed reproduction is explicitly represented without invented screenshots.
Timestamps and PNG structure do not prove what the screenshot visually shows.

## Implementation sketch

- Add *verify-repro.sh* to check start-state shape, contiguous steps, exhibit
  references, image signatures/dimensions, freshness, and orphan files.
- Allow an honest `reproduced: false` form with observation and reason, but no
  success-only exhibit requirements.
- Invoke the verifier before evidence is shown or returned to the calling skill.
- Add valid, missing, corrupt, stale, orphan, and honest-failure fixtures.
- Keep visual truth judgment in the model; the rail validates provenance and
  structure, not screenshot meaning.

## Open questions

- Filesystem timestamp precision varies. Compare against run start with a small
  documented tolerance as a provenance signal, while keeping visual truth as a
  model check performed after capture.
