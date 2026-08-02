---
date: '2026-08-02'
governs:
- recon/scripts/record-repro.sh
- recon/scripts/reconctl.sh
- recon/scripts/artifact-tools.py
- recon/scripts/verify-repro.sh
- recon/scripts/package-artifacts.sh
- recon/scripts/doctor.sh
- recon/skills/recon-repro/SKILL.md
- recon/docs/registry.yaml
- recon/docs/pipeline.md
- recon/docs/hosts.md
- recon/docs/workspace-index.md
- docs/flow.html
- tools/test-artifact-verifiers.sh
id: SPEC-01KZ1BD2V986MYTYD6PCB02BGX
references:
- ADR-01KZ0ZK4WYVWRY0WJM2CZ7ZS8C
- SPEC-01KZ14Q6A2WB6J6TTX3XWQC5QJ
status: implemented
---

# SPEC-01KZ1BD2V986MYTYD6PCB02BGX Recon 0.16.0 Recorded Repro Runtime

## Overview

Make a recorded browser session the single repro runtime. v0.15.0's verifier
(SPEC-01KZ14Q6A2WB6J6TTX3XWQC5QJ) proves a repro package is well-formed; it
cannot prove the steps happened, because the model performs actions and then
writes `repro.md` from recall. This SPEC routes every repro through the
proofshot CLI (pinned 1.6.0, driving the separate agent-browser CLI): the
session produces a timestamped action log, a video, and console/server logs
inside the workspace, `repro.md` steps are transcribed from that log, and the
verifier cross-checks prose against the mechanical record. There is no
unrecorded fallback path — a missing or mismatched recorder fails the new
`repro` preflight profile and yields an honest failed-repro finding.

Full design rationale and the vendored proofshot 1.6.0 contract:
[docs/plans/2026-08-02-proofshot-repro-runtime.md](../../../../docs/plans/2026-08-02-proofshot-repro-runtime.md).

## Technical Design

### Recorder rail

New rail *record-repro.sh* `<TICKET> start|exec|stop|status`. It pins the
working directory to `$RECON_ROOT/<TICKET>/repro/` and writes a
workspace-local `proofshot.config.json` (`output: ./session-staging`) so
`start`, `exec`, and `stop` always resolve the same session and any config
higher in the tree is shadowed. `exec` exits 2 when no active recording
exists, making proofshot's silent unlogged-exec mode unreachable. `stop`
relocates step-numbered screenshots (`<n>-<slug>.png`) into
`repro/exhibits/`, finalizes the session bundle at `repro/session/`
(`session-log.json`, `session.webm`, `metadata.json`, `console-output.log`,
`server.log` with `--run`, `SUMMARY.md`, `viewer.html`), and removes the
staging directory and config. `start` replaces a previously finalized
session (replacement semantics, like Jira attachments) and cleans staging on
failure so no transient file reaches a stage's lint step.

### Preflight

`reconctl.sh` gains a `repro` preflight profile: base checks plus `proofshot`
and `agent-browser` on PATH and an exact pinned proofshot version (default
1.6.0, `RECON_PROOFSHOT_VERSION` override). recon-repro starts with
`reconctl.sh start repro`; `doctor.sh` surfaces the recorder checks.

### Verifier cross-checks

`artifact-tools.py verify-repro` additionally requires, for
`reproduced: true`, the session bundle with a schema-exact log: a JSON array
of `{action, relativeTimeSec, timestamp}` entries with optional `element`
and no unknown keys (vendored-schema drift fails loudly), non-decreasing
`relativeTimeSec`, ISO timestamps inside the run window, every exhibit
matched by exactly one logged `screenshot <n>-<slug>.png` action, screenshot
actions ordered by step number, and a `session.webm` bearing the EBML magic
with non-trivial size. `reproduced: false` permits an absent session (the
app may never have booted); a present one is validated structurally. All
session files must be regular, non-symlinked, in-workspace, and
current-run-fresh, matching the existing exhibit rules.

### Delivery and registry

`package-artifacts.sh` gains a per-file size guard
(`RECON_BUNDLE_MAX_FILE_SIZE`, default 20 MB) that skips oversized files with
a printed `SKIPPED` line, so the video degrades the bundle rather than the
delivery. The registry gains `repro/session/*` (token `session/`), mirrored
in pipeline.md's registry table, `workspace-index.md`, and `docs/flow.html`.
pipeline.md invariant 9 states the recording mechanism (no renumbering);
hosts.md replaces the host-browser repro row with the recorder contract.

## Testing Strategy

Extend `tools/test-artifact-verifiers.sh` with isolated session fixtures: a
valid recorded success; success without a session; an exhibit with no
matching screenshot action; screenshot actions out of step order; a
malformed or unknown-key log entry; a log timestamp outside the run window;
a corrupt `session.webm`; failed repros with and without a session bundle.
Each failing case asserts its intended diagnostic. *record-repro.sh* guard
behavior (exec without an active recording exits 2; stop finalizes and
cleans staging) is covered with a stubbed `proofshot` on PATH — no real
browser, network, or Jira access in any fixture. The full local chain
(`check-links.sh`, `check-coherence.sh` including the verifier fixtures,
`generate-adapters.py --check`) passes before release; agent-browser driving
quality is validated on 2–3 real tickets before `recon-publish` cuts the
release.

## Acceptance Criteria

- [x] *record-repro.sh* brackets every repro: guarded exec, staging shadowed and cleaned, finalized bundle at `repro/session/`, step screenshots relocated to `repro/exhibits/`.
- [x] `reconctl.sh start repro` fails closed on a missing or version-mismatched proofshot/agent-browser install.
- [x] `verify-repro.sh` rejects a `reproduced: true` package without a session bundle, an exhibit not produced by a logged screenshot action, out-of-order screenshot actions, schema drift in the log, stale timestamps, and a corrupt video.
- [x] Honest failed repros pass with or without a session bundle.
- [x] Oversized session files are skipped from the delivery bundle with a visible `SKIPPED` line.
- [x] Registry, pipeline.md, workspace-index.md, and flow.html mirror the `session/` artifact; all coherence and link checks pass.
