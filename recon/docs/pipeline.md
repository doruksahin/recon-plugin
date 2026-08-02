# Recon Pipeline — Machine Spec

Audience: LLM sessions. Three reader roles:
- **Pipeline session** — executing a recon skill. Your skill's SKILL.md is authoritative; this doc gives you the whole-chain view. On conflict, SKILL.md wins.
- **Implementer session** — implementing an approved ticket. Read [Consuming the artifacts](#consuming-the-artifacts-implementer-sessions).
- **Editor session** — modifying this plugin. Read [Change protocol](#change-protocol-editor-sessions).

Design formula (all changes must preserve it): **judgment stays in the model but must leave mechanical evidence; execution moves onto rails** (scripts, schemas, condition-table triggers, markers). A step where the model has freedom in *execution* is a defect.

## Runtime and host contract

`recon/scripts/reconctl.sh` owns workspace, local host/surface detection,
preflight, capability levels, and human-facing invocation rendering.
`RECON_ROOT` is the absolute workspace root; its backward-compatible default
is `~/.claude/recon`. `RECON_HOST` and `RECON_SURFACE` are explicit overrides;
otherwise the rail detects Claude Code or local Codex and fails closed as
`unknown`. Skills read `recon/docs/hosts.md` and run `reconctl.sh start
base|triage` for one pure-output runtime, capability, and preflight snapshot
before mutation. Later rails re-detect current identity for provenance. Host
mechanics may change; gates, schemas, evidence, and routing semantics may not.
Hosted runtimes are outside the executable `0.15.0` contract.

## State machine

| # | Stage | Skill | Entry condition | Exit states |
|---|---|---|---|---|
| 0 | Fresh workspace | recon-triage step 0 | always (script-guarded: once per run) | workspace = `meta.yaml` (+ `runs/`) only |
| 1 | Blocker triage | recon-triage | ticket ID/URL | verdict verified by `verify-triage.sh` → `READY` → stage 2 (auto-chain, unless user said "triage only") · `BLOCKED`/`NEEDS_INFO` → repro (if UI blockers) → dossier (render-only, auto) → render + shape rails → package → comment+attachments gate → attach then comment → **STOP** |
| 2 | Code discovery | recon-discovery | `triage/triage.yaml` with `disposition: READY` | ID-bearing contract → routing → required repro + verification → brief → pre-gate verification → gate → post-gate verification → **STOP** (handoff quoted verbatim from `route/routing.yaml`, never executed) |
| RT | Routing | `scripts/route-generic.sh` (governance `none`) **or** the adapter skill `recon-<governance>` (e.g. recon-decree) | invoked by stage 2 after the contract; governance resolved by `scripts/detect-governance.sh` | `route/routing.yaml` (route, rule trace, `brief_kind`, `handoff:` as data) |
| R | Live repro | recon-repro | invoked by stage 1 or 2 per trigger table | `repro.md` + screenshots, or an honest failure finding; both must pass `verify-repro.sh` |
| D | Dossier | recon-report | on demand after any STOP (current run exists), or auto-invoked render-only by stage 1's `BLOCKED`/`NEEDS_INFO` posting path | always `report/dossier.html`; private artifact URL only when `publish_once` is available |
| S | State canvas | recon-state | on demand, and local refresh at a STOP/gate | always `state/state.yaml` + `state/canvas.html`; `state/artifact-url` only when `publish_stable_url` is available |

**Legend:** numbered stages run in sequence; lettered stages fire on trigger-table conditions, not in order — **R** repro (invocable from stage 1 or 2), **RT** routing (inside stage 2, two possible producers), **D** dossier (after any STOP, or auto on the posting path), **S** state canvas (the living view; refreshes wherever the run stops).

**STOP is a real state.** The pipeline never implements, branches, or edits repo code. After stage 2 approval, implementation belongs to a NEW session entered through the printed, host-neutral handoff. After a BLOCKED stop, re-entry is a fresh Recon Triage run once answers arrive; the display command comes from `reconctl.sh invocation`.

## Invariants (MUST hold in every run)

1. **Read-only on the repo.** Each skill writes only inside its own stage directory of `$RECON_ROOT/<TICKET>/` (`triage/`, `discovery/`, `route/` — owned by the routing producer, `repro/`, `report/`); root `meta.yaml` + `index.md` belong to the step-0 script. A stage directory existing means that stage ran.
2. **Step 0 exactly once per run**, via `scripts/fresh-workspace.sh` — never inline, never re-invoked mid-run (script prints `SKIPPED` on re-invocation; that means *continue*). `RECON_STEP0_FORCE=1` only for a genuinely new run inside the 30-min guard window.
3. **`runs/` is unreadable.** Archived prior runs are never opened, listed, or cited. Inputs are the live Jira API, git, `gh`, and resources fetched this run.
4. **Marker comments are output, not evidence.** Jira comments containing `recon-triage` are pipeline-authored: excluded from every check; used only for edit-vs-create and human-reply detection. Every comment the pipeline posts ends with `~recon-triage v<plugin_version>~`.
5. **Every claim carries evidence** — `file:line`, command output, HTTP status, or exact quote. In `triage.yaml`, evidence entries are TYPED (`kind: quote | http | git | file | note`), and every `kind: quote` must appear verbatim in the human content of `ticket.json` — checked by `recon/scripts/verify-triage.sh`. A checklist answer without evidence is not done.
6. **No mutating Jira call (comment create/edit, attachment delete/upload) without explicit human approval in-session.** Drafts are saved to `comment.txt` and attachments staged before the gate; one "post" answer authorizes the comment AND the attachments; at most one marker comment per ticket, edited on re-runs.
7. **Routing is a stage with exactly two producers** — `route-generic.sh` (rail) or the governance adapter skill — writing `route/routing.yaml` with non-empty `matched_rule`, `governance`, `governance_source`, `rules_not_matched`, a full lowercase 40- or 64-character Git object ID in `evidence.repo_commit`, and a block-scalar `handoff:`. The Discovery verifier rejects missing, placeholder, malformed, duplicate, or unknown envelope fields without second-guessing the producer's semantic rule choice. Never route by feel; discovery consumes the record and quotes `handoff:` VERBATIM (the handoff is data, authored once).
8. **Human-facing questions are concrete**: numbered steps from a stated start state, real entity names, options as user-observable outcomes. Internal identifiers are banned from question text.
9. **Repro is never fabricated.** Every step performed and every screenshot captured this run; a failed repro is reported as a finding. `verify-repro.sh` proves package structure and coarse provenance, while the skill reads each screenshot to judge visual truth.
10. **No undeclared artifacts.** Every file a run writes appears in the artifact registry — `recon/docs/registry.yaml`, the single source that `recon/scripts/lint-workspace.sh <TICKET>` executes (every stage runs it in its Report step; exit 1 on violations). The table below is a checked mirror of that file, kept honest by `tools/check-coherence.sh`.
11. **Determinism definition:** given the same ticket state, a run produces the same verdict regardless of what earlier runs left behind.
12. **Governance is opt-in and fenced.** `detect-governance.sh` resolves the ladder (env > `~/.config/recon/config` > probe); detection alone never opts a developer in — a detected-but-unchosen tool yields `undecided` and exactly one persisted question. When governance resolves to `none`, governance-system vocabulary (decree/SPEC/PRD/ADR) is banned from every artifact — `lint-workspace.sh` greps for it. All adapter vocabulary lives in the adapter skill (`recon-<governance>`), which a `none` run never loads.
13. **Comment shape is mechanical — and so is the comment.** A posting-path comment is exactly n+4 non-empty lines — header, n one-line blockers `*i. Title* — [~accountid]: ask?` numbered 1..n, attachment-links line, reply line, marker line LAST — with n ≥ 1, EMITTED from `triage.yaml` + `meta.yaml` by `recon/scripts/render-comment.sh` (the model never writes `comment.txt`; edits happen in `triage.yaml` and re-render) and independently verified by `recon/scripts/verify-comment-shape.sh` before the gate. All detail lives in the dossier question packs (`blockers[].detail`), never the comment.
14. **Attachments replace, never accumulate.** Files named `recon-*-<TICKET>.*` are recon-owned; `recon/scripts/attach-artifacts.sh` deletes stale ones then uploads, always BEFORE the comment posts (Jira binds duplicate-filename `[^…]` links to the OLDER attachment). Same approval gate as invariant 6.
15. **The disposition is derived.** `verify-triage.sh` re-computes the verdict from the six checks (any of checks 2–5 failing → `BLOCKED`; else check 1 `partial`/`false` → `NEEDS_INFO`; else `READY`; BLOCKED/NEEDS_INFO require blockers ≥ 1, READY requires 0) and fails on mismatch. The model fills the checks and blockers with evidence; it never reconciles the verdict by hand.
16. **The ticket ledger is output, never evidence.** `history.ndjson` (workspace root) is the append-only cross-run event log: written ONLY by `log-event.sh` (closed vocabulary — `--vocab` prints it), preserved across runs by `fresh-workspace.sh`, validated by `lint-workspace.sh`. Every event carries the current normalized host and surface. No check, verdict, or routing decision may read it — determinism (invariant 11) binds exactly as if it did not exist. Views (state canvas, humans) may render it as a timeline.
17. **Generated handoff evidence is verified before consumption.** A repro package must pass `verify-repro.sh` before triage, discovery, or report consumes it. A routed Discovery package must pass `verify-discovery.sh` before the human gate and again after the gate before report or handoff consumes it. Inputs must be regular, non-symlinked paths that resolve inside the current workspace. The routing record must retain invariant 7's complete producer/trace/commit envelope. Stable `REQ-N` / `REG-N` / `OPEN-N` IDs are exact visible joins across the contract and either acceptance checkboxes or problem-statement entries; HTML comments, fenced examples, and indented code cannot satisfy a structural heading or join. On approval, the complete OPEN resolution is copied verbatim into its visible same-ID entry. Repro exhibit references likewise count only when visible on their numbered step, never when hidden in an HTML comment.

## Artifact registry

All under `$RECON_ROOT/<TICKET>/`. Producer → consumers. **The authoritative registry is `recon/docs/registry.yaml`** — `lint-workspace.sh` matches against its patterns; this table (like `workspace-index.md` and `docs/flow.html`) is a mirror that `tools/check-coherence.sh` verifies token-by-token. Add an artifact in the yaml first; the checker then names every mirror still missing it.

| File | Producer | Consumers | Notes |
|---|---|---|---|
| `meta.yaml` | step 0 script | discovery (current-run check), humans | plugin version, start time, starting host/surface; stamps the run |
| `index.md` | step 0 script (copied from `docs/workspace-index.md`) | anyone opening the workspace | static per-file documentation; identical across tickets |
| `runs/<ts>/…` | step 0 script | **nobody** (invariant 3) | archived prior runs, dotfiles included |
| `history.ndjson` | `log-event.sh` (called by rails + skill report steps) | state canvas timeline, humans — **never evidence** (invariant 16) | append-only cross-run ledger with current host/surface per event; survives step 0 |
| `triage/ticket.json` | triage | triage checks | Jira issue, API v2 plain-text |
| `triage/aux-<slug>.json` | triage | triage checks | auxiliary GETs (linked tickets, Confluence) |
| `triage/triage.yaml` | triage | discovery precondition, `verify-triage.sh`, `render-comment.sh`, humans | schema in recon-triage SKILL.md; disposition derived + quotes verified by `verify-triage.sh` (invariant 15) |
| `triage/jira/{comment.txt, post-result.json, attach-result.json}` | `render-comment.sh` (comment.txt) + triage (on posting path) | audit | comment.txt RENDERED from triage.yaml + meta.yaml, never hand-written, saved BEFORE gate; responses after POST; `attach-result.json` is written by `attach-artifacts.sh` and cleared at the start of each attach run |
| `triage/jira/bundle-manifest.txt` | `package-artifacts.sh` | gate display, audit | size + rel path per bundled file; the zip itself is staged in a temp dir (its contents ARE the workspace) |
| `discovery/discovery.md` | discovery | gate, implementer verification | rendered Gherkin under visible stable `REQ-N`, `REG-N`, and `OPEN-N` H2 headings; or a visible evidenced no-scenarios declaration |
| `route/routing.yaml` | route-generic.sh or the governance adapter | discovery (route/brief_kind/handoff), recon-report | route + rule trace + governance/source + `brief_kind` + `handoff:` (data, quoted verbatim) + full SHA-1/SHA-256 `evidence.repo_commit` |
| `route/aux-intent-check.txt` | governance adapter only | audit, recon-report | raw adapter-check output backing the evidence lines |
| `discovery/gate.yaml` | discovery | recon-report decision cards, humans | approved/date plus exact `OPEN-N` resolution keys or a rejection reason — the gate is discovery's act |
| `discovery/spec-draft.md` | discovery | implementer session | absent for `brief_kind: none`; otherwise the named brief with exact visible scenario-ID parity + Manual verification, or the fixed-section problem statement; approved OPEN resolution text is bound to its visible same-ID entry — governance-neutral |
| `repro/repro.md` + `repro/exhibits/<n>-<slug>.png` | repro | gate questions, spec-draft Manual verification, PR "before" evidence, recon-report exhibits | fixed frontmatter (`ticket`, `reproduced`, `start_state`, `failure_reason`); successful steps and visibly referenced exhibits are numbered 1:1; inputs are regular in-workspace paths and PNGs pass chunk bounds/order, CRC, IDAT zlib EOF, and terminal-IEND checks; honest failures contain no invented success evidence |
| `report/dossier.html` | recon-report | humans (published as a private artifact on-demand; attached to the Jira ticket by triage on the posting path) | a VIEW over the rows above — no new facts, fixed template |
| `state/state.yaml` | `derive-state.sh` | `render-state-canvas.sh`, humans | flat derived state: stop label, node statuses, fact counts, canonical `next_action`, neutral next prose |
| `state/canvas.html` | `render-state-canvas.sh` | recon-state display/publish step, humans | the living node canvas; always available locally |
| `state/artifact-url` | recon-state, only with `publish_stable_url` | recon-state republish | one line: the ticket's stable artifact URL; never created by render-only hosts |

## Trigger table (mechanical — no judgment)

| Event | Condition | Action |
|---|---|---|
| Runtime resolution | before a skill's first path or host-tool action | `reconctl.sh start base|triage` prints one root/host/surface/capability/preflight snapshot; failure stops before mutation and no context file is written |
| Auto-chain to discovery | `disposition: READY` and user did not say "triage only" | invoke recon-discovery in the same run |
| Blocker repro | stage 1, any blocker concerns observable UI behavior | invoke recon-repro and require `verify-repro.sh` clean BEFORE drafting; reference exhibits in the blocker's `detail` pack |
| Primary-scenario repro | `task_class: defect` AND affected surface is visible UI AND `routing.route` ∉ {`direct`, `no-doc`} | invoke recon-repro for the bug itself, verify it, then draft the brief |
| OPEN-scenario repro | any OPEN scenario concerns observable UI behavior | invoke recon-repro, verify it, then reference steps + screenshots in the gate question |
| Repro session reuse | primary + OPEN scenarios share a start state | one dev-server session covers both |
| Repro verification | `repro/repro.md` written or consumed | `verify-repro.sh` until `verify: clean`; then the skill still reads every screenshot for visual meaning |
| Comment edit-vs-create | any fetched comment contains `recon-triage` | EDIT the most recent one; never create a second |
| Answered-blocker detection | human comment posted after a marker comment | counts as replying to its questions |
| Step-0 re-invocation | `meta.yaml` younger than 30 min | script prints `SKIPPED`; continue the current run |
| Governance resolution | `detect-governance.sh` ladder: env > config > probe-absent→none > probe-present-no-choice→undecided | undecided → ONE host-native user interaction (see `hosts.md`), answer persisted via `set-governance.sh`, re-resolve |
| Routing dispatch | `governance: none` → `route-generic.sh <TICKET> <source>`; else → invoke skill `recon-<governance>` | either producer writes `route/routing.yaml` |
| Discovery pre-gate verification | route + contract + route-required brief/repro are ready | `verify-discovery.sh <TICKET> pre-gate` until clean before asking approval |
| Discovery post-gate verification | `discovery/gate.yaml` written or edited | bind every approved OPEN resolution verbatim to its same-ID brief entry, then run `verify-discovery.sh <TICKET> post-gate` until clean before rejection stop, report, or handoff |
| Vocabulary fence | `route/routing.yaml` has `governance: none` | lint greps all artifacts for governance vocabulary; any hit = violation |
| Dossier | auto render-only on the `BLOCKED`/`NEEDS_INFO` posting path; on demand otherwise | recon-report always renders; publishes only when `publish_once` is available |
| Blocked delivery | disposition ∈ {`BLOCKED`, `NEEDS_INFO`} (requires n ≥ 1 structured blockers) | recon-report render-only → `package-artifacts.sh` → gate → `attach-artifacts.sh` → comment (attach strictly first) |
| Verdict verification | `triage/triage.yaml` written or edited | `verify-triage.sh` until `verify: clean` before branching on disposition |
| State canvas refresh | a stage reaches STOP or presents a gate | derive → render; republish only when `publish_stable_url` is available and `state/artifact-url` exists |
| State canvas first publish | recon-state invoked, `publish_stable_url` available, and `state/artifact-url` absent | ONE host-native interaction; on Publish, save the URL and log `canvas_published`; incapable hosts remain render-only |
| Ledger events | the step happens (closed list) | `log-event.sh <TICKET> <event>`: step 0 → `run_started` (by the script itself) · verify clean → `verdict` · routing producer → `routed` (route-generic.sh logs itself; the adapter skill calls it) · attach rail → `attachments_replaced` · comment POST/edit → `comment_posted` · `gate.yaml` written → `gate_answered` · handoff printed → `handoff_printed` · dossier published → `dossier_published` · canvas published → `canvas_published` |
| Comment render + shape gate | posting path, `triage.yaml` blockers written or edited | `render-comment.sh` emits `comment.txt`, then `verify-comment-shape.sh` until `shape: clean` before the approval gate — `comment.txt` is never hand-edited |

## Rails vs judgment

| Rails (zero model freedom) | Judgment (model decides, evidence required) |
|---|---|
| workspace + host/surface detection, preflight, capability levels, invocation rendering (`reconctl.sh`, `hosts.md`) | |
| step-0 script, archive layout, meta stamp | the six check verdicts |
| comment partition by marker substring | root-cause identification (`file:line`) |
| routing policy table, first match wins | Gherkin scenarios + OPEN option design |
| repro trigger conditions | what the minimal repro state sequence is |
| artifact names and schemas | drafted question wording (within rule 8) |
| gates: who may approve, what gets recorded | disposition rationale in evidence lines |
| comment shape: n+4 lines (`verify-comment-shape.sh`) | blocker ask/detail wording (within triage rule 7 / invariant 8) |
| disposition derivation + typed-evidence/quote verification (`verify-triage.sh`) | |
| repro frontmatter, visible step/exhibit, non-symlink path, PNG chunk/CRC/zlib/IEND, and mtime verification (`verify-repro.sh`) | screenshot visual meaning |
| visible scenario IDs, implementation/problem brief parity/shape, complete route producer/trace/commit envelope, block-scalar handoff, and exact same-ID gate-resolution verification (`verify-discovery.sh`) | scenario content + routing rule choice + gate recommendation |
| comment rendering from triage.yaml (`render-comment.sh`) | |
| attachment replace + ordering (`attach-artifacts.sh`) | |
| bundle packaging + manifest (`package-artifacts.sh`) | |
| ledger append + vocabulary (`log-event.sh`, invariant 16) | |
| state derivation decision table (`derive-state.sh`) | |
| canvas rendering from derived state (`render-state-canvas.sh`) | |

## Consuming the artifacts (implementer sessions)

1. Run `verify-discovery.sh <TICKET> post-gate`; if repro exists, also run `verify-repro.sh <TICKET>`. Stop on either failure rather than implementing from a drifted package.
2. Read `discovery/spec-draft.md` when the route has a brief — it is self-sufficient: acceptance criteria keyed by scenario ID, technical design (names the contract to reuse), integration guardrails, and **Manual verification** (start state + numbered steps to reach the surface; BEFORE/AFTER outcomes). A `brief_kind: none` route intentionally has no draft.
3. Verify your work against the stable IDs in `discovery/discovery.md`, including the regression (`REG-N`) scenarios and approved `OPEN-N` resolution.
4. `repro/exhibits/*.png` are your PR's "before" screenshots; capture "after" equivalents at the same states.
5. Do not read `runs/` (invariant 3 binds you too). Do not treat `triage.yaml` evidence as current after your changes land.

## Change protocol (editor sessions)

1. Edit the source repository, never an installed Claude or Codex cache. A marketplace clone is a distribution mirror, not an alternate source of truth.
2. Do not hand-edit version fields during implementation. The release rail computes and writes the next version, creates the release commit/tag, and pushes only after explicit release approval. Until that gate runs, validated work may remain on the current unreleased version.
3. Regenerate native adapters with `python3 tools/generate-adapters.py`; `python3 tools/generate-adapters.py --check` must pass. Refresh local installs only through `activate-plugin.sh` (Claude Code) and `activate-codex-plugin.sh` (Codex). Codex activation must bind clean same-origin source/configured checkouts to the exact released commit, reject ignored/untracked, sparse/assume-unchanged, or special plugin entries, attest the materialized plugin tree before and after installation, attest the actual installed version/path, then repeat the full checkout/tree attestation immediately before success. Do not delete previously pinned cache directories used by live sessions.
4. Mechanical checks in skills must be `find`-based — `ls`/`grep` may be aliased or function-wrapped in a user's shell with non-POSIX exit codes.
5. Any new behavior must land as a rail (script/table/schema) or as judgment-with-evidence; update this doc's tables in the same commit. New artifact verifiers need isolated clean and failing fixtures.
6. Governance adapters follow the convention: skill `recon-<governance>`, same contract as recon-decree (reads `discovery/`, writes `route/routing.yaml` incl. `handoff:` data, vocabulary quarantined in its own SKILL.md).
7. Docs must not outlive the files they name: `tools/check-links.sh` (pre-commit hook — enable per clone with `git config core.hooksPath .githooks`) resolves every backticked script name, `../`-relative path, and `blob/master` link against the working tree, then runs lychee over the real links. Renaming a script without updating its references fails the commit.
8. Docs must not contradict the data they mirror: `tools/check-coherence.sh` (same pre-commit hook) verifies the facts that exist in more than one place. Every shared fact has exactly ONE owner file; every other appearance is a mirror the checker validates — never a place you author the fact. The ownership table:

   | Fact class | Owner (author here) | Mirrors (checked, never authored) |
   |---|---|---|
   | Artifact registry | `recon/docs/registry.yaml` | `lint-workspace.sh` executes it; registry table above, `workspace-index.md`, `docs/flow.html` checked by token |
   | Current version | `recon/.claude-plugin/plugin.json` | `recon/.codex-plugin/plugin.json` + every line marked `coherence:version` (e.g. `docs/flow.html` chip + footer) |
   | Native adapter metadata | each skill's `SKILL.md` frontmatter + `recon/.claude-plugin/plugin.json` | `.agents/plugins/marketplace.json`, `recon/.codex-plugin/plugin.json`, and `agents/openai.yaml`, generated and checked by `tools/generate-adapters.py` |
   | Invariants + numbering | this file's Invariants section | every "invariant N" citation repo-wide must cite an existing number |
   | File roles | each directory's `CLAUDE.md` (`recon/scripts/`, `recon/docs/`, `recon/skills/`, `tools/`, `docs/`) | every file in those directories must have a role entry — files must not outrun their role docs |
   | `triage.yaml` schema | recon-triage SKILL.md step 3 schema block | `recon/scripts/triage-tools.py` parses the same shape; keep them in one commit (fixture test tracked in `docs/improvements/golden-fixtures/`) |

   The published flow artifact is the one mirror a git hook cannot reach. Keep `docs/flow.html` accurate during implementation; `recon-publish` republishes a changed file at the release gate (the header comment carries the artifact URL). Implementation-only work never mutates that external mirror.
