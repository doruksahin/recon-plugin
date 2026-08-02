# Proofshot as the single repro runtime — implementation plan

Implements [docs/improvements/proofshot-repro-runtime/README.md](../improvements/proofshot-repro-runtime/README.md).
Ships as one `feat(repro)!` commit (new required runtime dependency, stage-semantics
change). Target: the release after v0.15.0.

## Vendored proofshot 1.6.0 contract (verified from the published npm package)

Facts below were read from `proofshot@1.6.0` `dist/` sources on 2 Aug 2026. The
verifier and rail depend on them; a version bump re-verifies each line.

- Binary `proofshot` (Node ≥ 18). Drives the separate `agent-browser` CLI
  (`agent-browser [--session <name>] <cmd>`) — BOTH binaries must exist.
- Config: `proofshot.config.json`, found by walking **up** from `cwd`.
  `output` defaults to `./proofshot-artifacts`, resolved against **cwd**, not
  the config's directory.
- `proofshot start [--run <cmd>] [--port N] [--description <text>] [--force]`
  creates `<output>/<ISO-ts>_<desc-slug>/` containing `session.webm` (recording),
  `metadata.json` (`branch`, `commitSha`, `startedAt`, `description`), and
  `server.log` (only with `--run`), plus the active-session marker
  `<output>/.session.json`. `--run` spawns via `$SHELL`, so
  `cd <repo> && <dev cmd>` keeps the dev server in the target repo.
- `proofshot exec <agent-browser args>` resolves the session from config+cwd
  (no `--output` flag). **If it finds no active session it still executes but
  logs nothing** — the rail must guard this, or provenance is silently lost.
  With a session it appends to `session-log.json`: a JSON array of
  `{action, relativeTimeSec, timestamp, element?}` where `action` is the
  original arg string (relative screenshot names, pre-resolution) and relative
  screenshot paths are materialized inside the session dir.
- `proofshot stop` finalizes: writes `console-output.log`, `SUMMARY.md`,
  `viewer.html`, clears `.session.json`.

## Design decisions

1. **One path, no fallback.** `reconctl.sh` gains a `repro` preflight profile:
   base checks + `proofshot` + `agent-browser` on PATH + pinned version
   (`1.6.0`, override `RECON_PROOFSHOT_VERSION`). Absent/mismatched fails
   preflight; a failed preflight is an honest failed-repro finding (hosts.md
   rule 5), never a fallback to unrecorded browsing.
2. **New rail *record-repro.sh*** `<TICKET> start|exec|stop|status` pins
   `cwd` to `$RECON_ROOT/<TICKET>/repro/` and writes a workspace-local
   `proofshot.config.json` (`output: ./session-staging`) so `start`/`exec`/
   `stop` always resolve the same session and any parent config is shadowed.
   `exec` refuses (exit 2) when no active recording exists — the silent
   no-logging mode is unreachable. `stop` moves step-numbered PNGs
   (`<n>-<slug>.png`) into `repro/exhibits/`, moves the session dir to
   `repro/session/`, and removes the staging dir + config. `start` replaces a
   finalized `repro/session/` (replacement semantics, like attachments) and
   cleans up staging on failure, so no transient file survives to fail lint.
3. **Steps are transcribed, not recalled.** The skill writes `repro.md` from
   `repro/session/session-log.json`. `verify-repro.sh` cross-checks: for
   `reproduced: true` the session bundle is REQUIRED; every exhibit must match
   one logged `screenshot <n>-<slug>.png` action; screenshot actions must be
   ordered by step number; log entries must be schema-exact
   (`action`/`relativeTimeSec`/`timestamp`, optional `element`; unknown keys
   fail = vendored-schema drift detection) with non-decreasing
   `relativeTimeSec` and timestamps inside the run window; `session.webm`
   must carry the EBML magic and a non-trivial size. `reproduced: false`
   allows an absent session (the app may never have booted); a present one is
   validated structurally.
4. **Delivery.** `package-artifacts.sh` gains a per-file size guard
   (`RECON_BUNDLE_MAX_FILE_SIZE`, default 20 MB): oversized files are skipped
   with a printed `SKIPPED` line so a long video degrades the bundle, never
   the delivery.
5. **Registry.** New pattern `repro/session/*` (token `session/`), mirrored in
   pipeline.md's registry table, `workspace-index.md`, and `docs/flow.html`.
   Staging (`repro/session-staging/`, `repro/proofshot.config.json`) is
   transient by rail contract and never survives a stage Report step, so it is
   deliberately NOT registered.
6. **Invariant 9 extended** (no renumbering): recording is the mechanism that
   makes "never fabricate" mechanical.

## File-level checklist

- [x] *recon/scripts/record-repro.sh* — new rail (above)
- [x] `recon/scripts/reconctl.sh` — `repro` preflight profile + pinned-version check
- [x] `recon/scripts/artifact-tools.py` — session bundle + log cross-checks in `verify_repro`
- [x] `recon/scripts/package-artifacts.sh` — size guard
- [x] `recon/scripts/doctor.sh` — repro-recorder check lines (derived from `preflight repro`)
- [x] `recon/skills/recon-repro/SKILL.md` — record→drive→stop→transcribe workflow
- [x] `recon/docs/registry.yaml` + pipeline.md registry table + `recon/docs/workspace-index.md` + `docs/flow.html` — `session/` artifact
- [x] `recon/docs/pipeline.md` — invariant 9, stage R row, trigger rows, rails table
- [x] `recon/docs/hosts.md` — repro row + rule 5 + profile list
- [x] `recon/scripts/CLAUDE.md` + `recon/skills/CLAUDE.md` — role lines
- [x] `tools/test-artifact-verifiers.sh` — session fixtures (valid, missing-session,
      unmatched exhibit, out-of-order screenshots, malformed log, stale timestamp,
      bad webm, failed-with/without-session)

## Validation before release

Run the full local chain (`check-links`, `check-coherence` incl. artifact
verifiers, `generate-adapters --check`). Before `recon-publish` cuts the
release: drive 2–3 real tickets side-by-side to validate agent-browser driving
quality — the go/no-go from the proposal.
