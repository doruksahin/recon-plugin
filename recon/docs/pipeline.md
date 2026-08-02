# Recon Pipeline — Machine Spec

Audience: LLM sessions. Three reader roles:
- **Pipeline session** — executing a recon skill. Your skill's SKILL.md is authoritative; this doc gives you the whole-chain view. On conflict, SKILL.md wins.
- **Implementer session** — implementing an approved ticket. Read [Consuming the artifacts](#consuming-the-artifacts-implementer-sessions).
- **Editor session** — modifying this plugin. Read [Change protocol](#change-protocol-editor-sessions).

Design formula (all changes must preserve it): **judgment stays in the model but must leave mechanical evidence; execution moves onto rails** (scripts, schemas, condition-table triggers, markers). A step where the model has freedom in *execution* is a defect.

## State machine

| # | Stage | Skill | Entry condition | Exit states |
|---|---|---|---|---|
| 0 | Fresh workspace | recon-triage step 0 | always (script-guarded: once per run) | workspace = `meta.yaml` (+ `runs/`) only |
| 1 | Blocker triage | recon-triage | ticket ID/URL | verdict verified by `verify-triage.sh` → `READY` → stage 2 (auto-chain, unless user said "triage only") · `BLOCKED`/`NEEDS_INFO` → repro (if UI blockers) → dossier (render-only, auto) → render + shape rails → package → comment+attachments gate → attach then comment → **STOP** |
| 2 | Code discovery | recon-discovery | `triage/triage.yaml` with `disposition: READY` | contract → routing stage → brief → gate → **STOP** (handoff quoted verbatim from `route/routing.yaml`, never executed) |
| RT | Routing | `scripts/route-generic.sh` (governance `none`) **or** the adapter skill `recon-<governance>` (e.g. recon-decree) | invoked by stage 2 after the contract; governance resolved by `scripts/detect-governance.sh` | `route/routing.yaml` (route, rule trace, `brief_kind`, `handoff:` as data) |
| R | Live repro | recon-repro | invoked by stage 1 or 2 per trigger table | `repro.md` + screenshots, or an honest failure finding |
| D | Dossier | recon-report | on demand after any STOP (current run exists), or auto-invoked render-only by stage 1's `BLOCKED`/`NEEDS_INFO` posting path | on-demand: `report/dossier.html` + one private artifact URL · render-only: `report/dossier.html` only (no artifact URL) |

**STOP is a real state.** The pipeline never implements, branches, or edits repo code. After stage 2 approval, implementation belongs to a NEW session entered via the printed handoff (`/decree:ddd`). After a BLOCKED stop, re-entry is a fresh `recon-triage <TICKET>` run once answers arrive.

## Invariants (MUST hold in every run)

1. **Read-only on the repo.** Each skill writes only inside its own stage directory of `~/.claude/recon/<TICKET>/` (`triage/`, `discovery/`, `route/` — owned by the routing producer, `repro/`, `report/`); root `meta.yaml` + `index.md` belong to the step-0 script. A stage directory existing means that stage ran.
2. **Step 0 exactly once per run**, via `scripts/fresh-workspace.sh` — never inline, never re-invoked mid-run (script prints `SKIPPED` on re-invocation; that means *continue*). `RECON_STEP0_FORCE=1` only for a genuinely new run inside the 30-min guard window.
3. **`runs/` is unreadable.** Archived prior runs are never opened, listed, or cited. Inputs are the live Jira API, git, `gh`, and resources fetched this run.
4. **Marker comments are output, not evidence.** Jira comments containing `recon-triage` are pipeline-authored: excluded from every check; used only for edit-vs-create and human-reply detection. Every comment the pipeline posts ends with `~recon-triage v<plugin_version>~`.
5. **Every claim carries evidence** — `file:line`, command output, HTTP status, or exact quote. In `triage.yaml`, evidence entries are TYPED (`kind: quote | http | git | file | note`), and every `kind: quote` must appear verbatim in the human content of `ticket.json` — checked by `recon/scripts/verify-triage.sh`. A checklist answer without evidence is not done.
6. **No mutating Jira call (comment create/edit, attachment delete/upload) without explicit human approval in-session.** Drafts are saved to `comment.txt` and attachments staged before the gate; one "post" answer authorizes the comment AND the attachments; at most one marker comment per ticket, edited on re-runs.
7. **Routing is a stage with exactly two producers** — `route-generic.sh` (rail) or the governance adapter skill — writing `route/routing.yaml` with `matched_rule` + `rules_not_matched` + evidence. Never by feel; discovery consumes it and quotes `handoff:` VERBATIM (the handoff is data, authored once).
8. **Human-facing questions are concrete**: numbered steps from a stated start state, real entity names, options as user-observable outcomes. Internal identifiers are banned from question text.
9. **Repro is never fabricated.** Every step performed and every screenshot captured this run; a failed repro is reported as a finding.
10. **No undeclared artifacts.** Every file a run writes appears in the artifact registry — `recon/docs/registry.yaml`, the single source that `recon/scripts/lint-workspace.sh <TICKET>` executes (every stage runs it in its Report step; exit 1 on violations). The table below is a checked mirror of that file, kept honest by `tools/check-coherence.sh`.
11. **Determinism definition:** given the same ticket state, a run produces the same verdict regardless of what earlier runs left behind.
12. **Governance is opt-in and fenced.** `detect-governance.sh` resolves the ladder (env > `~/.config/recon/config` > probe); detection alone never opts a developer in — a detected-but-unchosen tool yields `undecided` and exactly one persisted question. When governance resolves to `none`, governance-system vocabulary (decree/SPEC/PRD/ADR) is banned from every artifact — `lint-workspace.sh` greps for it. All adapter vocabulary lives in the adapter skill (`recon-<governance>`), which a `none` run never loads.
13. **Comment shape is mechanical — and so is the comment.** A posting-path comment is exactly n+4 non-empty lines — header, n one-line blockers `*i. Title* — [~accountid]: ask?` numbered 1..n, attachment-links line, reply line, marker line LAST — with n ≥ 1, EMITTED from `triage.yaml` + `meta.yaml` by `recon/scripts/render-comment.sh` (the model never writes `comment.txt`; edits happen in `triage.yaml` and re-render) and independently verified by `recon/scripts/verify-comment-shape.sh` before the gate. All detail lives in the dossier question packs (`blockers[].detail`), never the comment.
14. **Attachments replace, never accumulate.** Files named `recon-*-<TICKET>.*` are recon-owned; `recon/scripts/attach-artifacts.sh` deletes stale ones then uploads, always BEFORE the comment posts (Jira binds duplicate-filename `[^…]` links to the OLDER attachment). Same approval gate as invariant 6.
15. **The disposition is derived.** `verify-triage.sh` re-computes the verdict from the six checks (any of checks 2–5 failing → `BLOCKED`; else check 1 `partial`/`false` → `NEEDS_INFO`; else `READY`; BLOCKED/NEEDS_INFO require blockers ≥ 1, READY requires 0) and fails on mismatch. The model fills the checks and blockers with evidence; it never reconciles the verdict by hand.

## Artifact registry

All under `~/.claude/recon/<TICKET>/`. Producer → consumers. **The authoritative registry is `recon/docs/registry.yaml`** — `lint-workspace.sh` matches against its patterns; this table (like `workspace-index.md` and `docs/flow.html`) is a mirror that `tools/check-coherence.sh` verifies token-by-token. Add an artifact in the yaml first; the checker then names every mirror still missing it.

| File | Producer | Consumers | Notes |
|---|---|---|---|
| `meta.yaml` | step 0 script | discovery (current-run check), humans | plugin_version + start time; stamps the run |
| `index.md` | step 0 script (copied from `docs/workspace-index.md`) | anyone opening the workspace | static per-file documentation; identical across tickets |
| `runs/<ts>/…` | step 0 script | **nobody** (invariant 3) | archived prior runs, dotfiles included |
| `triage/ticket.json` | triage | triage checks | Jira issue, API v2 plain-text |
| `triage/aux-<slug>.json` | triage | triage checks | auxiliary GETs (linked tickets, Confluence) |
| `triage/triage.yaml` | triage | discovery precondition, `verify-triage.sh`, `render-comment.sh`, humans | schema in recon-triage SKILL.md; disposition derived + quotes verified by `verify-triage.sh` (invariant 15) |
| `triage/jira/{comment.txt, post-result.json, attach-result.json}` | `render-comment.sh` (comment.txt) + triage (on posting path) | audit | comment.txt RENDERED from triage.yaml + meta.yaml, never hand-written, saved BEFORE gate; responses after POST; `attach-result.json` is written by `attach-artifacts.sh` and cleared at the start of each attach run |
| `triage/jira/bundle-manifest.txt` | `package-artifacts.sh` | gate display, audit | size + rel path per bundled file; the zip itself is staged in a temp dir (its contents ARE the workspace) |
| `discovery/discovery.md` | discovery | gate, implementer verification | Gherkin: required + regression + OPEN scenarios |
| `route/routing.yaml` | route-generic.sh or the governance adapter | discovery (route/brief_kind/handoff), recon-report | route + rule trace + governance/source + `brief_kind` + `handoff:` (data, quoted verbatim) + `evidence.repo_commit` |
| `route/aux-intent-check.txt` | governance adapter only | audit, recon-report | raw adapter-check output backing the evidence lines |
| `discovery/gate.yaml` | discovery | recon-report decision cards, humans | approved/date/open_scenario_resolutions/rejected — extracted from routing (the gate is discovery's act) |
| `discovery/spec-draft.md` | discovery | implementer session | the brief named by `routing.brief_kind`; ACs 1:1 from Gherkin + Manual verification (or a problem statement) — governance-neutral |
| `repro/repro.md` + `repro/exhibits/<n>-<slug>.png` | repro | gate questions, spec-draft Manual verification, PR "before" evidence, recon-report exhibits | numbered, human-re-runnable |
| `report/dossier.html` | recon-report | humans (published as a private artifact on-demand; attached to the Jira ticket by triage on the posting path) | a VIEW over the rows above — no new facts, fixed template |

## Trigger table (mechanical — no judgment)

| Event | Condition | Action |
|---|---|---|
| Auto-chain to discovery | `disposition: READY` and user did not say "triage only" | invoke recon-discovery in the same run |
| Blocker repro | stage 1, any blocker concerns observable UI behavior | invoke recon-repro BEFORE drafting; reference exhibits in the blocker's `detail` pack |
| Primary-scenario repro | `task_class: defect` AND affected surface is visible UI AND `routing.route` ∉ {`direct`, `no-doc`} | invoke recon-repro for the bug itself BEFORE the gate |
| OPEN-scenario repro | any OPEN scenario concerns observable UI behavior | invoke recon-repro; reference steps + screenshots in the gate question |
| Repro session reuse | primary + OPEN scenarios share a start state | one dev-server session covers both |
| Comment edit-vs-create | any fetched comment contains `recon-triage` | EDIT the most recent one; never create a second |
| Answered-blocker detection | human comment posted after a marker comment | counts as replying to its questions |
| Step-0 re-invocation | `meta.yaml` younger than 30 min | script prints `SKIPPED`; continue the current run |
| Governance resolution | `detect-governance.sh` ladder: env > config > probe-absent→none > probe-present-no-choice→undecided | undecided → ONE AskUserQuestion, answer persisted via `set-governance.sh`, re-resolve |
| Routing dispatch | `governance: none` → `route-generic.sh <TICKET> <source>`; else → invoke skill `recon-<governance>` | either producer writes `route/routing.yaml` |
| Vocabulary fence | `route/routing.yaml` has `governance: none` | lint greps all artifacts for governance vocabulary; any hit = violation |
| Dossier | auto render-only on the `BLOCKED`/`NEEDS_INFO` posting path; on demand otherwise (user asks, or a stage's report mentions it) | recon-report renders the fixed template from current-run artifacts; publishes private (on-demand only — render-only stops after write + lint) |
| Blocked delivery | disposition ∈ {`BLOCKED`, `NEEDS_INFO`} (requires n ≥ 1 structured blockers) | recon-report render-only → `package-artifacts.sh` → gate → `attach-artifacts.sh` → comment (attach strictly first) |
| Verdict verification | `triage/triage.yaml` written or edited | `verify-triage.sh` until `verify: clean` before branching on disposition |
| Comment render + shape gate | posting path, `triage.yaml` blockers written or edited | `render-comment.sh` emits `comment.txt`, then `verify-comment-shape.sh` until `shape: clean` before the approval gate — `comment.txt` is never hand-edited |

## Rails vs judgment

| Rails (zero model freedom) | Judgment (model decides, evidence required) |
|---|---|
| step-0 script, archive layout, meta stamp | the six check verdicts |
| comment partition by marker substring | root-cause identification (`file:line`) |
| routing policy table, first match wins | Gherkin scenarios + OPEN option design |
| repro trigger conditions | what the minimal repro state sequence is |
| artifact names and schemas | drafted question wording (within rule 8) |
| gates: who may approve, what gets recorded | disposition rationale in evidence lines |
| comment shape: n+4 lines (`verify-comment-shape.sh`) | blocker ask/detail wording (within triage rule 7 / invariant 8) |
| disposition derivation + typed-evidence/quote verification (`verify-triage.sh`) | |
| comment rendering from triage.yaml (`render-comment.sh`) | |
| attachment replace + ordering (`attach-artifacts.sh`) | |
| bundle packaging + manifest (`package-artifacts.sh`) | |

## Consuming the artifacts (implementer sessions)

1. Read `discovery/spec-draft.md` — it is self-sufficient: acceptance criteria, technical design (names the contract to reuse), integration guardrails, and **Manual verification** (start state + numbered steps to reach the surface; BEFORE/AFTER outcomes).
2. Verify your work against the scenarios in `discovery/discovery.md`, including the regression ("must-not-change") ones.
3. `repro/exhibits/*.png` are your PR's "before" screenshots; capture "after" equivalents at the same states.
4. Do not read `runs/` (invariant 3 binds you too). Do not treat `triage.yaml` evidence as current after your changes land.

## Change protocol (editor sessions)

1. Edit either clone — `~/Desktop/ADCREATIVE/recon-plugin` or `~/.claude/plugins/marketplaces/recon-plugin` — then keep BOTH synced with `origin/master`.
2. Bump `recon/.claude-plugin/plugin.json` version on every change. Commit conventionally; push.
3. Activate without the interactive `/plugin install`: copy `recon/` to `~/.claude/plugins/cache/recon-plugin/recon/<version>/` and repoint the `recon@recon-plugin` entry (installPath, version, gitCommitSha) in `~/.claude/plugins/installed_plugins.json`. Do not delete the previously pinned cache dir (a live session may hold script paths into it).
4. Mechanical checks in skills must be `find`-based — `ls`/`grep` may be aliased or function-wrapped in a user's shell with non-POSIX exit codes.
5. Any new behavior must land as a rail (script/table/schema) or as judgment-with-evidence; update this doc's tables in the same commit.
6. Governance adapters follow the convention: skill `recon-<governance>`, same contract as recon-decree (reads `discovery/`, writes `route/routing.yaml` incl. `handoff:` data, vocabulary quarantined in its own SKILL.md).
7. Docs must not outlive the files they name: `tools/check-links.sh` (pre-commit hook — enable per clone with `git config core.hooksPath .githooks`) resolves every backticked script name, `../`-relative path, and `blob/master` link against the working tree, then runs lychee over the real links. Renaming a script without updating its references fails the commit.
8. Docs must not contradict the data they mirror: `tools/check-coherence.sh` (same pre-commit hook) verifies the facts that exist in more than one place. Every shared fact has exactly ONE owner file; every other appearance is a mirror the checker validates — never a place you author the fact. The ownership table:

   | Fact class | Owner (author here) | Mirrors (checked, never authored) |
   |---|---|---|
   | Artifact registry | `recon/docs/registry.yaml` | `lint-workspace.sh` executes it; registry table above, `workspace-index.md`, `docs/flow.html` checked by token |
   | Current version | `recon/.claude-plugin/plugin.json` | every line marked `coherence:version` (e.g. `docs/flow.html` chip + footer) |
   | Invariants + numbering | this file's Invariants section | every "invariant N" citation repo-wide must cite an existing number |
   | File roles | each directory's `CLAUDE.md` (`recon/scripts/`, `recon/docs/`, `recon/skills/`, `tools/`, `docs/`) | every file in those directories must have a role entry — files must not outrun their role docs |
   | `triage.yaml` schema | recon-triage SKILL.md step 3 schema block | `recon/scripts/triage-tools.py` parses the same shape; keep them in one commit (fixture test tracked in `docs/improvements/golden-fixtures/`) |

   The published flow artifact is the one mirror a git hook cannot reach — after changing `docs/flow.html`, republish it (the file's header comment carries the artifact URL).
