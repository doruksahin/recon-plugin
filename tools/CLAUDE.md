# tools/ — repo tooling

Editor-session tooling: nothing here ships inside the plugin or runs during a
recon pipeline run. Adding a file here without a role line below fails
`check-coherence.sh` (role coverage).

| File | Role |
| --- | --- |
| `check-links.sh` | Pre-commit pass 1 — existence: resolves `blob/master` self-links and backticked path references against the working tree, then lychee over real links. Docs must not outlive the files they name. |
| `check-coherence.sh` | Pre-commit agreement gate: version stamps, generated adapters, host/runtime + artifact-verifier + Codex-activation contracts, no-command-leak test, registry mirrors, role coverage, and invariant citations. |
| `check-commit-msg.sh` | Commit-msg hook: enforces the Conventional Commits format. |
| `cz.sh` | Commitizen wrapper for composing conventional commits interactively. |
| `release.sh` | The release rail: bumps `recon/.claude-plugin/plugin.json`, generates the changelog, tags. The version bump lives here, never hand-edited. |
| `generate-adapters.py` | Validates each skill's unique, trigger-bearing ≤200-character description, then generates the native Codex plugin manifest and each skill's `agents/openai.yaml` from the canonical Claude manifest + SKILL.md frontmatter; `--check` is the drift gate. |
| `render-decree-reports.py` | Generated-view owner for Decree completion reports: regenerates tracked snapshots through Decree, canonicalizes each document identity to its stable repository-relative source, and fails `--check` on absolute or mismatched identities. |
| `test-decree-reports.sh` | Isolated generated-report portability controls proving that absolute host identities fail and repository-relative identities pass. |
| `test-host-contract.sh` | Isolated local Claude/Codex contract test: detection, invocation rendering, atomic startup, capability levels, preflight, changing-host provenance, canonical state actions, and workspace lint. |
| `test-artifact-verifiers.sh` | Isolated clean/failing fixtures for repro and Discovery package verifiers, including PNG corruption/order, symlink escapes, route-envelope omissions/malformed/duplicate fields, comment/code shadow evidence, scenario/brief/gate/outcome drift, honest failures, both brief shapes, no-brief routing, and the railed gates: deterministic question rendering plus verbatim exchange/coverage/resolution parity at the approval gate, comment-byte parity, exchange ordering, outcome/disk agreement, and the declined-delivery derived state at the posting gate, question determinism plus config-and-exchange-or-neither persistence at the governance question, and rail-owned question, append-only record, and rejected-answer-writes-nothing at the canvas publish gate. |
| `test-comment-rendering.sh` | Isolated rendered-comment fixtures for BLOCKED progressive-disclosure and approved READY delivery shapes. |
| `test-codex-activation.sh` | Fake-Codex, two-clone activation contract: proves released-commit/materialized-tree plus installed version/path attestation, and rejects stale or dirty installs, same-version different-content branches, ignored rogue skills, sparse/assume-unchanged entries, post-add mutation, and list-time ignored mutation. |

Both check scripts run from `.githooks/pre-commit` (enable per clone:
`git config core.hooksPath .githooks`; bypass once with `--no-verify`).
