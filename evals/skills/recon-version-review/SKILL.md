---
name: recon-version-review
description: Operate a private team-review cycle grouped by the published Recon plugin version that produced each dossier.
---

# Recon Version Review

Collect and review many Recon reports under one actual published plugin
version without posting to Jira or writing arbitrary files into a Recon
workspace. This skill is repository-local and never ships in the plugin.

Read the [laboratory contract](../../version-reviews/README.md) before acting.
The [schema](../../version-reviews/schema.yaml) owns fields and enums;
`tools/version-review.py` owns every path, state transition, hash, and mutation.

## Contract

- **Input:** an external private review root and one published plugin version.
- **Reads:** local current-run Recon workspaces and authored semantic YAML.
- **Writes:** only through the rail beneath
  `<review-root>/versions/v<version>/`.
- **External side effects:** none; no Jira, repository, release, activation, or
  publication mutation.

## Rules

1. Run `state` before interpreting or mutating an existing version cycle.
2. Never place a live review root, dossier, Jira export, or teammate feedback
   in this repository or inside `$RECON_ROOT`.
3. At Recon's delivery gate choose **Don't post**. Capture rejects successful
   Jira response artifacts and non-declined posting-gate records.
4. Teammates author only files shaped by the checked-in
   [templates](../../version-reviews/templates/). Import them with the rail;
   never hand-edit external receipts, manifests, indexes, hashes, status, or
   closure counts.
5. A synthesis decision of `PROPOSE` is only a link to a future proposal. Use
   the [replay skill](../recon-replay-lab/SKILL.md) and
   [improvement skill](../recon-improvement-loop/SKILL.md) before changing or
   claiming improvement in Recon.

## Workflow

From the repository root:

```bash
python3 tools/version-review.py init <review-root> \
  --plugin-version <X.Y.Z> --plugin-tag <vX.Y.Z> \
  --plugin-commit <full-release-commit>

python3 tools/version-review.py capture <review-root> \
  --plugin-version <X.Y.Z> --ticket <ATT-N> \
  --workspace <absolute-current-run-workspace> \
  --target-repository <name> --target-commit <full-commit>

python3 tools/version-review.py begin-review <review-root> \
  --plugin-version <X.Y.Z>

python3 tools/version-review.py add-review <review-root> \
  --plugin-version <X.Y.Z> --from <authored-review.yaml>

python3 tools/version-review.py add-consensus <review-root> \
  --plugin-version <X.Y.Z> --from <authored-consensus.yaml>

python3 tools/version-review.py synthesize <review-root> \
  --plugin-version <X.Y.Z> --findings <findings.yaml> \
  --themes <themes.yaml> --decisions <decisions.yaml>

python3 tools/version-review.py close <review-root> \
  --plugin-version <X.Y.Z> --from <closure.yaml>
```

Before every resume or handoff:

```bash
python3 tools/version-review.py state <review-root> --plugin-version <X.Y.Z>
```

Follow only the validated state's allowed actions. A contract error exits 2;
report it without modifying the external tree manually.

## Report

Return the external version directory, validated state, ticket/run counts,
review and consensus coverage, synthesis status, and exact allowed next
commands. State explicitly that teammate review is evidence, not proof of a
general Recon improvement.
