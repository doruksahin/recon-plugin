# One gated flow from commit to activated cache

> recon-publish + activate-plugin.sh: release, distribute, republish mirrors, smoke test

- **Status:** shipped (v0.12.0) — implemented 2 Aug 2026 (`recon/skills/recon-publish/`,
  `recon/scripts/activate-plugin.sh`, `release.sh --yes` + coherence guard)
- **Priority:** P2
- **Theme:** operational robustness
- **Origin:** 1–2 Aug 2026 — the publish ritual (push, two GitHub releases,
  marketplace-clone sync, cache copy, installed_plugins.json repoint, artifact
  republish, smoke test) was performed three times by hand across v0.9.0–v0.11.0;
  every step existed only in session transcripts.

## Problem

Releasing was railed (`release.sh`) but distribution was not: cache activation
and clone sync were improvised ad-hoc Bash each time — exactly the "model has
freedom in execution" defect the design formula bans — and the artifact-mirror
republish relied on discipline alone. With more marketplaces and plugins
coming, the ritual multiplies.

## Before (observed, v0.9.0–v0.11.0)

Each publish: hand-written `git push --follow-tags`, hand-sliced changelog for
`gh release create`, hand-written python to repoint `installed_plugins.json`,
a remembered `cp -R` with a remembered "don't delete old dirs" rule, and a
remembered flow-artifact republish.

## After (implemented)

`/recon:recon-publish` — one gated flow:

1. preflight (clean tree, master) → dry-run preview
2. ONE AskUserQuestion gate → `tools/release.sh --yes` (bump, tag, push,
   GitHub Release; `--yes` exists only for orchestration after that explicit
   approval — release.sh also gained the coherence check as guard [2/5])
3. `activate-plugin.sh` — plugin-AGNOSTIC rail: identity from the source
   repo's own `marketplace.json` + `plugin.json`s; cache copy (pinned dirs
   never deleted); `installed_plugins.json` repoint behind a shape validation
   that fails loudly (it is Claude Code internal format, not a contract);
   marketplace-clone fast-forward from `known_marketplaces.json`
4. republish changed artifact mirrors (files whose header carries
   `Published at: <url>`) — fires on virtually every release since the bump
   rewrites flow.html's stamps
5. smoke test from the activated cache path

## Implementation sketch

Shipped as described. Planned extraction: the skill is parked under recon by
the user's explicit call; `activate-plugin.sh` takes a source-root argument and
reads only generic manifests, so moving both to a shared devkit plugin later is
a file move plus the devkit's three-file registration checklist.

## Open questions

- When extracted, should mirror discovery (the `Published at:` header
  convention) become a declared list in `marketplace.json` instead of a
  header grep? Decide at extraction time, when a second repo uses it.
