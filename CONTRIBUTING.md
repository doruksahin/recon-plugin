# Contributing

## The commit is the changelog entry

`CHANGELOG.md` is generated from commit subjects — nobody writes it by hand, and
edits to it are overwritten by the next release. So the subject line you write is
the sentence a teammate reads when they wonder why their ticket looks different
this week. Write it for them, not for the diff.

This matters more here than in a normal repo: the plugin cache keeps one
directory per version, and every run stamps its plugin version into `meta.yaml`.
A teammate on 0.6.0 and a teammate on 0.8.0 get genuinely different pipelines,
and the changelog is how they find out which one they are on.

## Format

```
type(scope): subject
```

```
feat(comment): link the dossier attachment from the comment header line
fix(attachments): skip re-upload when the dossier is byte-identical to the attached one
```

### Types

| Type | Changelog section | Version |
| --- | --- | --- |
| `feat` | Features | minor |
| `fix` | Bug Fixes | patch |
| `perf` | Performance | patch |
| `refactor` | Internal | patch |
| `docs` `chore` `ci` `build` `test` `style` | — none — | none |
| `revert` | — none — | none |

Two traps in that table:

- **`revert` produces no changelog line and no release.** If you back out
  something a teammate could have noticed, write it as `fix:` and say what
  changed back. A silent revert is worse than a noisy one.
- **An unparseable subject vanishes entirely.** It is not rendered wrong, it is
  absent. `.githooks/commit-msg` exists to catch that before it happens.

### Scopes

The scope is rendered as the bold prefix of the changelog line, so it should
name **what a teammate would notice**, not which file you touched. Prefer the
first group; fall back to the second.

| Scope | Covers |
| --- | --- |
| `comment` | the Jira comment recon posts |
| `attachments` | what recon uploads to the ticket |
| `gate` | the human approval gate — what you are asked to approve |
| `triage` `discovery` `repro` `report` `routing` | a pipeline stage's own behavior |
| `workspace` | the run tree and the artifact contract |
| `scripts` | the shell rails |
| `tools` | repo tooling — link check, release |

`feat(scripts): package-artifacts.sh delivery-bundle rail` is a real commit from
this repo's history and a good example of the wrong choice: it tells a teammate
nothing. `feat(attachments): blocked tickets now carry a zip of the run` is the
same change, scoped to what they see.

### Breaking changes

Mark with `!` **and** a `BREAKING CHANGE:` footer. The subject appears under
Features; the footer is the only place the migration note lands, so write it for
someone whose workspace just stopped linting.

```
feat(workspace)!: move repro screenshots under repro/exhibits/

BREAKING CHANGE: repro screenshots moved from exhibits/ to repro/exhibits/.
Workspaces written by 0.7.x fail lint until the ticket is re-run.
```

Breaking means a teammate's existing habit or a downstream consumer breaks:

- workspace layout or artifact-contract changes — moved or renamed paths under
  `triage/`, `discovery/`, `route/`, `repro/`, `report/`
- a skill renamed or removed, because the invocation changes
- gate semantics — a change to what the human is being asked to approve
- the Jira comment marker format, because older comments stop being recognized
  as recon's and a re-run posts a second one instead of editing the first

Not breaking: adding a check, adding an artifact, changing prose.

While the plugin is pre-1.0, `!` bumps the **minor** version, never to 1.0.0.
That is `major_version_zero` in `.cz.toml`; drop it the day recon goes 1.0.

## Releasing

```bash
tools/release.sh
```

It refuses on a non-`master` branch, a dirty tree, an empty commit range, or
link drift; shows you the exact version and changelog and waits for a `y`; then
bumps, tags, pushes, and opens the GitHub Release with that version's section as
the body.

Version numbers live in exactly two places, both written for you: the git tag
(the source of truth, via `version_provider = "scm"`) and
`recon/.claude-plugin/plugin.json`. Never edit either by hand.

To see what the next release would be without cutting it:

```bash
tools/cz.sh bump --changelog --dry-run
```

## Fresh clone

```bash
git config core.hooksPath .githooks
```

That wires both hooks: `pre-commit` runs the fail-closed
`tools/pre-commit-check.sh` rail (staged diff, local references, generated
views, universal controls, and Decree records), while `commit-msg` runs
`tools/check-commit-msg.sh` (subjects that would not reach the changelog).
Install `uv` before committing; missing required local tooling blocks the
pre-commit rail. Do not bypass normal checks with `git commit --no-verify`;
CI and branch protection remain the remote enforcement boundary.

Commitizen is resolved by `tools/cz.sh` — an installed `cz` if you have one,
otherwise `uvx`, which needs no install.
