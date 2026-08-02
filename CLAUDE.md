# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A Claude Code **plugin marketplace** shipping one plugin, `recon` — a deterministic Jira task recon pipeline that runs *before* planning: blocker triage → code discovery → governance routing → human approval gate. There is no application code, build step, or test suite; the deliverables are skill prompts (`recon/skills/*/SKILL.md`) and the shell scripts that rail them (`recon/scripts/*.sh`).

- `.claude-plugin/marketplace.json` — marketplace root, points at `./recon`
- `recon/.claude-plugin/plugin.json` — the plugin manifest; its `version` is written by the release tool, **never edit by hand**
- `recon/skills/` — the six skills: `recon-triage` (stage 0), `recon-discovery` (stage 1), `recon-repro` (on-demand live repro), `recon-report` (HTML dossier), `recon-decree` (governance adapter), `recon-help` (orientation + setup doctor)
- `recon/scripts/` — the mechanical rails the skills call (workspace lifecycle, verdict/comment rails, routing, Jira delivery, workspace lint, doctor)
- `recon/docs/pipeline.md` — the machine spec: state machine, invariants, artifact registry mirror, trigger tables, the binding Change protocol
- `recon/docs/registry.yaml` — THE artifact registry (single source; `lint-workspace.sh` executes it)
- `tools/` — repo tooling: link check, coherence check, commit-msg check, commitizen wrapper, release

Each of `recon/scripts/`, `recon/docs/`, `recon/skills/`, `tools/`, and `docs/` carries its own `CLAUDE.md` with a role line per file — enforced by the coherence check, so read the local one before editing in a directory.

## Authoritative docs — read before editing

When editing this plugin you are an **"editor session"** in the sense of [recon/docs/pipeline.md](recon/docs/pipeline.md); its **Change protocol** section is binding. Key rules from it:

1. Bump `recon/.claude-plugin/plugin.json` version on every change (normally done by the release tool).
2. Two clones exist — this one and `~/.claude/plugins/marketplaces/recon-plugin` — keep both synced with `origin/master`. To activate a local change without `/plugin install`, copy `recon/` into `~/.claude/plugins/cache/recon-plugin/recon/<version>/` and repoint `~/.claude/plugins/installed_plugins.json`; never delete the previously pinned cache dir.
3. Mechanical checks inside skills must be `find`-based, not `ls`/`grep` (user shells may alias those with non-POSIX exit codes).
4. Any new behavior must land as a **rail** (script/table/schema) or as **judgment-with-evidence**, and pipeline.md's tables must be updated in the same commit. The design formula: judgment stays in the model but must leave mechanical evidence; execution moves onto rails. A step where the model has freedom in *execution* is a defect.
5. Governance adapters follow the convention: skill named `recon-<governance>`, same contract as `recon-decree`, all governance vocabulary quarantined in that skill.
6. **Every shared fact has exactly one owner file; every other appearance is a mirror you never author.** The ownership table is Change protocol item 8 in pipeline.md; `tools/check-coherence.sh` (pre-commit, after the link check) verifies the mirrors — version stamps, registry tokens, role coverage, invariant citations, skill discoverability. When it fails, fix the owner or the named mirror; never `--no-verify` past it.

## Published artifacts — the mirrors the hooks cannot reach

Two kinds of pages live on claude.ai, outside this repo, and **no git hook can verify them** — they are the only mirrors kept honest by discipline instead of a rail:

- **The flow artifact** ("Recon Pipeline — Flow") — a human view of the pipeline, published from [docs/flow.html](docs/flow.html); the artifact URL lives in that file's header comment. Its version stamps are rewritten automatically by the release bump (`.cz.toml` `version_files`), so **every release changes the file** even when you didn't touch it.
- **Dossier artifacts** (`<TICKET> — Recon Dossier`) — per-run records published by `recon-report`. These are views of a finished run and are **never retro-updated**: rewriting one to match a newer pipeline would falsify what that run actually produced. Leave them alone.

**The rule: any change to the flow ends with the question "does the published flow artifact still match `docs/flow.html`?"** Concretely — after editing skills, scripts, pipeline.md, or cutting a release, check whether `docs/flow.html` changed (edit or version bump); if it did, update its content if the flow's shape changed, then republish it to the SAME artifact URL. Everything in-repo is drift-checked mechanically; this one republish step is the manual link in the chain — treat it as part of the change, not an afterthought.

## Commands

```bash
# One-time per clone: enable the git hooks (pre-commit link check, commit-msg format check)
git config core.hooksPath .githooks

# Check that docs don't reference files that no longer exist (also runs as pre-commit)
bash tools/check-links.sh

# Check that mirrored facts still agree with their owner files (also runs as pre-commit)
bash tools/check-coherence.sh

# Preview the next release (version + changelog) without cutting it
tools/cz.sh bump --changelog --dry-run

# Cut a release: bumps version, regenerates CHANGELOG.md, tags, pushes, opens GitHub Release
tools/release.sh

# Runtime check of a recon workspace against the artifact registry (used by the skills, not CI)
bash recon/scripts/lint-workspace.sh <TICKET>
```

Optional tooling: `lychee` (external URL checking in the link check) and `uv` (commit-msg check + commitizen via `uvx`). The hooks warn instead of blocking when these are missing.

## Commit convention (not cosmetic)

`CHANGELOG.md` is generated from commit subjects — an unparseable subject is silently dropped from release notes. Format is `type(scope): subject`; full rules in [CONTRIBUTING.md](CONTRIBUTING.md). Essentials:

- **Commit atomically — every commit is an accountable unit.** One logical change per commit, nothing else riding along. A change travels WITH everything that keeps it true: the rail plus the SKILL.md that invokes it, the schema plus its parser, the fact plus its mirrors and pipeline.md tables — never "docs in a follow-up commit". Each commit must pass the full hook chain on its own, and its subject must honestly name the whole diff; if you can't write one honest subject line for it, split the commit. The git history is the audit trail for why the pipeline behaves as it does — a mixed commit hides which change caused what.

- Scope names **what a teammate would notice** (`comment`, `attachments`, `gate`, `triage`, `discovery`, `repro`, `report`, `routing`, `workspace`, `scripts`, `tools`), not which file changed.
- `feat` → minor, `fix`/`perf`/`refactor` → patch; `docs`/`chore`/`ci`/`test`/`style`/`revert` produce no changelog line and no release. Back out a user-visible change as `fix:`, never `revert:`.
- Breaking changes need `!` **and** a `BREAKING CHANGE:` footer (the footer is the only place the migration note lands). Breaking = workspace layout/artifact-contract change, skill rename/removal, gate-semantics change, or comment-marker format change. Pre-1.0, `!` bumps minor (`major_version_zero` in `.cz.toml`).
- Version numbers live only in the git tag (source of truth, `version_provider = "scm"`) and `recon/.claude-plugin/plugin.json` (written by the tools).

## Architecture — how the pieces relate

The pipeline runs entirely in a per-ticket workspace at `~/.claude/recon/<TICKET>/`, never in the target repo. Each skill owns exactly one stage directory (`triage/`, `discovery/`, `route/`, `repro/`, `report/`); every file a run may write is declared in pipeline.md's artifact registry, and `lint-workspace.sh` enforces that mechanically at the end of every stage.

Control flow: `recon-triage` runs six blocker checks → `READY` auto-chains into `recon-discovery` (code surface + Gherkin contract → routing → approval gate → STOP), while `BLOCKED`/`NEEDS_INFO` drafts a shape-verified Jira comment plus attachments behind a single human approval gate → STOP. Routing has exactly two producers writing `route/routing.yaml`: `scripts/route-generic.sh` (governance `none`) or an adapter skill like `recon-decree` (governance resolved by `scripts/detect-governance.sh` via env > config > probe, opt-in only). The pipeline never implements code — implementation is a new session entered via the handoff printed verbatim from `routing.yaml`.

Invariants worth internalizing before touching any skill or script (full list in pipeline.md): step 0 (`fresh-workspace.sh`) runs exactly once per run and archives prior runs into `runs/` which nothing may ever read; recon's own Jira comments carry a `~recon-triage~` marker and are excluded from evidence; no mutating Jira call happens without explicit in-session approval; attachments in the `recon-*-<TICKET>.*` namespace are replaced (delete-then-upload, always before the comment posts), never accumulated; when governance is `none`, decree vocabulary is banned from every artifact and lint greps for leakage.

Skill SKILL.md files are authoritative over pipeline.md for their own stage; on conflict, SKILL.md wins — but keep them consistent in the same commit.
