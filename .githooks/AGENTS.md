# Commit guardrails

This directory contains the versioned local Git hook entry points. Read this
file only when changing a hook or commit-validation behavior.

## Operating rule

Normal commits must run `.githooks/pre-commit`, which delegates to the single
owner `tools/pre-commit-check.sh`. The hook contains no policy and no duplicate
checks; the rail owns command order, diagnostics, and exit behavior.
`commit-msg` remains a separate thin hook because Git provides the final
message only after pre-commit. It validates Conventional Commit syntax; it is
not a repository-drift or runtime-control check.

The rail fails closed for staged whitespace errors, unresolved index conflicts,
missing required local tools, local reference drift, generated-view drift,
universal control failures, and invalid Decree records. It is intentionally
network-independent: `check-links.sh` still reports external-link reachability
as best effort, while all local deterministic checks remain mandatory.

## Progressive disclosure

1. Read this file to understand hook ownership and failure boundaries.
2. Read `tools/pre-commit-check.sh` for check order and diagnostics.
3. Read `tools/check-coherence.sh` only when adding or changing a universal
   drift/control suite.
4. Read `tools/CLAUDE.md` for each tool's role.

## Extension rule

Any new universal deterministic check belongs in `tools/check-coherence.sh`,
with a focused failing control. Do not append it directly to the Git hook.
Update `tools/CLAUDE.md` in the same change.

## Boundary

Enable the versioned hooks explicitly once per clone:

```bash
git config core.hooksPath .githooks
```

`git commit --no-verify` can intentionally bypass all local hooks. Do not use
it for normal work. Remote branch protection and CI are required to prevent an
intentional bypass; this repository-local hook cannot do that by itself.
