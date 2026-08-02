---
name: recon-repro
description: Produce human-rerunnable UI evidence with numbered steps and annotated screenshots. Use when visible behavior must be reproduced, a finding made concrete, or manual-smoke evidence captured.
---

# Recon Repro

Turns an abstract claim or question ("selecting a hidden collection produces a tab value with no tab") into evidence a human can verify in 60 seconds: a stated start state, numbered steps, and a screenshot per state — written to the ticket's recon workspace.

## Host setup

Before the first path or tool action, read `../../docs/hosts.md`, then run
`reconctl.sh start base` once. Retain its root, host, surface, capabilities, and
preflight snapshot for the run. A failed preflight is a hard STOP. Use only the
declared browser and file-display capabilities; missing browser capability is an
honest failed-repro finding, never permission to fabricate evidence. Later rails
still detect their current host and surface independently.

## Contract

- **Input:** ticket ID + the claim/question to make concrete
- **Reads:** current-run stage directories in `$RECON_ROOT/<TICKET>/` (never `runs/`), the running app's UI
- **Writes:** ONLY inside `$RECON_ROOT/<TICKET>/repro/` — `repro.md` + `exhibits/<n>-<slug>.png`. Create the directory before your first write — a stage directory existing means that stage ran. Anything else fails `lint-workspace.sh`
- **Local side effects:** starts the project's dev server (preview tools, mock mode preferred); renders the screenshots to the user's screen (host file-display capability (see hosts.md))
- **External side effects:** NONE — never touches Jira or the repo.

---

## ⚠️ CRITICAL: Rules

1. **Never fabricate.** Every step MUST actually be performed this run and every screenshot actually captured this run. If reproduction fails (build broken, missing mock data, behavior doesn't reproduce), report the failure honestly with what you observed — a failed repro is itself a finding. NEVER describe steps you did not execute as if you had.
2. **READ-ONLY on the repo.** You MUST NOT edit source code to make the behavior reproducible. Writes go only to `$RECON_ROOT/<TICKET>/repro/`.
3. **The start state MUST be stated and reachable**: prefer the project's mock/dev mode (no backend needed), name the exact page/route. A repro that starts from "wherever the app happens to be" is not reproducible.
4. **Steps MUST be numbered and re-runnable by a human** — each step is one user action on a named, visible element ("click the eye icon on Collection3's row"), never a code operation. Its exhibit reference is visible on that same line; a token hidden in an HTML comment is not evidence.
5. **Human-facing language**: user-observable outcomes only; internal identifiers (service/method/prop names) are BANNED from repro.md and question text.
6. **Use the host preview/start capability** from `hosts.md`. If the host has no preview launcher but exposes a local shell, start the project's already-documented dev command without editing the repo. If neither capability exists, report an unavailable-runtime finding and stop.
7. **NEVER read archived runs.** `$RECON_ROOT/<TICKET>/runs/` holds prior-run artifacts — you MUST NOT open, list, or reuse anything under it, including old screenshots. Every screenshot and step you reference must be produced this run (rule 1).
8. **A caller consumes only a verified package.** After writing `repro.md`, run
   `verify-repro.sh` until it prints `verify: clean`. This rail proves the fixed
   metadata, step/exhibit parity, regular non-symlinked in-workspace inputs,
   coarse current-run timestamps, and PNG container integrity: bounded and
   ordered chunks, every chunk CRC, a complete IDAT zlib stream, and terminal
   IEND with no trailing data. It does not decode or prove visual meaning: read
   every screenshot back and confirm it shows the state claimed by its step.

---

## Workflow

### 1. Input

Ticket ID + the claim/question to make concrete (from `$RECON_ROOT/<TICKET>/triage/triage.yaml`, `discovery/discovery.md`, or the user's message). Restate it as the *observable* thing to demonstrate: baseline state → user action → resulting state.

### 2. Boot the app

Use the host preview/start capability with the project's existing dev-server config; prefer the project's mock mode so no backend is needed. Do not create host configuration in the target repo because this stage is read-only. Navigate to the named page. Verify the needed entities exist in mock data — if not, note which handler/fixture is missing and stop honestly (rule 1).

### 3. Plan the state sequence

Minimal set of states that makes the question answerable — typically: **baseline → action → after → (the anomaly)**. Each state gets one screenshot.

### 4. Execute and capture

Drive the UI (the host page-inspection capability to find elements, the host browser-control capability to click, screenshot per state). Save each as `$RECON_ROOT/<TICKET>/repro/exhibits/<n>-<slug>.png`. Verify each screenshot actually shows the state you claim (read it back if unsure).

### 5. Write `repro.md`

A successful package uses exactly this frontmatter and one contiguous numbered
step per exhibit. The exhibit number MUST equal the step number, and the
reference must be rendered Markdown rather than an HTML comment.

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
is what makes the failed package valid.

### 6. Verify the package

```bash
bash "<skill base dir>/../../scripts/verify-repro.sh" <TICKET>
```

Fix the artifact and re-run until it prints `verify: clean`. Never weaken the
contract or hand a failed verification to Discovery. For `reproduced: true`,
read every PNG back after the rail passes and verify its visible state yourself.

### 7. Return — and SHOW the evidence

**Show the screenshots to the user** through the host file-display capability in `hosts.md` so they are visible on screen BEFORE any question is asked — a plain file path is not shown evidence. Then print the concrete question text for the calling skill — `recon:recon-triage`/`recon:recon-discovery` embed it in their drafted comment or gate question. When invoked for SPEC/PR smoke evidence, show and print the evidence paths instead.

---

## Report

Print:

```
Wrote: $RECON_ROOT/<TICKET>/repro/repro.md (+ <n> screenshots in repro/exhibits/)
Repro: <reproduced | failed — <honest reason>>
Verify: <verify-repro.sh verdict line, verbatim>
Next: <calling skill embeds the concrete question | attach evidence to PR>
```

---

## Reference

- Screenshot naming: `exhibits/<n>-<slug>.png`, numbered in step order (the directory carries the "repro" meaning).
- Annotate only when ambiguity demands it; a clean screenshot of the right state beats a cluttered annotated one.
- Mock-data gaps are findings: "the behavior cannot be exercised in mock mode — handler X missing" is a valid, useful output.
- This skill doubles as the evidence-capture step for SPEC "manual smoke" acceptance criteria and PR screenshots.
- Standing caller: `recon:recon-discovery` invokes this mandatorily for the primary scenario of every visible-UI defect (its rule 10) — the verified start state and numbered steps are copied verbatim into `spec-draft.md`'s Manual verification section, and the screenshots serve as the PR's "before" evidence.
- Whole-chain spec (stages, invariants, artifact registry, trigger table): `../../docs/pipeline.md` relative to this skill's base directory. On conflict, this SKILL.md wins.
