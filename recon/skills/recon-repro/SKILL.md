---
description: Reproduce an observable app behavior live and capture numbered repro steps plus annotated screenshots as evidence. Use when a recon question or finding concerns visible UI behavior, when asked to make a finding concrete or reproducible, or to capture manual-smoke evidence for a SPEC or PR.
---

# Recon Repro

Turns an abstract claim or question ("selecting a hidden collection produces a tab value with no tab") into evidence a human can verify in 60 seconds: a stated start state, numbered steps, and a screenshot per state — written to the ticket's recon workspace.

## Contract

- **Input:** ticket ID + the claim/question to make concrete
- **Reads:** current-run artifacts in `~/.claude/recon/<TICKET>/` (never `runs/`), the running app's UI
- **Writes:** `~/.claude/recon/<TICKET>/repro.md` + `repro-<n>-<slug>.png`
- **Local side effects:** starts the project's dev server (preview tools, mock mode preferred); renders the screenshots to the user's screen (SendUserFile)
- **External side effects:** NONE — never touches Jira or the repo.

---

## ⚠️ CRITICAL: Rules

1. **Never fabricate.** Every step MUST actually be performed this run and every screenshot actually captured this run. If reproduction fails (build broken, missing mock data, behavior doesn't reproduce), report the failure honestly with what you observed — a failed repro is itself a finding. NEVER describe steps you did not execute as if you had.
2. **READ-ONLY on the repo.** You MUST NOT edit source code to make the behavior reproducible. Writes go only to `~/.claude/recon/<TICKET>/`.
3. **The start state MUST be stated and reachable**: prefer the project's mock/dev mode (no backend needed), name the exact page/route. A repro that starts from "wherever the app happens to be" is not reproducible.
4. **Steps MUST be numbered and re-runnable by a human** — each step is one user action on a named, visible element ("click the eye icon on Collection3's row"), never a code operation.
5. **Human-facing language**: user-observable outcomes only; internal identifiers (service/method/prop names) are BANNED from repro.md and question text.
6. **Use the Browser pane preview tools** (`preview_start` with a launch.json entry) to run the dev server — NEVER Bash.
7. **NEVER read archived runs.** `~/.claude/recon/<TICKET>/runs/` holds prior-run artifacts — you MUST NOT open, list, or reuse anything under it, including old screenshots. Every screenshot and step you reference must be produced this run (rule 1).

---

## Workflow

### 1. Input

Ticket ID + the claim/question to make concrete (from `~/.claude/recon/<TICKET>/triage.yaml`, `discovery.md`, or the user's message). Restate it as the *observable* thing to demonstrate: baseline state → user action → resulting state.

### 2. Boot the app

`preview_start` with the project's dev-server config (create a `.claude/launch.json` entry if missing; prefer the project's mock mode so no backend is needed). Navigate to the named page. Verify the needed entities exist in mock data — if not, note which handler/fixture is missing and stop honestly (rule 1).

### 3. Plan the state sequence

Minimal set of states that makes the question answerable — typically: **baseline → action → after → (the anomaly)**. Each state gets one screenshot.

### 4. Execute and capture

Drive the UI (`read_page` to find elements, `computer` to click, screenshot per state). Save each as `~/.claude/recon/<TICKET>/repro-<n>-<slug>.png`. Verify each screenshot actually shows the state you claim (read it back if unsure).

### 5. Write `repro.md`

```markdown
# Repro — <TICKET>: <one-line claim>

Start state: <dev command>, <page>, <any preconditions>

1. <action on named element> → <observable result>   [repro-1-baseline.png]
2. ...

## The question (concrete form)
<the rewritten question, options as user-observable outcomes with screenshot refs>
```

### 6. Return — and SHOW the evidence

**Send the screenshots to the user** (SendUserFile with `display: render`, or the client's inline equivalent) so they are visible on screen BEFORE any question is asked — a file path is not shown evidence. Then print the concrete question text for the calling skill — `recon:recon-triage`/`recon:recon-discovery` embed it in their drafted comment or gate question. When invoked for SPEC/PR smoke evidence, send + print the evidence paths instead.

---

## Report

Print:

```
Wrote: ~/.claude/recon/<TICKET>/repro.md (+ <n> screenshots)
Repro: <reproduced | failed — <honest reason>>
Next: <calling skill embeds the concrete question | attach evidence to PR>
```

---

## Reference

- Screenshot naming: `repro-<n>-<slug>.png`, numbered in step order.
- Annotate only when ambiguity demands it; a clean screenshot of the right state beats a cluttered annotated one.
- Mock-data gaps are findings: "the behavior cannot be exercised in mock mode — handler X missing" is a valid, useful output.
- This skill doubles as the evidence-capture step for SPEC "manual smoke" acceptance criteria and PR screenshots.
- Standing caller: `recon:recon-discovery` invokes this mandatorily for the primary scenario of every visible-UI defect (its rule 10) — the resulting `repro.md` is copied verbatim into `spec-draft.md`'s Manual verification section, and the screenshots serve as the PR's "before" evidence.
