# tools/ — repo tooling

Editor-session tooling: nothing here ships inside the plugin or runs during a
recon pipeline run. Adding a file here without a role line below fails
`check-coherence.sh` (role coverage).

| File | Role |
| --- | --- |
| `check-links.sh` | Pre-commit pass 1 — existence: resolves `blob/master` self-links and backticked path references against the working tree, then lychee over real links. Docs must not outlive the files they name. |
| `check-coherence.sh` | Pre-commit agreement gate: version stamps, generated adapters + replay-lab report, host/runtime + artifact-verifier + real-ticket-replay + Codex-activation contracts, no-command-leak test, registry mirrors, role coverage, and invariant citations. |
| `check-commit-msg.sh` | Commit-msg hook: enforces the Conventional Commits format. |
| `cz.sh` | Commitizen wrapper for composing conventional commits interactively. |
| `release.sh` | The release rail: bumps `recon/.claude-plugin/plugin.json`, generates the changelog, tags. The version bump lives here, never hand-edited. |
| `generate-adapters.py` | Validates each skill's unique, trigger-bearing ≤200-character description, then generates the native Codex plugin manifest and each skill's `agents/openai.yaml` from the canonical Claude manifest + SKILL.md frontmatter; `--check` is the drift gate. |
| `render-decree-reports.py` | Executable complete generated-view owner for tracked Decree completion reports: regenerates through Decree in an exception-cleaned temporary project, canonicalizes generated portable identities, validates tracked Document and source-derived transition identities without rewriting them, and fails `--check` on report-set or whole-body drift after ignoring only the Generated timestamp. |
| `test-decree-reports.sh` | Executable isolated complete-report controls proving transition, body, and Document mutations fail, timestamp-only variation passes, exceptional regeneration leaves no owned temporary project, and clean regeneration is byte-equivalent modulo that timestamp. |
| `test-host-contract.sh` | Isolated local Claude/Codex contract test: detection, invocation rendering, atomic startup, capability levels, preflight, changing-host provenance, canonical state actions, and workspace lint. |
| `test-artifact-verifiers.sh` | Isolated clean/failing fixtures for repro and Discovery package verifiers, including PNG corruption/order, symlink escapes, route-envelope omissions/malformed/duplicate fields, comment/code shadow evidence, scenario/brief/gate/outcome drift, honest failures, both brief shapes, no-brief routing, and the railed gates: deterministic question rendering plus verbatim exchange/coverage/resolution parity at the approval gate, comment-byte parity, exchange ordering, outcome/disk agreement, and the declined-delivery derived state at the posting gate, question determinism plus config-and-exchange-or-neither persistence at the governance question, and rail-owned question, append-only record, and rejected-answer-writes-nothing at the canvas publish gate. |
| `test-comment-rendering.sh` | Isolated rendered-comment fixtures for BLOCKED progressive-disclosure and approved READY delivery shapes. |
| `test-dossier-store.sh` | Hermetic current-workspace storage-adapter controls: exact task-packet-store pin, package-owned store metadata and doctor failure, support-file inclusion, checked traversal with archive pruning, filesystem overlap rejection including symlink aliases, v1 preservation on repeat, success-receipt locations, and empty-stdout failures at validation, checkpoint, and locate boundaries. |
| `test-triage-verifier.sh` | Isolated generic normative-requirement closure controls for `triage-tools.py`: complete normative/context coverage attestations, descriptor-bound repository evidence under deterministic pathname replacement, symlink/type/UTF-8 rejection, closure surfaces, classifications, atomic joins, check/disposition consistency, generic READY, and case-vocabulary leakage. |
| `test-codex-activation.sh` | Fake-Codex, two-clone activation contract: proves released-commit/materialized-tree plus installed version/path attestation, and rejects stale or dirty installs, same-version different-content branches, ignored rogue skills, sparse/assume-unchanged entries, post-add mutation, and list-time ignored mutation. |
| `replay-ticket.py` | Repository-only real-ticket evaluation rail: strict case validation, oracle-free atomic preparation from an immutable target commit, production-verifier-first scoring, one-to-one decision/blocker matching, receipt-derived run state, and no-overwrite retained evaluation. |
| `render-replay-lab-report.py` | Generated-view owner for `docs/replay-lab-report.html`: executes live replay controls, resolves source line references and hashes, renders the self-contained operator report, and fails `--check` on byte drift. |
| `test-replay-lab.sh` | Isolated ATT-4845 scoring controls plus input-drift, oracle-isolation, exact-commit export, persisted state/evaluation, inconsistent-run, symlink, candidate-drift, and no-overwrite controls. |
| `test-replay-lab-report.sh` | Structural report gate: generated-byte parity, section and navigation targets, in-repository references, copy targets, seven decision cards, required control diagnostics, no remote assets, and desktop/narrow/print responsive contracts. |
| `improvement-cycle.py` | Repository-only improvement rail: validated fixed experiment contracts, comparable immutable attempt captures, retained comparison/review decisions, retry state, fail-closed acceptance, and generic deterministic proposal HTML rendering/checking. |
| `test-improvement-cycle.sh` | Isolated controls for experiment identity enforcement, result consistency, symlink/overwrite/tamper rejection, retained compare/review lifecycle, retry attempts, generic rendering, state-first routing, and frozen baseline invariance. |
| `version-review.py` | Repository-only external-root team-review rail: requires and pins a distinct private GitHub repository, rechecks live privacy before writes, retains offline state derivation, captures immutable minimal dossier evidence, validates report-bound reviews/consensus/cross-ticket synthesis, and closes with proposal links without Jira mutation. |
| `test-version-review.sh` | Isolated complete-lifecycle and negative controls for private-GitHub storage, inherited Git-hook environment isolation, identity/visibility drift, privacy allowlisting, hashes, joins, symlink/overlap rejection, no-overwrite, offline derived state, and exception cleanup. |
| `render-system-map.py` | Generated-view owner for `docs/system-map.html`: resolves source references and hashes, derives current improvement state, and fails `--check` on any byte drift. |
| `test-system-map.sh` | Structural and drift controls for the system map: required four-flow explanation, public examples, version-review references, oracle non-leakage, and generated-byte parity. |
| `pre-commit-check.sh` | Single fail-closed local commit gate: staged-diff integrity, local links, coherence plus every universal control, and Decree lint. Invoked only by `.githooks/pre-commit`. |
| `test-pre-commit-check.sh` | Isolated temporary-index control that proves the commit gate rejects staged whitespace without touching the caller's worktree or index. |

The versioned pre-commit hook delegates only to `pre-commit-check.sh` (enable
per clone: `git config core.hooksPath .githooks`). Read `.githooks/AGENTS.md`
before changing hook behavior. Normal commits must not use `--no-verify`.
