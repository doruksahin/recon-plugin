# tools/ — repo tooling

Editor-session tooling: nothing here ships inside the plugin or runs during a
recon pipeline run. Adding a file here without a role line below fails
`check-coherence.sh` (role coverage).

| File | Role |
| --- | --- |
| `check-links.sh` | Pre-commit pass 1 — existence: resolves `blob/master` self-links and backticked path references against the working tree, then lychee over real links. Docs must not outlive the files they name. |
| `check-coherence.sh` | Pre-commit pass 2 — agreement: version stamps (`coherence:version` markers vs `plugin.json`), registry tokens vs the three mirror docs, role coverage of directory CLAUDE.mds, invariant citations vs pipeline.md. Docs must not contradict the data they mirror. Ownership table: pipeline.md Change protocol item 8. |
| `check-commit-msg.sh` | Commit-msg hook: enforces the Conventional Commits format. |
| `cz.sh` | Commitizen wrapper for composing conventional commits interactively. |
| `release.sh` | The release rail: bumps `recon/.claude-plugin/plugin.json`, generates the changelog, tags. The version bump lives here, never hand-edited. |

Both check scripts run from `.githooks/pre-commit` (enable per clone:
`git config core.hooksPath .githooks`; bypass once with `--no-verify`).
