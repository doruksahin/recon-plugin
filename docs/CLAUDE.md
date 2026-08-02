# docs/ — repo-level docs (not shipped in the plugin)

Nothing here is read at pipeline runtime — runtime-visible docs live in
`recon/docs/`. Adding a file or directory here without a role line below
fails `tools/check-coherence.sh` (role coverage).

| Entry | Role |
| --- | --- |
| `flow.html` | Source of the published "Recon Pipeline — Flow" artifact (URL in the file's header comment). A registry + version MIRROR: the workspace table is checked token-by-token against `recon/docs/registry.yaml`, and the `coherence:version` markers pin its version stamps to `plugin.json`. After editing, republish the artifact — the one mirror the pre-commit hook cannot reach. |
| `plans/` | Dated design docs, implementation plans, and spike notes for shipped work — the long-form record behind CHANGELOG entries. |
| `improvement-proposals/` | Versioned improvement-proposal ledger: every record lives at `<target-version>/<slug>/README.md`, with concrete before/after and a cohort index. New proposals must reserve a future version directory; accepted ideas graduate to `plans/`. |
