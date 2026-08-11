# recon/docs/ — the specs that ship with the plugin

These files ride inside the plugin install, so scripts and skills may read
them at runtime (unlike the repo-level `docs/`). Adding a file here without a
role line below fails `tools/check-coherence.sh` (role coverage).

| File | Role |
| --- | --- |
| `pipeline.md` | The machine spec: state machine, numbered invariants (cited repo-wide — renumbering breaks citations, the coherence check catches it), trigger table, rails-vs-judgment split, the artifact-registry MIRROR table, and the binding Change protocol with the fact-ownership table. On conflict with a SKILL.md, the SKILL.md wins. |
| `registry.yaml` | THE artifact registry — single source of truth for what a run may write into `$RECON_ROOT/<TICKET>/`. `lint-workspace.sh` executes its `pattern` globs; `check-coherence.sh` asserts every `token` appears in the three mirror docs. Author artifacts HERE first. |
| `workspace-index.md` | Per-file documentation of a recon workspace; `fresh-workspace.sh` copies it into every workspace as `index.md`. A registry mirror — checked token-by-token. |
| `hosts.md` | Executable local-host contract for Claude Code and Codex: one atomic startup snapshot, later provenance re-detection, canonical actions, invocation rendering, capability levels, host-package parity with its intentional differences, source-to-install anti-drift ownership, and explicit hosted-runtime exclusion. |
| `decisions/` | ADRs. `0001-jira-rest-api-over-mcp.md` records why the pipeline talks to Jira via curl + REST instead of MCP tools. `0002-verbatim-gate-exchanges.md` records the decision to rail the discovery gate's presentation and store the exchange verbatim. `0003-remaining-gate-exchanges.md` extends that pattern to the triage posting gate, the governance question, and the state-canvas publish gate, and fixes the rule for how much presentation machinery a gate needs. |

Do not restate registry facts in prose here or elsewhere — link to
`registry.yaml` or rely on the mirrors the coherence check already validates.
