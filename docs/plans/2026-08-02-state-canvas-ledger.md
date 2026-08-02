# State canvas + ticket ledger — implementation plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Ship the two accepted improvements — [ticket-ledger](../improvement-proposals/0.13.0/ticket-ledger/README.md) and [state-canvas-skill](../improvement-proposals/0.13.0/state-canvas-skill/README.md) — as rails + one new skill, per the pipeline.md Change protocol.

**Architecture:** Three new rails (*log-event.sh*, *derive-state.sh*, *render-state-canvas.sh*) carry all execution; the new skill *recon-state* holds only the publish step (the Artifact tool needs a session) behind a first-publish gate. The ledger is a root-level append-only `history.ndjson` that `fresh-workspace.sh` preserves across runs and NOTHING may read as evidence (new invariant). The canvas is the approved ATT-5047 node-canvas design turned into a token-substitution template.

**Tech stack:** bash + python3 stdlib (repo convention: no PyYAML, `find`-based checks, exit codes 0/1/2, `RECON_ROOT` override for fixtures). No test suite exists; verification = running rails against the real ATT-5047 workspace + the pre-commit hook chain.

---

## Ground rules binding every task

- Change protocol (pipeline.md): every shared fact edited ONLY in its owner file; mirrors updated in the SAME commit; `bash tools/check-links.sh && bash tools/check-coherence.sh` green before each commit.
- Registry tokens: adding an entry to `recon/docs/registry.yaml` requires the token in `recon/docs/pipeline.md` (registry table), `recon/docs/workspace-index.md`, and `docs/flow.html` — the coherence check enforces this.
- New scripts: role line in `recon/scripts/CLAUDE.md`; uniform exit codes; `RECON_ROOT` support.
- Version: not hand-edited; the release tool bumps it after implementation (user decision).

## Task 1 — accept + plan (docs commit)

- Flip Status to `in-progress` in both idea READMEs + their index rows.
- Save this plan.
- Commit: `docs(plans): accept state-canvas-skill + ticket-ledger, add implementation plan`

## Task 2 — ticket ledger (one feat commit)

**Files:** create *recon/scripts/log-event.sh*; modify `recon/scripts/fresh-workspace.sh`, `recon/scripts/lint-workspace.sh`, `recon/scripts/route-generic.sh`, `recon/scripts/attach-artifacts.sh`, `recon/docs/registry.yaml`, `recon/docs/pipeline.md`, `recon/docs/workspace-index.md`, `docs/flow.html`, `recon/scripts/CLAUDE.md`, and the four SKILL.md callers (triage, discovery, decree, report).

1. **log-event.sh** — `log-event.sh <TICKET> <event> [k=v …]`, plus `--vocab` printing the closed set:
   `run_started verdict routed comment_posted attachments_replaced gate_answered handoff_printed dossier_published canvas_published`.
   Appends `{"ts","run","v","event",…pairs}` (python3 json.dumps; ts UTC now; run + v read from `meta.yaml` `started`/`plugin_version`). Unknown event or malformed pair → exit 1; missing meta → exit 2. `RECON_ROOT` respected.
   (While unbuilt, all three rails are written in italics here — the link check resolves backticks against the working tree.)
2. **fresh-workspace.sh** — archive filter also excludes `history.ndjson`; after stamping meta, call log-event `run_started`; echo a `ledger:` line.
3. **lint-workspace.sh** — after the registry loop: if `history.ndjson` exists, every line must json-parse and carry an in-vocab event (*log-event.sh --vocab* is the single vocabulary owner); violations count as lint failures.
4. **Rails log their own events:** route-generic.sh → `routed route=<route>`; attach-artifacts.sh → `attachments_replaced count=<n>`.
5. **Skill callers (one line each, in existing steps):** triage step 3 after `verify: clean` → `verdict disposition=… blockers=n`; triage posting step 7 after POST → `comment_posted comment=<id> action=<created|edited>`; discovery step 7 after writing `gate.yaml` → `gate_answered approved=…`; discovery step 8 → `handoff_printed`; decree Report → `routed route=…`; report step 6 after publishing → `dossier_published`.
6. **registry.yaml** — entry `history.ndjson` (producer log-event.sh, consumers: recon-state timeline, humans — never evidence). Token added to the three mirror docs.
7. **pipeline.md** — append the NEW ledger invariant ("the ledger is output, never evidence…" — next free number, never renumber existing ones); trigger-table row (which step logs which event — the closed list); rails-table row.
8. Verify: *bash recon/scripts/log-event.sh ATT-5047 made_up* → exit 1 naming the vocab; `run_started` via a `RECON_ROOT` temp fixture appends a parseable line; `lint-workspace.sh` on ATT-5047 clean; both repo checks green.
9. Commit: `feat(workspace): cross-run ticket ledger — history.ndjson + log-event rail`

## Task 3 — recon-state (one feat commit)

**Files:** create *recon/scripts/derive-state.sh*, *recon/scripts/render-state-canvas.sh*, *recon/skills/recon-state/SKILL.md*, *recon/skills/recon-state/template.html*; modify `recon/.claude-plugin/plugin.json` (skills array only), `recon/docs/registry.yaml`, `recon/docs/pipeline.md`, `recon/docs/workspace-index.md`, `docs/flow.html`, `recon/skills/CLAUDE.md`, `recon/scripts/CLAUDE.md`, plus one auto-refresh line in triage + discovery SKILL.md.

1. **derive-state.sh** — closed decision table over file presence + `disposition` + `gate.yaml approved` → writes flat, sed-parseable `state/state.yaml`: `stop:` ∈ {triage-in-progress, comment-gate, awaiting-replies, discovery-in-progress, approval-gate, rejected, handed-off}, `node.<id>: done|current|queued|not-taken|absent` for the 11 canvas nodes, `fact.*` lines (disposition, route, governance, blockers, conflicts, exhibits, scenarios), `next:` one fixed sentence per stop. Contradictory presence (e.g. `routing.yaml` without `discovery.md`) → exit 1 naming both files.
2. **render-state-canvas.sh** — python3 fills `template.html`: `«NODE:<id>»` → status class, `«FACT:…»`/`«NEXT»`/`«TS»` → values, `«TIMELINE»` → one fixed-format line per ledger event (ledger read here is VIEW rendering, not evidence — the new ledger invariant fences decisions, mirroring how the dossier renders triage.yaml). Unresolved marker left in output → exit 1. Writes `state/canvas.html`.
3. **template.html** — the approved ATT-5047 canvas (node map, elbow wires, glow, popovers, next-action chip) with all ticket-specific strings replaced by markers; popover bodies = fixed explanatory text + fact slots + artifact pointers (no free prose).
4. **recon-state SKILL.md** — contract (reads workspace, writes only `state/`); rules: rails do derive+render; publish gate: FIRST publish per ticket asks in-session, URL saved to `state/artifact-url`, later republishes automatic to that URL; log `canvas_published url=…`; report block quoting rail verdict lines.
5. **Wiring:** plugin.json skills array += `./skills/recon-state`; triage Report `Next:` lines and discovery step 7/Report mention invoking `recon:recon-state` at STOP/gate (trigger rows in pipeline.md make it mechanical).
6. **registry.yaml** — `state/state.yaml`, `state/canvas.html`, `state/artifact-url` (+ tokens in 3 mirrors); pipeline.md stage row `S`, trigger rows (refresh at every STOP/gate presentation; first-publish gate), rails rows; workspace-index `state/` section; flow.html stage card + workspace rows; CLAUDE.md role lines.
7. Verify: *derive-state.sh* on ATT-5047 → `stop: approval-gate`; render → `state/canvas.html` with zero unresolved markers; `lint-workspace.sh` clean; repo checks green.
8. Commit: `feat(state): recon-state skill — derived state canvas, ledger timeline, stable artifact URL`

## Task 4 — smoke + mirrors

1. Run the full chain on ATT-5047; adopt the existing canvas artifact URL into `state/artifact-url`; republish the railed canvas to it.
2. Republish `docs/flow.html` to ITS artifact URL (header comment) — the one mirror no hook reaches.
3. Release (`tools/release.sh` or `/recon:recon-publish`) + cache activation + clone sync — **user decision, ask first**; then flip both improvements to `shipped (vX.Y.Z)`.
