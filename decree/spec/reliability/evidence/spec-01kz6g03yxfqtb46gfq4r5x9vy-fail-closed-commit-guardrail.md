---
date: '2026-08-04'
governs:
- AGENTS.md
- CLAUDE.md
- CONTRIBUTING.md
- README.md
- .githooks/AGENTS.md
- .githooks/pre-commit
- tools/CLAUDE.md
- tools/check-coherence.sh
- tools/check-commit-msg.sh
- tools/check-links.sh
- tools/pre-commit-check.sh
- tools/render-decree-reports.py
- tools/test-decree-reports.sh
- tools/test-pre-commit-check.sh
id: SPEC-01KZ6G03YXFQTB46GFQ4R5X9VY
references:
- ADR-01KZ0ZK4WYVWRY0WJM2CZ7ZS8C
- SPEC-01KZ6FJX3SGZVDAWA2M64H1E94
status: implemented
---

# SPEC-01KZ6G03YXFQTB46GFQ4R5X9VY Fail-Closed Commit Guardrail

## Overview

The repository contains deterministic drift checks and isolated controls, but
the committed hook ran only links and coherence, omitted the improvement-loop
and comment-rendering controls, and was not enabled in this checkout. A
maintainer could therefore create a commit without the full available local
evidence gate.

**Falsifiable claim:** once `core.hooksPath` explicitly points to the
versioned hook directory, every normal commit invokes one fail-closed command
that rejects staged whitespace errors, broken local references, generated-view
or adapter drift, all isolated universal controls, and invalid Decree records.

**Non-claims:** local Git hooks cannot prevent an intentional
`git commit --no-verify`, nor can they guarantee remote external-link
availability. Remote branch protection/CI remains the enforcement boundary for
intentional bypasses and network-only checks.

## Technical Design

`.githooks/pre-commit` is deliberately thin and delegates to the versioned
`tools/pre-commit-check.sh` rail. The rail checks the staged diff for whitespace
errors and unresolved index conflicts, requires `python3` and `uv`, then runs
`check-links.sh`, `check-coherence.sh`, and `uv run decree lint` in that order.

Staged-diff failures are normalized to exit 1 so a rejected commit is
distinguished from missing local prerequisites (exit 2).

`check-coherence.sh` remains the owner of universal generated-view and control
coverage. It runs adapter and report drift checks plus every isolated
repository-wide contract suite, including comment rendering and the persistent
improvement loop. The pre-commit rail does not duplicate those commands.

The Decree completion-report owner invokes the Decree regeneration rail for
the exact tracked report set. Check mode copies source documents into an
isolated temporary project, regenerates the same report IDs without touching
tracked files, canonicalizes repository-relative Document identities and
source-date transition identities exactly as write mode does, then compares
the complete content while ignoring only the explicitly volatile Generated
timestamp. Missing, extra, malformed, host-bound, or body-drifted reports fail.

The root `AGENTS.md` contains only the entry rule and one command. The detailed
failure, ownership, and extension policy lives in `.githooks/AGENTS.md` and is
loaded only when changing commit guardrails. A new universal deterministic
check must join `check-coherence.sh` and be documented in `tools/CLAUDE.md`.

## Testing Strategy

Prove the rail succeeds against the current tree, fails on an intentionally
introduced staged whitespace error in an isolated temporary index/worktree,
and invokes every required child command. Validate the hook is locally enabled
only through the explicit `git config core.hooksPath .githooks` command after
the repository checks are clean.

Generated-report controls mutate only the acceptance body, only the Document
identity, and only the Generated timestamp. Body and identity mutations must
fail; timestamp-only variation must pass; clean regeneration must remain
byte-equivalent modulo that one declared volatile field.

## Acceptance Criteria

- [x] The versioned pre-commit hook delegates to one fail-closed guardrail rail.
- [x] An isolated Git-index control proves that staged whitespace is rejected
      without modifying the caller's index or worktree.
- [x] The rail checks staged diff integrity, local links, coherence, every
  universal isolated control, and Decree lint.
- [x] Comment-rendering and improvement-loop controls are included in
  coherence, with no duplicated drift commands.
- [x] Root and hook-local AGENTS documents provide progressive disclosure and
  forbid normal bypasses while naming the CI/remote boundary.
- [x] The configured local hook path and full gate are demonstrated clean.
- [x] Decree report checks regenerate the exact tracked set in isolation and reject complete-content, set, status, acceptance-body, and portable-identity drift while ignoring only the Generated timestamp.
