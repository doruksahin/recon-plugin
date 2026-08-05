# Version-scoped team review laboratory

This repository-only laboratory collects teammate review of Recon dossiers by
the **actual published plugin version** that produced them. It never groups by
sprint, never writes inside `$RECON_ROOT/<TICKET>/`, and never posts to Jira.

The complete machine contract is [schema.yaml](schema.yaml). All mutations go
through [tools/version-review.py](../../tools/version-review.py); agents start
with the [version-review skill](../skills/recon-version-review/SKILL.md). The
live review root is the top level of a distinct private GitHub repository and
is external to this source repository. The initial team store is the private
`AdCreative-ai/recon-team-reviews` repository; never place evidence in either
the canonical public plugin repository or its public personal fork.

## External folder model

Print the exact current structure and commands instead of copying a stale tree:

```bash
python3 tools/version-review.py structure
python3 tools/version-review.py --help
```

One published version owns one append-only cycle at
`<review-root>/versions/vX.Y.Z/`. A ticket may have multiple immutable run IDs
under that version. A later plugin version gets a new sibling directory; runs
are never moved between versions.

`init` verifies the local Git top level and `origin`, asks GitHub for the live
visibility, and pins the verified repository identity in `version.yaml`.
Every mutating command repeats the live privacy check before writing. `state`
and `validate` intentionally use only the pinned identity plus local Git state,
so teammates can inspect an existing cycle while GitHub is temporarily
unavailable. A changed origin still fails closed.

## Evidence boundary

Capture retains only the paths listed under `capture_paths` in
[schema.yaml](schema.yaml). It excludes raw `ticket.json`, `aux-*` responses,
Jira drafts/results, `history.ndjson`, and archived `runs/`. A self-contained
dossier may still quote private ticket material, so the external root must stay
private.

The rail rejects a workspace containing successful Jira response artifacts.
If `post-gate.yaml` exists, its final exchange must be `declined`. Local Jira
draft/audit files may exist in the source workspace but are never copied.

## Semantic versus mechanical ownership

Teammates author reviews, consensus, normalized findings, themes, decisions,
and closure reasoning from the checked-in [templates](templates/). The rail
validates and imports them immutably. The rail alone owns identities, report
hash joins, allowed categories, cross-file references, manifests, counts, and
lifecycle transitions.

## From feedback to a Recon change

A `PROPOSE` decision links to a future planning cohort under
[docs/improvement-proposals](../../docs/improvement-proposals/README.md). It is
not evidence that Recon improved. Selected private evidence must first become a
sanitized case under the [replay laboratory](../README.md), then follow the
[persistent improvement loop](../skills/recon-improvement-loop/SKILL.md) with
baseline, candidate, negative control, comparison, and semantic review.

The producing-version review tree remains immutable throughout. For example,
feedback produced by v0.19.0 stays under `versions/v0.19.0/` even if an accepted
proposal later ships in v0.20.0.
