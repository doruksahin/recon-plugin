# Repository-local evaluation skills

Skills under this directory operate repository-only evidence workflows and
must never be added to the shipped plugin manifests. Start with the parent
[evals guide](../AGENTS.md), then read exactly one task router:

- [recon-replay-lab](recon-replay-lab/SKILL.md) for one frozen replay.
- [recon-improvement-loop](recon-improvement-loop/SKILL.md) for retained
  baseline/candidate/control comparison and review.
- [recon-version-review](recon-version-review/SKILL.md) for private teammate
  review cycles grouped by the plugin version that produced each dossier.

Each skill routes semantic work but delegates paths, state, hashes, parsing,
and mutations to its linked deterministic rail. Do not reconstruct progress
from chat history or add repository-local skills to `recon/skills/`.
