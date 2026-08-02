# docs/improvements/ — how this folder works

Improvement ideas for the recon pipeline. One idea = one folder. This file tells you
(a future Claude session or a human) how to read, add, and maintain them.

## Progressive disclosure — read in this order

1. **[README.md](README.md)** — the index. One line per idea with status + priority.
   Read only this to know what exists.
2. **`<slug>/README.md`** — the idea itself: problem, concrete before/after, sketch.
   Read only the ideas relevant to what you're doing. Keep each under ~120 lines.
3. **`<slug>/*.md` extras** — optional deep material (long transcripts, spike notes,
   measurement data). Only create one when the README would otherwise bloat past its
   budget; link it from the README.

Never inline an idea's full content into the index, and never let an idea README
grow into a design doc — full designs graduate to `../plans/` (see lifecycle below).

## Adding a new idea

1. Pick a kebab-case slug that names the *change*, not the complaint
   (`derive-disposition`, not `disposition-bug`). No numeric prefixes — the index
   table owns ordering and priority.
2. `mkdir <slug>` and copy the template below into `<slug>/README.md`.
3. Add ONE row to the index table in [README.md](README.md), matching the one-liner.
4. Every idea MUST cite a concrete origin — a real run, ticket, or failure with a
   date. "Would be nice" ideas without an observed trigger don't get folders.

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
  row. Nothing else.
- **Lifecycle:** `proposed` → (discussion) → `accepted` → implementation plan in
  `../plans/` when non-trivial → `in-progress` → `shipped (vX.Y.Z)`. Shipped and
  rejected folders stay — they're the record of what was tried and why. When an idea
  ships, add a `Shipped:` line linking the commit/plan.
- **This folder is docs-only.** Creating or editing ideas never bumps the plugin
  version and never touches `recon/` — the change protocol in pipeline.md applies
  only once an idea moves to implementation.
- **Proposed files get italics, not backticks.** `tools/check-links.sh` resolves
  every backticked path/script name against the working tree, so a backticked
  name that doesn't exist yet fails the pre-commit hook. Write not-yet-existing
  files as *proposed-script.sh* and switch to backticks when they land.
