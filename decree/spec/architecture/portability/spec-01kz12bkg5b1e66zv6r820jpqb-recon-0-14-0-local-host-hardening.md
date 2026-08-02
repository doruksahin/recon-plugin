---
date: '2026-08-02'
governs:
- recon/scripts/
- recon/skills/
- recon/docs/hosts.md
- recon/docs/pipeline.md
- README.md
- tools/
id: SPEC-01KZ12BKG5B1E66ZV6R820JPQB
references:
- ADR-01KZ0ZK4WYVWRY0WJM2CZ7ZS8C
status: implemented
---

# SPEC-01KZ12BKG5B1E66ZV6R820JPQB Recon 0.14.0 Local Host Hardening

## Overview

Harden the unreleased `0.14.0` portability work for two executable targets:
Claude Code and local Codex (app or CLI). Replace model-inferred host behavior
with deterministic local rails while retaining the existing shell runtime,
workspace schemas, approval gates, and native plugin packages.

Hosted ChatGPT, Codex Cloud, MCP, centralized Jira authentication, shared
remote state, and a cross-host publishing service are explicitly out of scope.
Unsupported publishing degrades to a local rendered file and is recorded as
such; it is not represented as a partially implemented remote capability.

## Technical Design

### Runtime identity

Extend `reconctl.sh` with normalized host and surface detection. Resolution
uses this precedence: explicit `RECON_HOST` / `RECON_SURFACE` overrides,
recognized Claude or Codex environment signals, then `unknown`. Detection is
read-only and available as both scalar commands and capability output.

`fresh-workspace.sh` stamps `started_host` and `started_surface` into
`meta.yaml`. `log-event.sh` records the current detected host and surface on
every event, preserving provenance when a run continues in another local
harness.

### Canonical actions and invocation rendering

Durable state stores canonical action IDs such as `recon.triage` and
`recon.discovery`; it never stores Claude slash commands or Codex skill
mentions. `reconctl.sh invocation <action> [ticket]` is the single renderer for
human-facing invocation syntax:

- Claude Code: `/recon:recon-triage ATT-1234`
- Codex: `$recon:recon-triage ATT-1234`
- unknown host: a neutral `Run Recon Triage for ATT-1234` label

Skills call the renderer before reporting a next action. Mechanical state
derivation writes `next_action` plus neutral `next` prose so saved artifacts
remain valid when viewed from another host.

### Preflight

Add `reconctl.sh preflight <base|triage>`:

- `base` verifies the workspace root is absolute and writable (or has a
  writable existing parent), and requires `bash`, `python3`, and `git`.
- `triage` additionally requires `curl`, `gh`, a readable Jira environment
  file with all required variables, and a successful authenticated Jira
  `/myself` request.

The command prints stable `check.<name>: PASS|FAIL|SKIP` records and exits
nonzero when a required check fails. Recon Triage runs the triage profile
before creating or archiving a workspace; other filesystem stages run the base
profile before mutation. Doctor reuses the same rail instead of implementing a
second Jira probe.

### Capability levels

Replace ambiguous publishing prose with four independent capabilities:
`render_local`, `display_file`, `publish_once`, and `publish_stable_url`.
Claude Code declares its native artifact publisher; local Codex declares local
render/display and treats publishing as unavailable unless an explicit future
adapter is configured. Only `publish_stable_url` may create or reuse
`state/artifact-url`.

### Compatibility and distribution

Keep `RECON_ROOT` defaulting to `~/.claude/recon` for compatibility. Do not add
runtime libraries, MCP configuration, remote services, or new credential
stores. Preserve native Claude and Codex manifests and generated Codex skill
metadata. The release remains `0.14.0` because it has not been committed,
tagged, or published.

## Testing Strategy

Add `tools/test-host-contract.sh` as an isolated shell contract test. It covers
explicit overrides, Claude/Codex/unknown detection, invocation rendering,
capability levels, base preflight pass/fail behavior, provenance stamps, event
provenance, and the absence of Claude slash commands from shared state output.

Run the existing adapter drift, eight skill validators, Codex plugin validator,
shell syntax, link, coherence, workspace smoke, and Decree validation suites.
Use a fresh local Codex plugin reinstall only after repository validation
passes. Do not commit, tag, push, publish, or post to Jira as part of this SPEC.

## Acceptance Criteria

- [x] `reconctl.sh` deterministically detects and normalizes Claude Code, Codex, explicit overrides, and unknown hosts/surfaces.
- [x] `reconctl.sh invocation` is the only executable-host command renderer used by shared skills and scripts.
- [x] Durable state contains canonical `next_action` values and no `/recon:` command strings.
- [x] `reconctl.sh preflight base|triage` emits stable check records and fails closed before workspace mutation.
- [x] Capability output distinguishes local rendering, file display, one-time publishing, and stable-URL publishing.
- [x] New workspaces record starting host/surface and every ledger event records its current host/surface.
- [x] All eight skills use the shared setup/preflight/invocation contract without hard-coded Claude commands.
- [x] README and pipeline/host documentation define local Claude/Codex support and explicitly exclude hosted runtimes from `0.14.0`.
- [x] `tools/test-host-contract.sh` passes in an isolated temporary workspace.
- [x] Adapter drift, skill validation, plugin validation, shell syntax, links, coherence, workspace smoke, and Decree lint all pass.
- [x] The locally installed Codex plugin is refreshed from the validated working tree and reports version `0.14.0`.

## Completed Outcome

The local runtime contract now has one mechanical owner, `reconctl.sh`, for
host/surface identity, capabilities, preflight, and invocation rendering.
Workspace metadata and ledger events retain host provenance; derived state
stores canonical action IDs; all eight skills consume the same setup contract.

Validation completed on 2026-08-02: the isolated host contract, shell syntax,
all eight skill validators, Codex plugin validator, generated-adapter drift,
link check, six-pass coherence suite, authenticated doctor/preflight, workspace
smoke, Decree lint, and `git diff --check` passed. The local Codex marketplace
was reactivated and reports `recon@recon-plugin` version `0.14.0` from the
validated working tree. No commit, tag, push, GitHub release, Jira mutation, or
hosted/MCP runtime was created.

### Deferred

- [ ] Hosted ChatGPT or Codex Cloud execution through MCP or another remote runtime.
- [ ] Centralized Jira OAuth, shared remote Recon state, or a stable cross-host artifact service.
