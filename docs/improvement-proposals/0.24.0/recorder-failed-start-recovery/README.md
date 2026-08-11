# Recover a stranded recorder start

> Recover a stranded recorder session without killing a dev server the run does not own.

- **Status:** shipped (v0.21.0)
- **Priority:** P2
- **Theme:** evidence rail
- **Origin:** 2026-08-11, found while syncing the source checkout. The
  implementation already existed — authored directly inside the installed Claude
  marketplace mirror at `~/.claude/plugins/marketplaces/recon-plugin` (then
  v0.18.0), which the Change protocol forbids. That mirror could not
  fast-forward, so `activate-plugin.sh` had been reporting `SYNC FAILED` while
  still exiting 0, and the work sat unreleased across two releases.

## Problem

`proofshot start` has one failure mode that strands state: recording
initialization fails while an agent-browser session is already active. The
partial session outlives the failed `record-repro.sh start` and blocks the next
attempt, and any dev server the recorder launched keeps running past a stage
that must not leak side effects. Invariant 9 forbids falling back to unrecorded
browsing, so the operator is stuck until they clean up by hand.

The recovered implementation resolved the dev-server port by scraping
proofshot's stdout (`Dev server started on :PORT`) and killing whatever `lsof`
reported there. proofshot's prose cannot distinguish "this recording started the
server" from "one was already running", so on a developer who already had a dev
server on that port, recovery killed theirs.

## Before

```text
record-repro.sh ATT-1234 start
  → proofshot start fails: "Recording already active"
  → stranded agent-browser session stays open
  → recorder-started dev server stays up
  → operator cleans up by hand, or the next start fails the same way
```

## After

```text
record-repro.sh ATT-1234 start
  → proofshot start fails: "Recording already active"
  → RECOVERY: stopped stranded recording session proofshot-…
  → RECOVERY: closed stranded browser session proofshot-…
  → dev server stopped ONLY when .session.json says serverAlreadyRunning: false
  → RECOVERY: retrying the recording start once …
  → active recording, or an honest failed-repro finding with no staging residue
```

## Decision

`repro/session-staging/.session.json` is the single owner of dev-server
ownership, expressed once as `owned_server_port` + `stop_owned_server` and shared
by both the `stop` path and the recovery path. proofshot's log text is never an
ownership authority. A successful session close authorizes exactly one retry; a
second failure stays an honest failure.

Design and acceptance criteria:
`decree/spec/reliability/evidence/spec-01kzrnhbpkfj53fgte6w30k5tt-recorder-failed-start-recovery-with-marker-owned-server.md`

## Evidence

`tools/test-artifact-verifiers.sh` drives the real rail against a stubbed
recorder plus a stubbed `lsof` that resolves the port to one PID the case owns.
Two controls encode the corrected defect: the run's own server is stopped, and a
pre-existing server is neither reported nor killed. Reintroducing port-only
resolution fails the second control.
