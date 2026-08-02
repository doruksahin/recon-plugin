---
name: recon-discovery
description: Turn a READY ticket into an evidence-backed behavior contract, route, and approval-gated implementation brief. Use when triage returns READY or when preparing work for planning or implementation.
---

# Recon Discovery

Maps the code surface for a triaged-READY ticket, writes an evidence-backed behavior contract, has the routing stage decide the implementation path, drafts the brief, then delivers the approved dossier and bundle to Jira behind a separate explicit delivery gate — never at code.

## Host setup

Before the first path or tool action, read `../../docs/hosts.md`, then run
`reconctl.sh start base` once. Retain its root, host, surface, capabilities, and
preflight snapshot for the run. A failed preflight is a hard STOP. Do not change
any gate or evidence rule. Later rails still detect their current host and
surface independently.

## Contract

- **Input:** ticket ID (precondition: `$RECON_ROOT/<TICKET>/triage/triage.yaml` with `disposition: READY`)
- **Reads:** the target repo (read-only), current-run artifacts in `$RECON_ROOT/<TICKET>/` (never `runs/`), `route/routing.yaml` after the routing stage runs
- **Writes:** ONLY inside `$RECON_ROOT/<TICKET>/discovery/` — `discovery.md`, `gate.yaml`, `gate-questions.md` (written by the `render-gate.sh` rail, never by hand), and `spec-draft.md` only when `brief_kind` is not `none`. After package approval, the shared Jira delivery rails write their registered audit files under `triage/jira/`. Create the directory before your first write — a stage directory existing means that stage ran. Anything else fails `lint-workspace.sh`.
- **External side effects:** NONE until the approved package reaches the READY delivery gate. Then at most one Jira comment (create, or edit of the most recent Recon marker comment) plus replacement of Recon-owned attachments — drafted/staged first and sent ONLY after that distinct explicit delivery approval. After delivery (or an explicit no-post answer) it PRINTS the handoff verbatim from `routing.yaml`, never executes it.
- **May invoke:** `recon:recon-repro` (primary scenario of UI defects + OPEN scenarios about visible UI), `recon:recon-triage` (missing or stale triage), `recon:recon-report` (render-only READY delivery dossier), and the governance adapter skill named by convention `recon:recon-<governance>` (only when governance resolves to something other than `none`)

---

## ⚠️ CRITICAL: Rules

1. **Precondition:** `$RECON_ROOT/<TICKET>/triage/triage.yaml` MUST exist with `disposition: READY`. If missing or not READY, invoke the `recon:recon-triage` skill first — NEVER skip triage.
2. **READ-ONLY on the repo.** Writes go only to `$RECON_ROOT/<TICKET>/discovery/` plus the registered shared Jira-delivery audit artifacts after approval. You MUST NOT implement, branch, or edit code.
3. **No prose unknowns.** Every "unknown" MUST be either resolved by running a command, or converted into a question with a named owner. "It is not yet known whether…" is a forbidden sentence.
4. **Every claim carries evidence** — `file:line` or command output. A responsibility map without line numbers is not done.
5. **Routing is consumed, never composed.** The route comes from the routing stage — `scripts/route-generic.sh` (a rail) or the governance adapter skill — as `route/routing.yaml`. NEVER route by feel, NEVER edit `routing.yaml`, and quote its `handoff:` block VERBATIM wherever the handoff is shown. Discovery's authority ends at describing; the routing stage decides the path.
6. **Governance is the developer's choice, resolved mechanically.** Run `scripts/detect-governance.sh` (the ladder: env > config > probe); on `undecided`, ask the one-time question (step 4) and persist the answer via `scripts/set-governance.sh answer` — NEVER decide silently, NEVER let detection alone opt a developer in. When governance resolves to `none`, governance-system vocabulary is BANNED from every artifact and printed line (`lint-workspace.sh` greps for it).
7. **Human-facing questions MUST be concrete.** Gate questions and OPEN scenarios must be answerable without reading code: numbered repro steps from a stated start state (e.g. the project's mock-mode dev command, which page), concrete entity names from the running system, before/after state, and options phrased as user-observable outcomes ("the tab appears and becomes selected"), never code outcomes ("activeTab is set"). Internal identifiers are BANNED from question text — they belong in the evidence tables, not the question. If an OPEN scenario concerns observable UI behavior, invoke the `recon:recon-repro` skill to attach visual evidence BEFORE presenting the gate.
8. **READY delivery is required after package approval, but never automatic.** Render the final dossier, deterministic READY comment, and bundle after `verify-discovery.sh` passes post-gate. Show their exact bytes/names/sizes/file count through the host-native delivery gate, then post attachments first and the comment only on a fresh explicit “Post to Jira now” answer. Never reuse the package-approval answer as Jira approval.
9. **NEVER read archived runs.** `$RECON_ROOT/<TICKET>/runs/` holds artifacts from prior runs (possibly produced by older skill versions) — you MUST NOT open, list, or cite anything under it. Consume only the current-run stage directories (`triage/`, `route/`, `repro/`, …); a current run is one whose root `meta.yaml` exists alongside `triage/triage.yaml`.
10. **UI defects get a primary-scenario repro — mechanically, not by judgment call.** The trigger is a condition, not a vibe: `task_class: defect` AND the affected surface is visible UI AND `routing.route` is not a trivial-direct route (`direct` / `no-doc`) → invoke `recon:recon-repro` for the bug itself in step 6, before the brief and gate. No implementer may receive a UI-defect brief without a reproduce-the-bug path in it.
11. **The package crosses boundaries only after verification.** Run
    `verify-discovery.sh <TICKET> pre-gate` before asking any gate question and
    `verify-discovery.sh <TICKET> post-gate` after recording the answer. Fix the
    authored artifact that failed; never edit `route/routing.yaml` or weaken the
    verifier to make a package pass. The rail accepts only regular,
    non-symlinked inputs that resolve inside the current workspace.
12. **The gate presents rail-rendered bytes and records the exchange verbatim.**
    `render-gate.sh` emits `discovery/gate-questions.md` from `discovery.md` +
    `routing.yaml`; you present those blocks word-for-word — NEVER a paraphrase —
    and `gate.yaml` stores each exchange (the user's exact answer next to its
    mapped resolution). `gate-questions.md` is never hand-edited: to change a
    question, edit `discovery.md` and re-render.
13. **The handoff-style question is the rail's own text, and its answer is on
    the record.** `set-governance.sh question <tool>` owns the wording; you
    present those bytes word-for-word and hand the developer's exact words back
    through `set-governance.sh answer`, which writes the standing config and
    the exchange record together or writes neither. NEVER retype the question,
    NEVER persist a mapped value without the answer that produced it.

---

## Workflow

### 1. Load context

Read `triage/triage.yaml` (ticket, task_class, conflicts). Confirm you are in the repo the ticket targets. Create your stage directory: `mkdir -p "$RECON_ROOT/<TICKET>/discovery"`.

### 2. Map the code surface

- Locate the owning component/service for the affected behavior (Grep/Glob; serena/LSP when available). Record every claim as `file:line`.
- Find the **existing contract to reuse**: is there already a service method/transition that does what the ticket needs? (`reuses_existing_contract: true/false` — the routing stage consumes this.)
- Identify the test surface: existing test files, or the new test file the change needs.
- **Edge-case scan:** for the affected UI surface, list what *renders* the data vs what *consumes* the resulting state. Mismatches (e.g. a panel rendering ALL items while the consumer handles only VISIBLE ones) are edge-case candidates — each becomes an OPEN Gherkin scenario, never a silent assumption.

### 3. Write the behavior contract

Give every scenario a unique, visible H2 heading in one of three namespaces:

- `## REQ-N` — required behavior
- `## REG-N` — must-not-change regression behavior
- `## OPEN-N` — an edge case that needs a human decision

An ID heading or `No scenarios:` declaration inside an HTML comment, fenced
example, or indented code block is not part of the contract. Under every real
heading write visible `Scenario:`, `Given`, `When`, and `Then` content; a fenced
Gherkin block is allowed after the real heading because its contents render.
OPEN scenarios also carry 2–3 labeled options as visible list lines in the
exact shape `- A: <outcome>` (the gate renderer parses them), with EXACTLY one
option ending in `(recommended)` — the recommendation is authored here, on the
record, never improvised at the gate. Option outcomes describe user-observable
behavior (rule 7), never internal state. Keep each ID unchanged
through edits and the gate: the brief and gate use these IDs as join keys. If
the change genuinely admits no scenario (copy fix, dead code, dep bump), write
`No scenarios:` plus the evidenced reason in `discovery.md`; do not invent a
placeholder scenario.

### 4. Resolve the handoff style (rail + at most one one-time question)

Internally this is the `governance` setting; every USER-FACING word about it describes what the developer gets — the **handoff style** — never the machinery. Rule 7's concreteness applies to the pipeline's own questions exactly as it does to Jira asks: options are outcomes, not config values.

```bash
bash "<skill base dir>/../../scripts/detect-governance.sh"   # run from the repo
```

- `governance: none` or a concrete adapter → proceed to step 5 with the printed `source`.
- `governance: undecided` (a doc tool is present but the developer never chose) → ask once, from the rail's own bytes. Take the tool's name from the script's evidence line, render the question, and present it word-for-word via the host-native user interaction in `hosts.md` — the wording lives in the rail, so NEVER retype or paraphrase it (rule 13):

  ```bash
  bash "<skill base dir>/../../scripts/set-governance.sh" question <tool>
  ```

  Then map the answer — docs → the tool's name, plain briefs → `none`, follow each repo → `auto` — and persist it together with the developer's exact words. The rail writes the config and the exchange record or neither:

  ```bash
  bash "<skill base dir>/../../scripts/set-governance.sh" answer <the tool's name | none | auto> <tool> "<the developer's answer, their exact words, unedited>"
  ```

  Then re-run `detect-governance.sh`; it now resolves from config and the question never fires again (change it anytime by re-running `set-governance.sh <value>`).

### 5. Route (the routing stage — never done by hand)

- **`governance: none`** → `bash "<skill base dir>/../../scripts/route-generic.sh" <TICKET> <source>` — a pure rail: 0 scenarios in `discovery.md` → `direct`, otherwise `brief`.
- **anything else** → invoke the adapter skill `recon:recon-<governance>` (host-native skill invocation; see hosts.md); it runs its checks and writes `route/routing.yaml` itself.

Then read back `route/routing.yaml` and note three fields for the rest of the run: `route`, `brief_kind`, `handoff`.

### 6. Capture and verify required UI evidence

Invoke the `recon:recon-repro` skill BEFORE the gate when either condition holds (evaluate both; they are mechanical, not judgment calls):

- **Primary scenario (rule 10):** `task_class: defect` AND visible UI surface AND `route` ∉ {`direct`, `no-doc`} → repro the bug itself. Its screenshots are the gate's evidence and the PR's "before" half.
- **OPEN scenarios (rule 7):** any OPEN scenario concerns observable UI behavior → repro it and reference the numbered steps + screenshots in the question.

One repro session covers both when the scenarios share a start state — don't boot the dev server twice.

The repro skill verifies its own package. Before consuming its steps, run the
rail again at this boundary and require `verify: clean`:

```bash
bash "<skill base dir>/../../scripts/verify-repro.sh" <TICKET>
```

### 7. Draft the brief (per `brief_kind` — a field, not a judgment)

- `none` → do not create `spec-draft.md`; proceed to step 8.
- `implementation-brief` → write `spec-draft.md` with these exact H2 sections:
  `Overview`, `Acceptance criteria`, `Technical design`, `Integration
  guardrails`, and `Manual verification`. The acceptance criteria are visible
  Markdown checkbox lines derived 1:1 from every scenario and start with the
  same stable ID (`- [ ] REQ-1 — …`, `- [ ] REG-1 — …`, `- [ ] OPEN-1 — …`).
  Checkboxes inside HTML comments, fenced examples, or indented code do not
  count. Technical
  design is the wiring in ≤10 lines and names the contract to reuse. Manual
  verification copies the verified `start_state` and numbered repro steps,
  marking the buggy outcome BEFORE and expected outcome AFTER, and — when
  `repro/session/` exists — ends with the recorded-session pointer line
  `Recorded session: repro/session/viewer.html` so the implementer can watch
  the bug before reproducing it. If no repro was
  triggered, state the mechanical reason and environment verification needed.
  If an honest repro failed, copy its attempted start state and failure reason,
  not fictional steps. The implementer must be able to reach the affected
  surface without re-deriving it.
- `problem-statement` → write `spec-draft.md` with these exact H2 sections:
  `Context`, `Current behavior`, `Desired outcome`, and `Open choices`. Its
  stable-ID set must equal the contract's set: include every `REQ-N`, `REG-N`,
  and `OPEN-N`, and invent none. Each ID begins exactly one visible single-line
  entry: place REQ/REG entries in `Context`, `Current behavior`, or `Desired
  outcome`, and each OPEN entry in `Open choices` (`- OPEN-1 — …`). HTML
  comments, fenced examples, and indented code are not entries. The downstream
  document named in the handoff starts from this evidence-backed statement.

### 8. Verify, render the gate, present it, record the exchange

Run the pre-gate verifier and fix authored artifacts until clean:

```bash
bash "<skill base dir>/../../scripts/verify-discovery.sh" <TICKET> pre-gate
```

Then render the gate questions — NEVER write or paraphrase them by hand (rule
12). The rail emits `discovery/gate-questions.md` from `discovery.md` +
`routing.yaml`: one block per `OPEN-N` (scenario, options, the one
`(recommended)` marker) plus the `PACKAGE` block:

```bash
bash "<skill base dir>/../../scripts/render-gate.sh" <TICKET>
```

Present via the host-native user interaction (see hosts.md), quoting each
rendered block word-for-word:
- One question per OPEN scenario decision — the `## OPEN-N` block verbatim.
- One question for the package itself — the `## PACKAGE` block verbatim:
  `Approve / Edit / Reject`.

Record the outcome in `discovery/gate.yaml`. Resolution keys are the exact
`OPEN-N` headings from `discovery.md` (never summaries or option letters), and
`exchanges` stores the full exchange verbatim — one entry per `OPEN-N` plus one
`PACKAGE` entry, exact two-space indent steps (the rails parse them):

```yaml
gate:
  approved: true | false
  date: YYYY-MM-DD
  open_scenario_resolutions:
    OPEN-1: "<chosen option> — <user-observable summary>"
  exchanges:
    - id: OPEN-1
      presented: gate-questions.md#OPEN-1
      recommendation: "<the (recommended) option line's outcome>"
      answer_verbatim: "<the user's answer, their exact words, unedited>"
      resolution: "<chosen option> — <user-observable summary>"   # = the same-key resolution above
    - id: PACKAGE
      presented: gate-questions.md#PACKAGE
      answer_verbatim: "<the user's answer, their exact words, unedited>"
      resolution: approved | rejected                             # must match `approved` above
  rejected: "<user's reason — only present on Reject>"
```

Use `open_scenario_resolutions: {}` only when there are no OPEN scenarios (the
`exchanges` list then carries only the `PACKAGE` entry). Every post-gate
package has exact OPEN-key parity, including a rejection: if the user rejected
before selecting an option, record that key as `unresolved — package rejected
before selection` and store the user's rejecting words as that exchange's
`answer_verbatim`. On approval, copy the complete resolution string verbatim
into the same-ID entry: the `OPEN-N` acceptance checkbox for an implementation
brief, or that visible `OPEN-N` line in a problem statement's `Open choices`
section. Preserve the ID. On Edit, apply the edits to the artifacts, re-run
pre-gate verification, re-render the gate questions (rule 12), and re-present.

Run `verify-discovery.sh <TICKET> post-gate` until it prints `verify: clean`.
**NEVER proceed past a Reject.** On Reject: write `approved: false` +
`rejected`; verify it; render the Discovery and Triage invocations with
`reconctl.sh invocation`; print `Next: fix what the rejection names and run
<Discovery invocation> again; if the ticket itself is wrong, run <Triage
invocation> or raise it with the reporter` — and STOP.

Whenever `gate.yaml` is written (approve OR reject), log it (invariant 16):

```bash
bash "<skill base dir>/../../scripts/log-event.sh" <TICKET> gate_answered approved=<true|false>
```

### 9. READY Jira delivery (after an approved package)

1. Invoke `recon:recon-report` in render-only mode. It verifies the post-gate package and writes `report/dossier.html`; do not publish it as a private artifact.
2. Render the READY delivery index — never hand-write it — then run its independent shape rail:

   ```bash
   bash "<skill base dir>/../../scripts/render-comment.sh" <TICKET>
   bash "<skill base dir>/../../scripts/verify-comment-shape.sh" <TICKET>
   ```

   The renderer requires `disposition: READY`, `discovery/gate.yaml` with `approved: true`, and `route/routing.yaml`. Its six non-empty lines contain the verified outcome, approval-decision count, route, attachment links, and marker; the dossier and ZIP carry the full packet.
3. Package only after the dossier and comment exist:

   ```bash
   bash "<skill base dir>/../../scripts/package-artifacts.sh" <TICKET>
   ```

   Quote the resulting `MANIFEST:` and `ZIP:` lines. Stage a temp copy named `recon-dossier-<TICKET>.html`; the ZIP is already staged outside the workspace.
4. **Render the delivery gate question** — NEVER compose it by hand. The same posting-gate rail used by triage emits the exact `comment.txt`, attachment names/sizes, bundle count, and three options:

   ```bash
   bash "<skill base dir>/../../scripts/render-post-gate.sh" <TICKET> "<ZIP path from step 3>"
   ```

5. **Delivery gate (one fresh approval).** Present `triage/jira/post-gate-questions.txt` word-for-word. Record every presentation in `triage/jira/post-gate.yaml` as the caller for this approved READY delivery: `presented: post-gate-questions.txt`, the user's exact `answer_verbatim`, and `outcome: posted | edited | declined`. On Edit package first, append `edited`, change the source artifacts, re-run post-gate verification, then steps 1–4 and re-present; never hand-edit `comment.txt`. On Don't post, append `declined`, log `post_declined`, run `verify-post-gate.sh`, and continue to the handoff.
6. **On Post:** replace attachments before the comment:

   ```bash
   cp "$RECON_ROOT/<TICKET>/report/dossier.html" "${TMPDIR:-/tmp}/recon-dossier-<TICKET>.html"
   bash "<skill base dir>/../../scripts/attach-artifacts.sh" <TICKET> \
     "${TMPDIR:-/tmp}/recon-dossier-<TICKET>.html" "<ZIP path from step 3>"
   ```

   Fetch live comments and edit the most recent body containing `recon-triage`; create one only when no marker exists. Save the create/edit response to `triage/jira/post-result.json`, then log `comment_posted` with its id and action. Then run `verify-post-gate.sh <TICKET>` until it prints `post-gate: clean` before the handoff.

### 10. Handoff (after delivery or an explicit no-post answer — print, don't execute)

Print `route/routing.yaml`'s `handoff:` block **verbatim** under a `Next:` line. Nothing is added, reworded, or dropped — the routing stage authored it; discovery only relays it. Then log `bash "<skill base dir>/../../scripts/log-event.sh" <TICKET> handoff_printed` (invariant 16).

---

## Report

If `$RECON_ROOT/<TICKET>/state/artifact-url` exists (mechanical check: `find` it), invoke the `recon:recon-state` skill first — the gate was just answered (or presented), so the ticket's canvas must be refreshed (no gate; the URL already exists).

Print:

```
Wrote: <actual files: discovery.md + gate-questions.md + gate.yaml, spec-draft.md unless brief_kind is none, and report/dossier.html + triage/jira/{comment.txt,bundle-manifest.txt,post-gate-questions.txt,post-gate.yaml} on the READY delivery path>
Route: <route> (rule <matched_rule>) — see route/routing.yaml
Handoff style: <plain-words line from the table below> (governance: <governance>/<source>)
Verify: <verify-discovery.sh post-gate verdict line, verbatim>
Lint: <run `bash "<skill base dir>/../../scripts/lint-workspace.sh" <TICKET>` — quote its verdict line; fix any violation before reporting>
Open decisions resolved at gate: <n>
Delivery: <comment + attachments posted | comment NOT posted (your choice)>
Next: <routing.yaml handoff, verbatim | rejected — reason recorded in gate.yaml, re-run instructions above>
Optional: <`reconctl.sh invocation recon.report <TICKET>` output> — HTML dossier of this run (private artifact when publishing is available; otherwise a local file)
```

The `Handoff style:` line translates the script's `source` token into the developer's own terms — MECHANICAL mapping, no improvisation. The fence still binds: rows marked † must not name the tool (governance resolved to `none`):

| `source` | Handoff style line reads |
|---|---|
| `config` (value = a tool) | `<tool> docs — your standing choice (change anytime: set-governance.sh)` |
| `config` (value = none) † | `plain briefs — your standing choice (change anytime: set-governance.sh)` |
| `config-auto-probe` | `follow each repo — this repo has <tool>, so <tool> docs` / † `follow each repo — no doc tool here, so plain briefs` |
| `env` | `<style> — set by RECON_GOVERNANCE for this run only` († phrase style without naming the tool when resolved to none) |
| `probe-absent` † | `plain briefs — no doc tool in this repo` |
| `env-decree-but-unavailable`, `config-decree-but-unavailable` † | `plain briefs this run — your chosen doc tool is not usable in this repo (CLI or its config file missing; see the script's evidence line)` |

---

## Reference

- READY Jira delivery: after an approved package, this stage renders and stages the final dossier, comment, and bundle, then uses a second explicit gate to post one marker comment plus two replacement attachments. Full Discovery detail remains in the dossier and ZIP, not the short comment.
- Decision language ban: discovery output uses "candidate", "reference", "OPEN"; the only path decisions it relays are `route/routing.yaml` fields authored by the routing stage.
- Conflict guardrail template: "PR #N (TICKET) modifies <file>; rebase whichever lands second, rerun the component tests."
- Whole-chain spec (stages, invariants, artifact registry, trigger table): `../../docs/pipeline.md` relative to this skill's base directory. On conflict, this SKILL.md wins.
