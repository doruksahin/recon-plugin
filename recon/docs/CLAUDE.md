# recon/docs/ — the specs that ship with the plugin

These files ride inside the plugin install, so scripts and skills may read
them at runtime (unlike the repo-level `docs/`). Adding a file here without a
role line below fails `tools/check-coherence.sh` (role coverage).

| File | Role |
| --- | --- |
| `pipeline.md` | The machine spec: state machine, numbered invariants (cited repo-wide — renumbering breaks citations, the coherence check catches it), trigger table, rails-vs-judgment split, the artifact-registry MIRROR table, and the binding Change protocol with the fact-ownership table. On conflict with a SKILL.md, the SKILL.md wins. |
| `registry.yaml` | THE artifact registry — single source of truth for what a run may write into `~/.claude/recon/<TICKET>/`. `lint-workspace.sh` executes its `pattern` globs; `check-coherence.sh` asserts every `token` appears in the three mirror docs. Author artifacts HERE first. |
| `workspace-index.md` | Per-file documentation of a recon workspace; `fresh-workspace.sh` copies it into every workspace as `index.md`. A registry mirror — checked token-by-token. |
| `decisions/` | ADRs. `0001-jira-rest-api-over-mcp.md` records why the pipeline talks to Jira via curl + REST instead of MCP tools. |

Do not restate registry facts in prose here or elsewhere — link to
`registry.yaml` or rely on the mirrors the coherence check already validates.
