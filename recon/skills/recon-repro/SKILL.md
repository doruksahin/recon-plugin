---
name: recon-repro
description: Produce human-rerunnable UI evidence with numbered steps and annotated screenshots. Use when visible behavior must be reproduced, a finding made concrete, or manual-smoke evidence captured.
---

# Recon Repro

Turns an abstract claim or question ("selecting a hidden collection produces a tab value with no tab") into evidence a human can verify in 60 seconds: a stated start state, numbered steps, and a screenshot per state — all captured inside a **recorded browser session** (action log + video) so the steps are transcribed from a mechanical record, never recalled.

## Host setup

Before the first path or tool action, read `../../docs/hosts.md`, then run
`reconctl.sh start repro` once. Retain its root, host, surface, capabilities,
and preflight snapshot for the run. A failed base check is a hard STOP. A
failed recorder check (`command.proofshot`, `command.agent-browser`,
`proofshot_version`) is an honest failed-repro finding — report it with the
check's remediation line and stop; it is never permission to fabricate
evidence or to drive an unrecorded browser instead.

## Contract

- **Input:** ticket ID + the claim/question to make concrete
- **Reads:** current-run stage directories in `$RECON_ROOT/<TICKET>/` (never `runs/`), the running app's UI, `repro/session/session-log.json` (the transcription source)
- **Writes:** ONLY inside `$RECON_ROOT/<TICKET>/repro/` — `repro.md`, `exhibits/<n>-<slug>.png`, and the recorder-finalized `session/` bundle. Create the directory before your first write — a stage directory existing means that stage ran. Anything else fails `lint-workspace.sh`
- **Local side effects:** the recorder rail starts the project's dev server (mock mode preferred) and records the browser session; screenshots are rendered to the user's screen (host file-display capability (see hosts.md))
- **External side effects:** NONE — never touches Jira or the repo.

---

## ⚠️ CRITICAL: Rules

1. **Never fabricate — and the recording proves it.** Every step MUST actually be performed this run inside the recorded session and every screenshot captured this run by a logged `screenshot` action. If reproduction fails (build broken, missing mock data, behavior doesn't reproduce), report the failure honestly with what you observed — a failed repro is itself a finding. NEVER describe steps you did not execute as if you had.
2. **READ-ONLY on the repo.** You MUST NOT edit source code to make the behavior reproducible. Writes go only to `$RECON_ROOT/<TICKET>/repro/`.
3. **The start state MUST be stated and reachable**: prefer the project's mock/dev mode (no backend needed), name the exact page/route. A repro that starts from "wherever the app happens to be" is not reproducible.
4. **Steps MUST be numbered and re-runnable by a human** — each step is one user action on a named, visible element ("click the eye icon on Collection3's row"), never a code operation. Its exhibit reference is visible on that same line; a token hidden in an HTML comment is not evidence.
5. **Human-facing language**: user-observable outcomes only; internal identifiers (service/method/prop names) are BANNED from repro.md and question text.
6. **All browser interaction goes through the recorder rail.** `record-repro.sh <TICKET> start` before the first action, every navigation/click/fill/screenshot via `record-repro.sh <TICKET> exec`, and `record-repro.sh <TICKET> stop` before `repro.md` is written. NEVER invoke `proofshot` or `agent-browser` directly (the rail owns the cwd/config discipline that keeps the session resolvable), and NEVER drive the repro through host preview/browser tools — an unrecorded action leaves no provenance and the verifier will reject the package.
7. **NEVER read archived runs.** `$RECON_ROOT/<TICKET>/runs/` holds prior-run artifacts — you MUST NOT open, list, or reuse anything under it, including old screenshots or session bundles. Every screenshot, log entry, and step you reference must be produced this run (rule 1).
8. **A caller consumes only a verified package.** After writing `repro.md`, run
   `verify-repro.sh` until it prints `verify: clean`. This rail proves the fixed
   metadata, step/exhibit parity, regular non-symlinked in-workspace inputs,
   coarse current-run timestamps, PNG container integrity — and, for a
   successful repro, the recorded session: schema-exact `session-log.json`
   entries inside the run window, every exhibit matched to a logged
   `screenshot` action in step order, and a real `session.webm`. It does not
   decode or prove visual meaning: read every screenshot back and confirm it
   shows the state claimed by its step.

---

## Workflow

### 1. Input

Ticket ID + the claim/question to make concrete (from `$RECON_ROOT/<TICKET>/triage/triage.yaml`, `discovery/discovery.md`, or the user's message). Restate it as the *observable* thing to demonstrate: baseline state → user action → resulting state.

### 2. Start the recording (boots the app)

Find the project's documented dev command (mock mode preferred, no backend needed) and port, then start the recorded session — the rail pins its working directory and config; run it from anywhere:

```bash
bash "<skill base dir>/../../scripts/record-repro.sh" <TICKET> start \
  --port <port> --description "<one-line claim>" \
  --run "cd <absolute repo path> && <documented dev command>"
```

Omit `--run` ONLY when the dev server was explicitly started by the user (server logs are then absent from the bundle). If `start` fails (server never came up, recorder broken), that is the finding: skip to step 6 and write an honest `reproduced: false` package with the rail's output as `failure_reason` evidence. Do not create host configuration in the target repo — this stage is read-only there.

### 3. Plan the state sequence

Minimal set of states that makes the question answerable — typically: **baseline → action → after → (the anomaly)**. Each state gets one screenshot.

### 4. Execute and capture — through the rail only

```bash
bash "<skill base dir>/../../scripts/record-repro.sh" <TICKET> exec open http://localhost:<port>/<page>
bash "<skill base dir>/../../scripts/record-repro.sh" <TICKET> exec snapshot -i
bash "<skill base dir>/../../scripts/record-repro.sh" <TICKET> exec click @<ref>
bash "<skill base dir>/../../scripts/record-repro.sh" <TICKET> exec screenshot <n>-<slug>.png
```

Verify the needed entities exist (read the snapshot output) — if mock data lacks them, note which handler/fixture is missing, stop the recording, and report honestly (rule 1). Take exactly one `screenshot <n>-<slug>.png` per planned state, numbered in step order — these become `repro/exhibits/` at stop.

### 5. Stop and finalize

```bash
bash "<skill base dir>/../../scripts/record-repro.sh" <TICKET> stop
```

Quote its `EXHIBIT:` and `SESSION:` lines in your progress note. The bundle is now at `repro/session/` (action log, video, console/server logs) and the step screenshots are in `repro/exhibits/`.

### 6. Write `repro.md` — transcribed from the log

Read `repro/session/session-log.json` and transcribe: each numbered step describes, in rule-5 human language, the logged action(s) between the previous screenshot and this step's `screenshot <n>-<slug>.png` entry. The log is the record of what happened; your judgment is the human phrasing, not the sequence. A successful package uses exactly this frontmatter and one contiguous numbered step per exhibit (exhibit number = step number; the reference must be rendered Markdown, not an HTML comment):

```markdown
---
recon: repro
ticket: <TICKET>
reproduced: true
start_state: <dev command, page, and preconditions on one line>
failure_reason: ""
---

# Repro — <TICKET>: <one-line claim>

1. <action on named element> → <observable result>   [exhibits/1-baseline.png]
2. ...

## The question (concrete form)
<the rewritten question, options as user-observable outcomes with step numbers>
```

If the behavior cannot be reproduced, use `reproduced: false`, preserve the
attempted reachable `start_state`, put the concrete cause in `failure_reason`,
and write a short observation below the title. Do not write numbered success
steps or retain exhibits from an earlier attempt; absence of invented evidence
is what makes the failed package valid. Keep the session bundle if the
recording started — it documents the attempt; a failure before `start`
succeeded legitimately has no bundle.

### 7. Verify the package

```bash
bash "<skill base dir>/../../scripts/verify-repro.sh" <TICKET>
```

Fix the artifact and re-run until it prints `verify: clean`. Never weaken the
contract or hand a failed verification to Discovery. For `reproduced: true`,
read every PNG back after the rail passes and verify its visible state yourself.

### 8. Return — and SHOW the evidence

**Show the screenshots to the user** through the host file-display capability in `hosts.md` so they are visible on screen BEFORE any question is asked — a plain file path is not shown evidence; mention that the full session video is at `repro/session/session.webm`. Then print the concrete question text for the calling skill — `recon:recon-triage`/`recon:recon-discovery` embed it in their drafted comment or gate question. When invoked for SPEC/PR smoke evidence, show and print the evidence paths instead.

---

## Report

Print:

```
Wrote: $RECON_ROOT/<TICKET>/repro/repro.md (+ <n> screenshots in repro/exhibits/)
Session: <the rail's SESSION: line, verbatim — or "none (failed before recording)">
Repro: <reproduced | failed — <honest reason>>
Verify: <verify-repro.sh verdict line, verbatim>
Next: <calling skill embeds the concrete question | attach evidence to PR>
```

---

## Reference

- Screenshot naming: `exhibits/<n>-<slug>.png`, numbered in step order (the directory carries the "repro" meaning); take them via `exec screenshot <n>-<slug>.png` so the log pairs them.
- The session bundle (`repro/session/`) rides into the delivery zip; the video lets a PM watch the anomaly instead of interpolating between stills. Oversized files are skipped by the packaging rail with a visible `SKIPPED` line.
- Annotate only when ambiguity demands it; a clean screenshot of the right state beats a cluttered annotated one.
- Mock-data gaps are findings: "the behavior cannot be exercised in mock mode — handler X missing" is a valid, useful output.
- This skill doubles as the evidence-capture step for SPEC "manual smoke" acceptance criteria and PR screenshots.
- Standing caller: `recon:recon-discovery` invokes this mandatorily for the primary scenario of every visible-UI defect (its rule 10) — the verified start state and numbered steps are copied verbatim into `spec-draft.md`'s Manual verification section, and the screenshots serve as the PR's "before" evidence.
- Whole-chain spec (stages, invariants, artifact registry, trigger table): `../../docs/pipeline.md` relative to this skill's base directory. On conflict, this SKILL.md wins.
