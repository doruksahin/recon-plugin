---
id: ADR-01KZ0ZK4WYVWRY0WJM2CZ7ZS8C
status: accepted
date: 2026-08-02
---

# ADR-01KZ0ZK4WYVWRY0WJM2CZ7ZS8C Portable Multi-Harness Recon Plugin Architecture

## Context and Problem Statement

Recon is distributed as a Claude Code plugin whose eight skills, manifest,
tool calls, runtime paths, release process, and generated report behavior
assume Claude Code. Codex can consume the portable parts of `SKILL.md`, but it
requires its own plugin manifest and interface metadata. ChatGPT and hosted
runtimes introduce an additional boundary because they cannot execute local
commands or Claude-specific tools by convention.

Maintaining independent Claude and Codex copies would create behavioral drift
in a workflow whose value depends on deterministic state transitions and
evidence integrity. Treating copied Markdown as universal would also hide real
capability differences such as interactive questions, browser automation,
artifact delivery, and skill-to-skill invocation.

The project therefore needs one accountable source model that preserves the
Recon workflow while producing native artifacts for each supported harness.
The design must remain useful without requiring Microsoft APM, OpenPackage, or
another external package manager at runtime.

## Decision Drivers

- One canonical definition for the eight Recon workflows
- Native Claude Code and Codex packaging rather than directory-only copying
- Deterministic behavior for state, evidence, validation, and reports
- Explicit host capability boundaries instead of invented tool equivalence
- CI-detectable drift between source and generated artifacts
- No mandatory third-party package-manager or network dependency
- A path to hosted ChatGPT support without weakening local functionality

## Considered Options

### Option A: Preserve a Claude-only plugin

Keep the current source and installation workflow unchanged. This has the
lowest immediate cost, but excludes Codex and makes future portability more
expensive because Claude-specific assumptions continue to spread.

### Option B: Copy or symlink identical skills into every harness

Adopt Agent Skills as the common file format and install the same directories
into Claude and Codex locations. This solves discovery for portable prose but
does not solve native manifests, tool names, interactive behavior, report
delivery, path resolution, or hosted execution.

### Option C: Canonical portable core with generated native adapters

Keep one canonical set of workflows and deterministic scripts. Generate and
validate native Claude and Codex packaging plus small host adapters for
capabilities that differ. Put state mutation, evidence handling, and report
contracts behind a host-neutral `reconctl` CLI so skills describe policy while
code enforces invariants.

### Option D: Require a universal package manager

Adopt APM, OpenPackage, or a similar manager as the canonical project model.
This would add dependency resolution and distribution features, but it would
not translate host semantics and would make Recon development depend on a
young external ecosystem. A package manager can remain an optional delivery
wrapper after native artifacts exist.

## Decision Outcome

Choose **Option C: canonical portable core with generated native adapters**.

The repository will treat the portable Agent Skills content, shared contracts,
and deterministic scripts as source. A generator will emit native Claude Code
and Codex artifacts from explicit adapter configuration. Generated outputs will
be checked into version control so releases are inspectable and consumers do
not need the generator installed.

The first implementation will:

1. Add valid `name` and `description` frontmatter to every skill.
2. Replace hard-coded Claude storage paths with a documented, overrideable
   Recon home contract.
3. Introduce a host-neutral `reconctl` command for deterministic paths,
   capability inspection, validation, and artifact/state operations that can
   safely be extracted from prose.
4. Add a native `.codex-plugin/plugin.json` and Codex skill interface metadata
   while preserving the native Claude manifest.
5. Add generator/check commands and CI-facing validation that fail on drift.
6. Preserve host-specific behavior behind explicit capability adapters. When
   no equivalent exists, the skill must degrade transparently or stop with an
   actionable message.

### Consequences

- Claude and Codex remain first-class targets rather than pretending their
  complete tool surfaces are identical.
- Generated files must not be edited directly; changes originate in canonical
  sources or adapter configuration.
- Optional package managers may distribute the plugin, but none becomes a
  runtime dependency.
- ChatGPT support is limited to skills that can run in its available execution
  environment. Local browser control, local files, or authenticated services
  require a hosted MCP/app adapter and remain a separately testable target.
- This architectural expansion requires a minor version bump from `0.13.0` to
  `0.14.0`; incompatible state or contract changes would instead require a
  major bump.

### Verification

- Validate all skill frontmatter and bundled references.
- Validate both native plugin manifests.
- Run the generator in check mode and fail on drift.
- Run existing link and coherence checks.
- Smoke-test `reconctl` with isolated temporary state.
- Record any unimplemented host capability as an explicit limitation rather
  than silently substituting behavior.
