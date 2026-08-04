# Evidence audit: recorded repro runtime

Use this shipped v0.16 change to calibrate claim strength. It is not a victory
narrative.

## Source record

- [Proposal](../../improvement-proposals/0.16.0/proofshot-repro-runtime/README.md)
- [Implementation plan](../../plans/2026-08-02-proofshot-repro-runtime.md)
- [Implemented specification](../../../decree/spec/reliability/evidence/spec-01kz1bd2v986mytyd6pcb02bgx-recon-0-16-0-recorded-repro-runtime.md)
- [`record-repro.sh`](../../../recon/scripts/record-repro.sh),
  [`verify-repro.sh`](../../../recon/scripts/verify-repro.sh), and
  [verifier fixtures](../../../tools/test-artifact-verifiers.sh)

## Spectrum move

The v0.15 verifier proved package structure but could not prove written steps
matched browser actions that happened. v0.16 replaced an instructional ban on
fabrication with a recorder rail, action log, video, and exhibit cross-check.
Visual meaning remained judgment over retained evidence.

## Evidence audit

| Claim | Evidence | Level | Admissible conclusion |
| --- | --- | --- | --- |
| Rail `exec` requires active recording | Stubbed recorder fixture exercises guard and exit | E2 | The tested rail rejects that unrecorded path |
| Missing session, unmatched exhibit, bad order, schema drift, stale time, and corrupt video are rejected | Negative fixtures assert each diagnostic | E2 | The verifier enforces those bounded properties |
| Recorder preflight rejects missing or mismatched tools | Host-contract fixtures cover both cases | E2 | The tested preflight fails closed |
| Flow worked on ATT-5107 on 2 August 2026 | Proposal names a recorded welcome-modal repro | E1 in this checkout | Traceable report, but no retained session or external evidence ID is auditable here |
| Driving quality generalizes | Plan required two or three tasks; proposal cites one | Unproven | Do not claim general driving reliability |
| Live Claude Code/Codex outcomes are equivalent | Shared CLI contract and fixtures, no paired retained live runs | E2 contract only | Do not claim equivalent live-host outcomes |

## Rerunnable E2 demonstration

```bash
bash tools/test-artifact-verifiers.sh
bash tools/test-host-contract.sh
```

Observed on 4 August 2026 at tag `v0.18.0`:

```text
artifact verifiers: PASS — 130 isolated cases
host contract: PASS
```

## Evidence still required

ATT-5107 reaches E3 only with a durable pointer to its commits, start state,
commands, session log/video, generated repro artifacts, verifier output, and
consumer consequence. A general workflow claim additionally needs at least two
more representative real tasks and every host named in the conclusion.

Implementation may ship with bounded evidence. Reporting may not turn that
delivery state into a broader outcome claim.
