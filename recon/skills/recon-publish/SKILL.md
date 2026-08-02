---
description: Release and distribute this plugin end-to-end — cut the version, push + GitHub release, activate the new version in the local plugin cache, sync the marketplace clone, republish declared artifact mirrors. Use when asked to publish, release, ship, bump-and-push, or activate the plugin.
---

# Recon Publish

The whole publish ritual as one gated flow: everything that must happen between
"the work is committed" and "new sessions load the new version and the
published mirrors match". Runs from the plugin SOURCE repo. (Parked under
recon for now; `activate-plugin.sh` is deliberately plugin-agnostic so this
skill can extract to a shared devkit later.)

## Contract

- **Input:** none (operates on the marketplace repo you are in)
- **Reads:** the repo, `~/.claude/plugins/{installed_plugins.json, known_marketplaces.json}`
- **Writes:** the release commit + tag (via `tools/release.sh`), the plugin cache dir for the new version, the repointed `installed_plugins.json` entry, the fast-forwarded marketplace clone
- **External side effects:** `git push --follow-tags` + a GitHub Release (inside `release.sh`), and republishing any changed artifact mirrors — ALL behind the single approval gate below
- **May invoke:** nothing

---

## ⚠️ CRITICAL: Rules

1. **One explicit approval, before anything irreversible.** Show the dry-run
   preview (version + changelog) via AskUserQuestion; only a "release" answer
   authorizes `release.sh --yes` — which pushes and publishes the GitHub
   Release. NEVER pass `--yes` without that in-session approval, and never
   pipe `y` into the interactive prompt.
2. **Commits happen BEFORE this skill.** `release.sh` refuses a dirty tree by
   design. If the tree is dirty, stop and tell the user what is uncommitted —
   do not commit for them here; atomic commits are their own accountable act
   (root CLAUDE.md commit convention).
3. **Activation is the rail's job.** `activate-plugin.sh` validates
   `installed_plugins.json`'s shape and fails loudly on surprise — if it
   refuses, report its message verbatim; do NOT hand-edit that file to push
   past it.
4. **Mirrors close the loop.** After the release, any file changed since the
   previous tag whose header comment carries `Published at: <artifact URL>`
   must be republished to that exact URL (the version bump rewrites
   `docs/flow.html`'s stamps, so this fires on virtually every release).

---

## Workflow

1. **Preflight.** `git status --porcelain` must be empty and the branch must be
   `master` — otherwise stop (rule 2). Then preview:

```bash
tools/cz.sh bump --changelog --dry-run
```

2. **Gate.** AskUserQuestion with the exact version and changelog section from
   the preview. Options: `Release <version> (push + GitHub Release)` /
   `Don't release`. On "don't": STOP — report nothing was changed.

3. **Release** (bump commit, tag, push, GitHub Release — the rail owns the
   ordering and its own checks):

```bash
tools/release.sh --yes
```

4. **Activate + sync** (cache copy, `installed_plugins.json` repoint, clone
   fast-forward — quote its `activated:` / `cache:` / `clone:` lines):

```bash
bash recon/scripts/activate-plugin.sh
```

5. **Republish changed mirrors.** List files changed by the release whose head
   carries a published-artifact header, then republish each to its URL with the
   Artifact tool (same URL, same favicon, label = the new version):

```bash
git diff --name-only "$(git describe --tags --abbrev=0 --exclude "$(git describe --tags --abbrev=0)")"..HEAD -- '*.html' | while read -r f; do head -3 "$f" | grep -q 'Published at:' && echo "$f"; done
```

   (Simpler equivalent: check whether `docs/flow.html` changed between the
   previous tag and HEAD — today it is the only mirror file.)

6. **Smoke test from the activated cache** — one rail invoked via the cache
   path printed by step 4 (for recon: `scripts/doctor.sh`), proving new
   sessions get the new version.

---

## Report

Print:

```
Released: v<version> — <GitHub release URL>
Activated: <activate-plugin.sh output lines, verbatim>
Mirrors: <artifact URL republished at v<version> | none changed>
Smoke: <first line of the cache-path rail's output>
Note: sessions already running keep their loaded skill text; new sessions load v<version>.
```
