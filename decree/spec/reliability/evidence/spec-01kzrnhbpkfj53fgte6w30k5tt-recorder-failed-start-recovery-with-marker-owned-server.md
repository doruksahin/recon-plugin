---
date: '2026-08-11'
governs:
- recon/scripts/record-repro.sh
- tools/test-artifact-verifiers.sh
id: SPEC-01KZRNHBPKFJ53FGTE6W30K5TT
references:
- ADR-01KZ0ZK4WYVWRY0WJM2CZ7ZS8C
status: implemented
---

# SPEC-01KZRNHBPKFJ53FGTE6W30K5TT Recorder Failed-Start Recovery With Marker-Owned Server Shutdown

## Overview

`proofshot start` has one failure mode that strands state: recording
initialization fails while an agent-browser session is already active, so the
partial session and any dev server the recorder launched outlive the failed
`record-repro.sh start`. Invariant 9 forbids converting that into unrecorded
browsing, but a stranded active session also blocks the next attempt.

This work originated outside the source repository: the implementation was
authored directly inside the installed Claude marketplace mirror at
`~/.claude/plugins/marketplaces/recon-plugin` (then at v0.18.0), which the
Change protocol forbids. It was recovered as a patch and ported here. The
ported recovery carried a defect that is corrected in this SPEC rather than
shipped: it resolved the dev-server port by scraping proofshot's stdout
(`Dev server started on :PORT`) and then killed whatever `lsof` reported on
that port. proofshot's prose cannot distinguish "this recording started the
server" from "a server was already running", so on a developer who already had
a dev server on that port, the recovery killed theirs.

**Falsifiable claim:** on the active-recording start failure, the rail stops and
closes a discoverable partial agent-browser session, stops a dev server only
when the session marker records `serverAlreadyRunning: false` with a port,
retries `start` exactly once, and leaves a persistent failure as an honest
failed-repro finding with no staging residue — while a dev server the recording
did not start is never signalled as stopped and never killed.

This is a bounded recorder-rail behavior change. It does not alter repro
evidence schemas, `verify-repro.sh`, invariant numbering, or any published
artifact. Passing isolated stub controls proves this rail behavior only; it does
not claim broader repro quality improvement.

## Technical Design

`repro/session-staging/.session.json` is the single owner of dev-server
ownership. Two helpers in `record-repro.sh` express that once:

- `owned_server_port` reads the marker and prints a port only when
  `serverAlreadyRunning is False` and a port is present. Empty output means
  "this run owns nothing", so callers kill nothing.
- `stop_owned_server` kills only a non-empty resolved port's holders and emits
  the caller's message. Absent `lsof`, it is a no-op.

Both the `stop` path and `recover_failed_start` call these helpers, so the
ownership rule exists in exactly one place. `recover_failed_start` resolves the
stranded agent-browser session from proofshot's own failure output, falling back
to the single staging directory it created; it stops and closes that session,
then releases only an owned server. A successful close authorizes exactly one
retry; a second failure cleans staging and reports the honest failure.

The marker may already exist when `start` fails — the failure happens after
proofshot writes it — so the same authority is available on both paths.

## Testing Strategy

`tools/test-artifact-verifiers.sh` drives the real rail against a stubbed
proofshot/agent-browser and a stubbed `lsof` that resolves the port to one PID
the case controls, so a kill is observable without touching whatever really
holds that port on the machine.

## Acceptance Criteria

- [x] A failed `start` with an active recording stops the stranded recording
      session and closes the stranded browser session.
- [x] A failed `start` leaves no `session-staging/` and no
      `proofshot.config.json` behind.
- [x] After a successful recovery, `start` is retried exactly once and reaches
      an active second recording.
- [x] A persistent start failure exits non-zero with the honest failed-repro
      message and no staging residue.
- [x] `stop` kills the dev server and reports it when the marker records
      `serverAlreadyRunning: false` with a port.
- [x] `stop` neither reports nor kills a dev server when the marker records
      `serverAlreadyRunning: true` — the developer's server survives.
- [x] Reintroducing port-only resolution fails the ownership control, so the
      control detects the corrected defect.
