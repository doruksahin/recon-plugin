# docs/improvement-proposals/ — how this folder works

Versioned improvement proposals for the recon pipeline. A proposal is a release
candidate record, not an unscoped backlog note: one target version = one cohort,
and one idea = one folder inside that cohort. This file tells a future agent or
human how to read, add, and maintain those records.

## Progressive disclosure — read in this order

1. **[README.md](README.md)** — the version ledger. Read only this to identify the
   relevant proposed or shipped cohort.
2. **`<version>/README.md`** — the cohort index. It is the release-scoped list of
   proposals and their current status.
3. **`<version>/<slug>/README.md`** — one idea's concrete problem, before/after,
   and implementation sketch. Read only ideas relevant to your work; keep each
   under ~120 lines.
4. **`<version>/<slug>/*.md` extras** — optional deep material (long transcripts, spike notes,
   measurement data). Only create one when the README would otherwise bloat past its
   budget; link it from the README.

Never inline an idea's full content into the index, and never let an idea README
grow into a design doc — full designs graduate to `../plans/` (see lifecycle below).

## Adding a new proposal

1. **Reserve a future target version first.** Use an explicit SemVer directory such
   as `0.16.0`; never write a proposal directly under this directory or under an
   already released cohort. New intake starts after the latest released or already
   reserved cohort. Create `<version>/README.md` from the cohort template
   when the version directory does not yet exist.
2. Pick a kebab-case slug that names the *change*, not the complaint
   (`derive-disposition`, not `disposition-bug`). No numeric prefixes — the cohort
   table owns ordering and priority.
3. Create `docs/improvement-proposals/<version>/<slug>/README.md` and copy the idea
   template below. The full path, including `<version>`, is the proposal's durable ID.
4. Add one matching row to `<version>/README.md` and add or update that version's
   summary row in the root [README.md](README.md).
5. Every proposal MUST cite a concrete origin — a real run, ticket, or failure with a
   date. "Would be nice" ideas without an observed trigger don't get folders.

### Cohort README template

```markdown
# v<target-version> proposal cohort

> Release-scoped records proposed for v<target-version>.

- **Cohort status:** proposed | in-progress | released
- **Opened:** YYYY-MM-DD

| Proposal | Status | Prio | One-liner |
| --- | --- | --- | --- |
| [<slug>](<slug>/README.md) | proposed | P1 | <identical one-liner> |
```

## Idea README template

```markdown
# <Title — imperative, names the change>

> <One-liner, ≤100 chars, identical to the index row.>

- **Status:** proposed | accepted | in-progress | shipped (vX.Y.Z) | rejected (why)
- **Priority:** P1 | P2 | P3
- **Theme:** determinism rail | operational robustness
- **Origin:** <run/ticket + date + what actually happened>
- **Depends on:** <other idea slugs, or omit>

## Problem
<What goes wrong today and why it matters. 1–2 paragraphs.>

## Before (today)
<Concrete artifact: the actual yaml/comment/output that ships today, or the
realistic failure that nothing prevents.>

## After (proposed)
<Concrete artifact: the same case with the improvement — expected script output,
new schema shape, failing lint line. Show, don't describe.>

## Implementation sketch
<Files touched, new scripts, SKILL.md lines that get DELETED. Bullet list.>

## Open questions
<Genuine unknowns, or "None".>
```

## Rules

- **Before/After must be concrete.** Real yaml, real command output, real quotes from
  a run — not prose descriptions of what would be different. If you can't show the
  artifact, the idea isn't ready for a folder.
- **Frame the After as a rail.** Per the design formula in
  [../../recon/docs/pipeline.md](../../recon/docs/pipeline.md): execution moves onto
  rails (scripts/schemas/tables), judgment stays in the model but leaves mechanical
  evidence. An improvement that adds prose instructions to a SKILL.md is usually the
  wrong shape — the best ideas *delete* SKILL.md prose and replace it with a script.
- **Status changes update two places:** the idea README's Status line and its index
  row in the same version cohort. Update the root ledger only if that changes the
  cohort's summary.
- **Lifecycle:** `proposed` → (discussion) → `accepted` → implementation plan in
  `../plans/` when non-trivial → `in-progress` → `shipped (vX.Y.Z)`. Shipped and
  rejected folders stay — they're the record of what was tried and why. When an idea
  ships, add a `Shipped:` line linking the commit/plan.
- **This folder is docs-only.** Creating or editing proposals never bumps the plugin
  version and never touches `recon/` — the change protocol in pipeline.md applies
  only once an idea moves to implementation.
- **A version cohort is never repurposed.** Do not move a proposal from its declared
  target version to make a later release look fuller. If scope changes materially,
  preserve the original record and open a successor under the newly proposed version
  with a link to it.
- **Proposed files get italics, not backticks.** `tools/check-links.sh` resolves
  every backticked path/script name against the working tree, so a backticked
  name that doesn't exist yet fails the pre-commit hook. Write not-yet-existing
  files as *proposed-script.sh* and switch to backticks when they land.
