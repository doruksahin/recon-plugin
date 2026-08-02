# Banned-phrase lint on the remaining free text

> Banned-phrase denylist + structural caps on the remaining free-text slots

- **Status:** proposed
- **Priority:** P3
- **Theme:** determinism rail
- **Origin:** ATT-5107 triage run, 1 Aug 2026 — dossier headline/lede and blocker
  packs are the only surviving free-text surfaces, and their style is governed by
  nothing but the model's taste on the day.

## Problem

After [derive-disposition](../derive-disposition/README.md) and
[render-comment](../render-comment/README.md), free text survives only in: asks,
detail packs, dossier headline, lede. Those are human-facing — the places slop
costs the most credibility — and the only defense is prose style guidance, which is
exactly the kind of instruction models drift on.

## Before (today)

Nothing fails this lede:

> "This comprehensive triage delves into the robust set of blockers. It's worth
> noting that the seamless resolution of these items will leverage cross-team
> alignment."

Says nothing, flags nothing, reads like a template. For contrast, the 1 Aug run's
actual lede passes every check below: *"Nothing on the FE side can move until the
design source of truth is picked, the video is hosted…"* — concrete nouns, no
filler.

## After (proposed)

```
$ bash recon/scripts/verify-triage.sh ATT-5107
slop check: FAIL — lede contains 'comprehensive' (denylist:12)
slop check: FAIL — lede contains 'leverage' (denylist:31)
slop check: FAIL — lede contains "It's worth noting" (denylist:3)
structure: FAIL — blocker 3 has 7 option bullets (cap: 5)
```

Two parts, both dumb on purpose:

- **Denylist** (*recon/scripts/slop-denylist.txt*, one phrase per line):
  comprehensive, robust, seamless, leverage, delve, "It's worth noting",
  "In conclusion", "Additionally,", crucial, vital, streamline, holistic… Editable
  without touching any skill.
- **Structural caps:** ≤ 5 option bullets per blocker, ≤ 5 evidence lines per
  blocker, no nested lists in any human-facing field, lede ≤ 2 sentences.

Crude beats clever here: the check is deterministic, and padding words stop
appearing the moment they cost a failed lint instead of a style note.

## Implementation sketch

- A pass inside `verify-triage.sh` ([validate-triage-yaml](../validate-triage-yaml/README.md))
  over ask/detail/headline/lede fields, plus the denylist file.
- Delete the style-guidance sentences from `recon-triage` and `recon-report`
  SKILL.md; point at the script.

## Open questions

- Denylist seeding: start from the common LLM-slop lists, then add whatever actually
  appears in past dossiers (grep the `runs/` archives of a few workspaces offline —
  fine for tooling, it's not a triage input).
- Case-sensitivity and word-boundary rules ("delve" vs "delves" — match on stem).
