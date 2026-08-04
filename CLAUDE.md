# CLAUDE.md

This file provides repository-wide editor guidance to Claude Code, Codex, and
other capable coding agents. `AGENTS.md` is the Codex entry point and delegates
here so the accountable rules remain single-source.

## What this repo is

A multi-harness **agent plugin** shipping one workflow, `recon` — a deterministic Jira task recon pipeline that runs *before* planning: blocker triage → code discovery → governance routing → human approval gate. There is no application build; the deliverables are portable skill prompts (`recon/skills/*/SKILL.md`), deterministic shell/Python rails, and generated native Claude/Codex packaging.

- `.claude-plugin/marketplace.json` — marketplace root, points at `./recon`
- `.agents/plugins/marketplace.json` — generated Codex marketplace root, points at `./recon`
- `recon/.claude-plugin/plugin.json` — canonical plugin metadata; its `version` is written by the release tool, **never edit by hand**
- `recon/.codex-plugin/plugin.json` — generated native Codex manifest; never edit directly
- `recon/skills/*/agents/openai.yaml` — generated Codex skill UI metadata; never edit directly
- `recon/skills/` — the eight skills: `recon-triage` (stage 0), `recon-discovery` (stage 1), `recon-repro` (on-demand live repro), `recon-report` (HTML dossier), `recon-decree` (governance adapter), `recon-help` (orientation + setup doctor), `recon-publish` (maintainer release + distribution), `recon-state` (living per-ticket state canvas)
- `recon/scripts/` — the mechanical rails the skills call (workspace lifecycle, verdict/comment rails, routing, Jira delivery, workspace lint, doctor)
- `recon/docs/pipeline.md` — the machine spec: state machine, invariants, artifact registry mirror, trigger tables, the binding Change protocol
- `recon/docs/registry.yaml` — THE artifact registry (single source; `lint-workspace.sh` executes it)
- `evals/` — repository-only real-ticket replay laboratory: sanitized frozen inputs, separately disclosed oracles, and scorer controls; nothing here ships in the plugin
- `evals/skills/recon-replay-lab/` — repository-local LLM operator workflow for prepare → fresh-context handoff → resume → retained evaluation; it routes the lab but never owns parsing, scoring, or state
- `evals/skills/recon-improvement-loop/` — repository-local operator workflow for durable proposal iteration; it routes only from retained improvement evidence and never ships in the plugin
- `evals/version-reviews/` — repository-only schema, templates, and linked structure contract for private team review cycles grouped by the actual published plugin version
- `evals/skills/recon-version-review/` — repository-local operator workflow for capture → teammate review → consensus → cross-ticket synthesis → proposal routing; live evidence stays outside the repository
- `docs/replay-lab-report.html` — generated, drift-checked visual operator report for the laboratory; owned by `tools/render-replay-lab-report.py`, never hand-edited
- `docs/system-map.html` — generated, drift-checked maintainer overview separating the shipped runtime, private version review, replay laboratory, and improvement loop; owned by `tools/render-system-map.py`, never hand-edited
- `tools/` — repo tooling: link check, coherence check, commit-msg check, commitizen wrapper, release
- `docs/agent-behavior/` — binding outcome-first operating contract for agent proposals, skill iteration, evidence, and live demonstrations

Each of `recon/scripts/`, `recon/docs/`, `recon/skills/`, `tools/`, and `docs/` carries its own `CLAUDE.md` with a role line per file — enforced by the coherence check, so read the local one before editing in a directory.

Before proposing or changing Recon behavior, read
[`docs/agent-behavior/README.md`](docs/agent-behavior/README.md), then follow its
progressive-disclosure router. Do not preload that whole tree. Do not call a
change an improvement until the routed playbook shows the claim is bounded by
retained, rerunnable evidence from the task class it concerns.

## Improvement-proposal records

Improvement proposals are durable, version-scoped evidence, not a floating backlog.
Create each at `docs/improvement-proposals/<future-target-version>/<slug>/README.md`.
Before writing the proposal, reserve the future SemVer cohort and add its cohort
index; never add new work to a released version directory or directly below
`improvement-proposals/`. The local instructions in
[`docs/improvement-proposals/CLAUDE.md`](docs/improvement-proposals/CLAUDE.md) define
the required before/after evidence and status updates.

## Authoritative docs — read before editing

When editing this plugin you are an **"editor session"** in the sense of [recon/docs/pipeline.md](recon/docs/pipeline.md); its **Change protocol** section is binding. Key rules from it:

1. Do not hand-edit versions while implementing. A version changes only when the release rail cuts a release; that rail updates both native manifests and all version mirrors together.
2. Treat this repository as the editable source. Use `recon/scripts/activate-codex-plugin.sh` to refresh the installed local Codex package after validation. Claude marketplace/cache activation remains a release concern; never patch an installed cache as source.
3. Mechanical checks inside skills must be `find`-based, not `ls`/`grep` (user shells may alias those with non-POSIX exit codes).
4. Any new behavior must land as a **rail** (script/table/schema) or as **judgment-with-evidence**, and pipeline.md's tables must be updated in the same commit. The design formula: judgment stays in the model but must leave mechanical evidence; execution moves onto rails. A step where the model has freedom in *execution* is a defect.
5. Governance adapters follow the convention: skill named `recon-<governance>`, same contract as `recon-decree`, all governance vocabulary quarantined in that skill.
6. **Every shared fact has exactly one owner file; every other appearance is a mirror you never author.** The ownership table is Change protocol item 8 in pipeline.md; `tools/check-coherence.sh` (pre-commit, after the link check) verifies the mirrors — version stamps, registry tokens, role coverage, invariant citations, skill discoverability. When it fails, fix the owner or the named mirror; never `--no-verify` past it.
7. Run `python3 tools/generate-adapters.py` after canonical manifest or skill metadata changes. `--check` is part of coherence validation.

## Published artifacts — the mirrors the hooks cannot reach

Two kinds of pages live on claude.ai, outside this repo, and **no git hook can verify them** — they are the only mirrors kept honest by discipline instead of a rail:

- **The flow artifact** ("Recon Pipeline — Flow") — a human view of the pipeline, published from [docs/flow.html](docs/flow.html); the artifact URL lives in that file's header comment. Its version stamps are rewritten automatically by the release bump (`.cz.toml` `version_files`), so **every release changes the file** even when you didn't touch it.
- **Dossier artifacts** (`<TICKET> — Recon Dossier`) — per-run records published by `recon-report`. These are views of a finished run and are **never retro-updated**: rewriting one to match a newer pipeline would falsify what that run actually produced. Leave them alone.

**The rule: source accuracy is an implementation concern; external mirror publication is a release concern.** After editing skills, scripts, or pipeline.md, update `docs/flow.html` in the same accountable change when the flow's shape changed. Do not republish from an implementation-only run. `recon-publish` checks the release diff and republishes a changed flow to the SAME artifact URL behind its release gate. Everything in-repo is drift-checked mechanically; the release rail owns the remaining external mirror step.

## Commands

```bash
# One-time per clone: enable the versioned pre-commit gate and commit-msg check
git config core.hooksPath .githooks

# Run the full local commit gate: staged diff, links, coherence + universal controls, Decree lint
bash tools/pre-commit-check.sh

# Validate, prepare, hand off, resume, and score a frozen real-ticket replay
python3 tools/replay-ticket.py validate evals/cases/att-4845-pre-comment
bash tools/test-replay-lab.sh
python3 tools/render-replay-lab-report.py --check

# Print and validate the private external team-review layout
python3 tools/version-review.py structure
bash tools/test-version-review.sh

# Generate native Codex packaging, or fail if checked-in outputs drift
python3 tools/generate-adapters.py
python3 tools/generate-adapters.py --check

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
- Version numbers live only in the git tag (source of truth, `version_provider = "scm"`) and the two native plugin manifests (written by the tools).

## Architecture — how the pieces relate

The pipeline runs entirely in a per-ticket workspace at `$RECON_ROOT/<TICKET>/`, never in the target repo. `reconctl.sh` owns workspace resolution, local-host detection, capability reporting, preflight, and invocation rendering; the backward-compatible default root is `~/.claude/recon`. Each skill owns exactly one stage directory (`triage/`, `discovery/`, `route/`, `repro/`, `report/`); every file a run may write is declared in pipeline.md's artifact registry, and `lint-workspace.sh` enforces that mechanically at the end of every stage.

Control flow: `recon-triage` runs six blocker checks → `READY` auto-chains into `recon-discovery` (code surface + Gherkin contract → routing → approval gate → STOP), while `BLOCKED`/`NEEDS_INFO` drafts a shape-verified Jira comment plus attachments behind a single human approval gate → STOP. Routing has exactly two producers writing `route/routing.yaml`: `scripts/route-generic.sh` (governance `none`) or an adapter skill like `recon-decree` (governance resolved by `scripts/detect-governance.sh` via env > config > probe, opt-in only). The pipeline never implements code — implementation is a new session entered via the handoff printed verbatim from `routing.yaml`.

Invariants worth internalizing before touching any skill or script (full list in pipeline.md): step 0 (`fresh-workspace.sh`) runs exactly once per run and archives prior runs into `runs/` which nothing may ever read; recon's own Jira comments carry a `~recon-triage~` marker and are excluded from evidence; no mutating Jira call happens without explicit in-session approval; attachments in the `recon-*-<TICKET>.*` namespace are replaced (delete-then-upload, always before the comment posts), never accumulated; when governance is `none`, decree vocabulary is banned from every artifact and lint greps for leakage.

Skill SKILL.md files are authoritative over pipeline.md for their own stage; on conflict, SKILL.md wins — but keep them consistent in the same commit.

For repository-only replay work, route start, resume, state, evaluation,
comparison, and explanation requests through
`evals/skills/recon-replay-lab/SKILL.md`. It is not a runtime stage and must not
be moved under `recon/skills/` or added to plugin manifests.

For a plugin-improvement/resume request, route through
`evals/skills/recon-improvement-loop/SKILL.md` first. Its state rail, not chat
history, owns the next action; it is likewise repository-only.

For a version-scoped team-review request, route through
`evals/skills/recon-version-review/SKILL.md`. Its external-root state rail owns
the lifecycle; the checked-in schema and templates own the semantic interface.
Do not use Jira comments as the review store and do not treat teammate feedback
as improvement evidence until a bounded proposal enters the replay/improvement
loop.
