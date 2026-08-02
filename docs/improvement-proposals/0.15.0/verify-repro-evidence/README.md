# Verify live repro evidence

> Verify every repro step is fresh, numbered, and backed by a contained PNG with valid structure

- **Status:** shipped (v0.15.0)
- **Priority:** P1
- **Theme:** determinism rail
- **Origin:** Static repro audit on 2 Aug 2026 found no content validator between
  screenshot capture and use in a gate, dossier, SPEC smoke check, or PR.

## Problem

In v0.14.1, `recon-repro` correctly banned fabrication, but enforcement ended at
workspace filenames. A zero-byte PNG, an exhibit not referenced by any step, a
missing start state, or a `repro.md` link to the wrong screenshot could pass
workspace lint.

The same evidence was reused by four company-facing consumers, so one bad capture
propagated into the approval gate, implementer brief, dossier, and eventual PR.

The first verifier draft still read raw Markdown. This meant a numbered step
could hide its only exhibit token inside `<!-- ... -->` and pass even though a
human reading the rendered step saw no evidence link.

## Before (v0.14.1)

```text
repro/repro.md: 1. Open Collections → baseline [exhibits/1-baseline.png]
repro/exhibits/1-baseline.png: 0 bytes
repro/exhibits/2-old-run.png: valid but unreferenced

$ bash recon/scripts/lint-workspace.sh ATT-6002
lint: clean
```

The artifact registry was satisfied even though the evidence was unusable.

The raw-token bypass looked valid to the parser but not to a reviewer:

```markdown
1. Open Collections → Collection3 is visible.
   <!-- [exhibits/1-baseline.png] -->
```

## After (implemented)

```text
$ RECON_ROOT=/tmp/recon bash recon/scripts/verify-repro.sh ATT-6002
REPRO: exhibits/1-baseline.png: invalid PNG signature
REPRO: orphan exhibits not referenced by numbered repro steps: exhibits/2-old-run.png
REPRO: exhibits/2-old-run.png: mtime predates this run by 86400s (tolerance 2s)

$ RECON_ROOT=/tmp/recon bash recon/scripts/verify-repro.sh ATT-6002
REPRO: repro.md body line 4: step 1 must reference exactly one exhibit (got 0)

$ bash tools/test-artifact-verifiers.sh
artifact verifiers: PASS — 69 isolated cases
```

Success means every step visibly references a regular, non-symlinked exhibit
inside the current workspace; every exhibit is used; and each PNG has bounded
and ordered chunks, valid per-chunk CRCs, a complete IDAT zlib stream, and a
terminal IEND with no trailing bytes. Only numbered steps own exhibits: a
question, prose reference, or HTML-comment token cannot prevent orphan detection.
Coarse timestamps must fit the current run, and an honest failure contains no
invented screenshots. The practical outcome is that every evidence link the
machine credits is also present for the human gate. These checks do not decode
or prove what the screenshot visually shows.

## Implementation sketch

- Add *verify-repro.sh* to check start-state shape, contiguous steps, visible
  comment-masked exhibit references, path containment and symlinks, PNG chunk bounds/order, CRCs,
  complete IDAT zlib streams, terminal IEND, freshness, and orphan files.
- Allow an honest `reproduced: false` form with observation and reason, but no
  success-only exhibit requirements.
- Invoke the verifier before evidence is shown or returned to the calling skill.
- Add valid, missing, corrupt, truncated, bad-CRC, invalid-IDAT, trailing-byte,
  symlink-escape, stale, orphan, question-only-reference, comment-hidden-token,
  and honest-failure fixtures; every failing case asserts its intended diagnostic.
- Keep visual truth judgment in the model; the rail validates provenance and
  structure, not screenshot meaning.

Implemented under
*SPEC-01KZ14Q6A2WB6J6TTX3XWQC5QJ Recon 0.15.0 Verified Handoff Chain*.

## Open questions

- Filesystem timestamp precision varies. Compare against run start with a small
  documented tolerance as a provenance signal, while keeping visual truth as a
  model check performed after capture.
