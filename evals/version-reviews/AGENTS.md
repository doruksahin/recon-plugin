# Version-review agent guide

This directory defines the repository-only contract for private team review
cycles grouped by the **published Recon plugin version that produced the
reports**. Read the parent [evaluation guide](../AGENTS.md), then use the
[operator skill](../skills/recon-version-review/SKILL.md).

Authoritative owners:

- [schema.yaml](schema.yaml) — lifecycle, enums, capture allowlist, and semantic
  document shapes.
- [version-review.py](../../tools/version-review.py) — every external-root
  mutation, hash, state transition, and validation.
- [README.md](README.md) — folder model, privacy boundary, and bridge into the
  replay and improvement laboratories.
- [templates/](templates/) — authored semantic input examples; the rail
  validates them in repository controls.

Never put a live dossier, Jira export, workspace bundle, teammate review, or
private review root in this repository. Those belong in an external private
root. Do not hand-write generated indexes, receipts, manifests, hashes,
version state, or closure counts.
