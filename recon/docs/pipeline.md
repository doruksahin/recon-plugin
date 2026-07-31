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
| 1 | Blocker triage | recon-triage | ticket ID/URL | `READY` → stage 2 (auto-chain, unless user said "triage only") · `BLOCKED`/`NEEDS_INFO` → comment gate → **STOP** |
| 2 | Code discovery | recon-discovery | `triage.yaml` with `disposition: READY` | routed + gated → **STOP** (handoff printed, never executed) |
| R | Live repro | recon-repro | invoked by stage 1 or 2 per trigger table | `repro.md` + screenshots, or an honest failure finding |
| D | Dossier | recon-report | on demand only, after any STOP (current run exists) | `report/dossier.html` + one private artifact URL |

**STOP is a real state.** The pipeline never implements, branches, or edits repo code. After stage 2 approval, implementation belongs to a NEW session entered via the printed handoff (`/decree:ddd`). After a BLOCKED stop, re-entry is a fresh `recon-triage <TICKET>` run once answers arrive.

## Invariants (MUST hold in every run)

1. **Read-only on the repo.** Each skill writes only inside its own stage directory of `~/.claude/recon/<TICKET>/` (`triage/`, `discovery/`, `repro/`, `report/`); root `meta.yaml` + `index.md` belong to the step-0 script. A stage directory existing means that stage ran.
2. **Step 0 exactly once per run**, via `scripts/fresh-workspace.sh` — never inline, never re-invoked mid-run (script prints `SKIPPED` on re-invocation; that means *continue*). `RECON_STEP0_FORCE=1` only for a genuinely new run inside the 30-min guard window.
3. **`runs/` is unreadable.** Archived prior runs are never opened, listed, or cited. Inputs are the live Jira API, git, `gh`, and resources fetched this run.
4. **Marker comments are output, not evidence.** Jira comments containing `recon-triage` are pipeline-authored: excluded from every check; used only for edit-vs-create and human-reply detection. Every comment the pipeline posts ends with `~recon-triage v<plugin_version>~`.
5. **Every claim carries evidence** — `file:line`, command output, HTTP status, or exact quote. A checklist answer without one is not done.
6. **No Jira POST without explicit human approval in-session.** Drafts are saved to `comment.txt` before the gate; at most one marker comment per ticket, edited on re-runs.
7. **Routing comes from the policy table** (`routing.yaml` with `matched_rule` + `rules_not_matched` + evidence). Never by feel.
8. **Human-facing questions are concrete**: numbered steps from a stated start state, real entity names, options as user-observable outcomes. Internal identifiers are banned from question text.
9. **Repro is never fabricated.** Every step performed and every screenshot captured this run; a failed repro is reported as a finding.
10. **No undeclared artifacts.** Every file a run writes appears in the artifact registry below — checked mechanically by `recon/scripts/lint-workspace.sh <TICKET>`, which every stage runs in its Report step (exit 1 on violations).
11. **Determinism definition:** given the same ticket state, a run produces the same verdict regardless of what earlier runs left behind.

## Artifact registry

All under `~/.claude/recon/<TICKET>/`. Producer → consumers.

| File | Producer | Consumers | Notes |
|---|---|---|---|
| `meta.yaml` | step 0 script | discovery (current-run check), humans | plugin_version + start time; stamps the run |
| `index.md` | step 0 script (copied from `docs/workspace-index.md`) | anyone opening the workspace | static per-file documentation; identical across tickets |
| `runs/<ts>/…` | step 0 script | **nobody** (invariant 3) | archived prior runs, dotfiles included |
| `triage/ticket.json` | triage | triage checks | Jira issue, API v2 plain-text |
| `triage/aux-<slug>.json` | triage | triage checks | auxiliary GETs (linked tickets, Confluence) |
| `triage/triage.yaml` | triage | discovery precondition, humans | schema in recon-triage SKILL.md |
| `triage/jira/{comment.txt, post-result.json, attach-result.json}` | triage (on posting path) | audit | draft saved BEFORE gate; responses after POST |
| `discovery/discovery.md` | discovery | gate, implementer verification | Gherkin: required + regression + OPEN scenarios |
| `discovery/routing.yaml` | discovery | handoff, `/decree:ddd`, recon-report | route + matched_rule + rules_not_matched + `gate:` block + `evidence.repo_commit` (pins every `file:line` claim) |
| `discovery/spec-draft.md` | discovery | implementer session | ACs 1:1 from Gherkin + Manual verification section |
| `repro/repro.md` + `repro/exhibits/<n>-<slug>.png` | repro | gate questions, spec-draft Manual verification, PR "before" evidence, recon-report exhibits | numbered, human-re-runnable |
| `report/dossier.html` | recon-report | humans (published as a private artifact) | a VIEW over the rows above — no new facts, fixed template |

## Trigger table (mechanical — no judgment)

| Event | Condition | Action |
|---|---|---|
| Auto-chain to discovery | `disposition: READY` and user did not say "triage only" | invoke recon-discovery in the same run |
| Primary-scenario repro | `task_class: defect` AND affected surface is visible UI AND `routing.route ≠ no-doc` | invoke recon-repro for the bug itself BEFORE the gate |
| OPEN-scenario repro | any OPEN scenario concerns observable UI behavior | invoke recon-repro; reference steps + screenshots in the gate question |
| Repro session reuse | primary + OPEN scenarios share a start state | one dev-server session covers both |
| Comment edit-vs-create | any fetched comment contains `recon-triage` | EDIT the most recent one; never create a second |
| Answered-blocker detection | human comment posted after a marker comment | counts as replying to its questions |
| Step-0 re-invocation | `meta.yaml` younger than 30 min | script prints `SKIPPED`; continue the current run |
| Dossier | never automatic — user asks, or a stage's report mentions it | recon-report renders the fixed template from current-run artifacts; publishes private |

## Rails vs judgment

| Rails (zero model freedom) | Judgment (model decides, evidence required) |
|---|---|
| step-0 script, archive layout, meta stamp | the six check verdicts |
| comment partition by marker substring | root-cause identification (`file:line`) |
| routing policy table, first match wins | Gherkin scenarios + OPEN option design |
| repro trigger conditions | what the minimal repro state sequence is |
| artifact names and schemas | drafted question wording (within rule 8) |
| gates: who may approve, what gets recorded | disposition rationale in evidence lines |

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
