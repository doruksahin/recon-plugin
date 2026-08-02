# Bound the mirrored facts; check agreement pre-commit

> One owner file per shared fact; check-coherence.sh fails commits whose mirrors drift

- **Status:** shipped (v0.9.0) — implemented 1 Aug 2026 (`recon/docs/registry.yaml`
  single-source registry, `tools/check-coherence.sh` in the pre-commit chain,
  role CLAUDE.mds in five directories, ownership table as Change protocol
  item 8)
- **Priority:** P1
- **Theme:** determinism rail
- **Origin:** 1 Aug 2026 — one flow change (verify/render rails) required editing
  SEVEN surfaces from memory, and the published flow page had already drifted
  (v0.7.0 chip while `plugin.json` said 0.8.0).

## Problem

Facts about the flow live in multiple places with no declared owner. The
artifact registry existed in FOUR copies (`lint-workspace.sh` case list,
pipeline.md table, workspace-index.md prose, flow.html table); version stamps
in flow.html had no tie to `plugin.json`; invariant numbers are cited
repo-wide with nothing guaranteeing they still exist. `check-links.sh` proves
files exist — nothing proved the facts still agree.

## Before (1 Aug, observed)

```
docs/flow.html:      <span class="chip ver">recon v0.7.0</span>   ← published, live
plugin.json:         "version": "0.8.0"                            ← nothing compares them
```

Adding one workspace artifact required remembering four edits in four files;
three of the four failure modes were silent.

## After (implemented)

- `recon/docs/registry.yaml` is THE registry: `lint-workspace.sh` executes its
  `pattern` globs (the hardcoded case list is gone); each entry's `token` must
  appear in the three mirror docs.
- `tools/check-coherence.sh` runs after check-links in `.githooks/pre-commit`:

```
[1/4] version stamps → plugin.json        (lines carrying the version marker comment)
[2/4] registry tokens → mirror docs       (pipeline.md · workspace-index.md · flow.html)
[3/4] role coverage → directory CLAUDE.md (files must not outrun their role docs)
[4/4] invariant citations → pipeline.md   ("invariant N" must cite an existing N)
coherence: clean — version v0.8.0 stamped, registry mirrored, roles covered, citations valid
```

- The ownership table (fact → owner → mirrors) is Change protocol item 8 in
  pipeline.md; directory `CLAUDE.md` role docs cover `recon/scripts/`,
  `recon/docs/`, `recon/skills/`, `tools/`, `docs/`.

## Implementation sketch

Shipped as described above. Remaining:

- Release-tool reminder: when the diff since the last tag touches
  `docs/flow.html`, print "republish the flow artifact" (the one mirror a git
  hook cannot reach).
- Schema fixture proving SKILL.md's `triage.yaml` block and `triage-tools.py`
  parse identically — first slice of [golden-fixtures](../../0.14.0/golden-fixtures/README.md).

## Open questions

- Should the role-coverage pass extend to `recon/skills/*/` contents (scripts
  or assets inside a skill dir)? Start with top-level entries; extend if a
  skill grows helper files.
