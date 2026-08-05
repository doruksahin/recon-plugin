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

For repository replay-laboratory work—starting, resuming, checking, evaluating,
comparing, or explaining a frozen ticket run—read
[`evals/skills/recon-replay-lab/SKILL.md`](evals/skills/recon-replay-lab/SKILL.md)
and follow its fresh-context handoff boundary. This skill is repository-local
evaluation guidance; it is intentionally not part of the shipped plugin.

For a plugin-improvement or improvement-resume request, start with
[`evals/skills/recon-improvement-loop/SKILL.md`](evals/skills/recon-improvement-loop/SKILL.md).
It derives the durable improvement state from retained evidence before any
interpretation; it is repository-local and never ships in the Recon plugin.

For collecting or reviewing teammate feedback across tickets produced by one
published plugin version, start with
[`evals/skills/recon-version-review/SKILL.md`](evals/skills/recon-version-review/SKILL.md).
The live review tree is private and external; its checked-in
[`schema`](evals/version-reviews/schema.yaml),
[`structure guide`](evals/version-reviews/README.md), and
[`rail`](tools/version-review.py) are the non-drifting owners. Do not group the
evidence by sprint or commit live ticket/report material under `evals/`. A live
root must be the top level of a distinct private GitHub repository outside this
source tree. Let the rail verify and pin that identity; never bypass its live
privacy check or hand-edit its storage receipt.

The architectural decision is
`ADR-01KZ0ZK4WYVWRY0WJM2CZ7ZS8C` under `decree/adr/architecture/`.

## Commit guardrails

Before committing, run the one owner command:

```bash
bash tools/pre-commit-check.sh
```

Enable the committed hooks once per clone with
`git config core.hooksPath .githooks`. The rail fails closed on staged-diff,
reference, generated-view, universal-control, and Decree drift. Read
`.githooks/AGENTS.md` only when changing this gate or adding a universal check.
Do not use `--no-verify` for normal work; remote CI/branch protection remains
necessary to prevent intentional local bypasses.

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
