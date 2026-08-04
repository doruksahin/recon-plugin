# AGENTS.md

This repository ships the `recon` workflow to Claude Code and Codex from one
canonical skill source. Read `CLAUDE.md` completely before editing; despite its
historical name, it is the repository-wide editor contract. Also read the
nearest directory-level `CLAUDE.md` before changing files in `recon/skills/`,
`recon/scripts/`, `recon/docs/`, `tools/`, or `docs/`.

Read [`docs/agent-behavior/README.md`](docs/agent-behavior/README.md) before
proposing or changing Recon behavior. It is the binding operating mentality for
agent work in this repository: start from an observed task outcome, prefer
deterministic rails, separate claims from evidence, and do not call an idea an
improvement until a rerunnable demonstration proves it. Apply it without waiting
for the user to repeat these expectations. Follow its progressive-disclosure
router and load only the principle, playbook, or example relevant to the work.

The architectural decision is
`ADR-01KZ0ZK4WYVWRY0WJM2CZ7ZS8C` under `decree/adr/architecture/`.

Portable-source rules:

- `recon/skills/*/SKILL.md` and `recon/.claude-plugin/plugin.json` are source.
- `.agents/plugins/marketplace.json`, `recon/.codex-plugin/plugin.json`, and
  each `agents/openai.yaml` are generated.
- Run `python3 tools/generate-adapters.py` after source metadata changes.
- Run `python3 tools/generate-adapters.py --check`, then the link and coherence
  checks before handing off a change.
- Runtime workspace paths are resolved by `recon/scripts/reconctl.sh`; do not
  add new hard-coded host workspace paths.
- Host-specific interaction uses the capability contract in
  `recon/docs/hosts.md`. Never invent an equivalent tool silently.

Do not hand-edit version fields. Versioning and publishing remain governed by
the release rail described in `CLAUDE.md` and `recon/docs/pipeline.md`.
