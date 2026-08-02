# tools/ — repo tooling

Editor-session tooling: nothing here ships inside the plugin or runs during a
recon pipeline run. Adding a file here without a role line below fails
`check-coherence.sh` (role coverage).

| File | Role |
| --- | --- |
| `check-links.sh` | Pre-commit pass 1 — existence: resolves `blob/master` self-links and backticked path references against the working tree, then lychee over real links. Docs must not outlive the files they name. |
| `check-coherence.sh` | Pre-commit agreement gate: version stamps, generated adapters, local host contract/no-command-leak test, registry mirrors, role coverage, and invariant citations. |
| `check-commit-msg.sh` | Commit-msg hook: enforces the Conventional Commits format. |
| `cz.sh` | Commitizen wrapper for composing conventional commits interactively. |
| `release.sh` | The release rail: bumps `recon/.claude-plugin/plugin.json`, generates the changelog, tags. The version bump lives here, never hand-edited. |
| `generate-adapters.py` | Generates the native Codex plugin manifest and each skill's `agents/openai.yaml` from the canonical Claude manifest + SKILL.md frontmatter; `--check` is the drift gate. |
| `test-host-contract.sh` | Isolated local Claude/Codex contract test: detection, invocation rendering, capability levels, preflight, provenance, canonical state actions, and workspace lint. |

Both check scripts run from `.githooks/pre-commit` (enable per clone:
`git config core.hooksPath .githooks`; bypass once with `--no-verify`).
