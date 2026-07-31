---
description: Stage 1 code discovery for a READY ticket — behavior contract, routing (via the governance adapter or the generic rail), implementer brief, approval gate. Use after recon-triage returns READY, or when asked to prepare a ticket for planning or implementation.
---

# Recon Discovery

Maps the code surface for a triaged-READY ticket, writes an evidence-backed behavior contract, has the routing stage decide the implementation path, drafts the brief, and ends at the human approval gate — never at code.

## Contract

- **Input:** ticket ID (precondition: `~/.claude/recon/<TICKET>/triage/triage.yaml` with `disposition: READY`)
- **Reads:** the target repo (read-only), current-run artifacts in `~/.claude/recon/<TICKET>/` (never `runs/`), `route/routing.yaml` after the routing stage runs
- **Writes:** ONLY inside `~/.claude/recon/<TICKET>/discovery/` — `discovery.md`, `spec-draft.md`, `gate.yaml`. Create the directory before your first write — a stage directory existing means that stage ran. Anything else fails `lint-workspace.sh`.
- **External side effects:** NONE. Never posts to Jira without explicit user approval; after the gate it PRINTS the handoff verbatim from `routing.yaml`, never executes it.
- **May invoke:** `recon:recon-repro` (primary scenario of UI defects + OPEN scenarios about visible UI), `recon:recon-triage` (missing or stale triage), and the governance adapter skill named by convention `recon:recon-<governance>` (only when governance resolves to something other than `none`)

---

## ⚠️ CRITICAL: Rules

1. **Precondition:** `~/.claude/recon/<TICKET>/triage/triage.yaml` MUST exist with `disposition: READY`. If missing or not READY, invoke the `recon:recon-triage` skill first — NEVER skip triage.
2. **READ-ONLY on the repo.** Writes go only to `~/.claude/recon/<TICKET>/discovery/`. You MUST NOT implement, branch, or edit code — discovery ends at the approval gate.
3. **No prose unknowns.** Every "unknown" MUST be either resolved by running a command, or converted into a question with a named owner. "It is not yet known whether…" is a forbidden sentence.
4. **Every claim carries evidence** — `file:line` or command output. A responsibility map without line numbers is not done.
5. **Routing is consumed, never composed.** The route comes from the routing stage — `scripts/route-generic.sh` (a rail) or the governance adapter skill — as `route/routing.yaml`. NEVER route by feel, NEVER edit `routing.yaml`, and quote its `handoff:` block VERBATIM wherever the handoff is shown. Discovery's authority ends at describing; the routing stage decides the path.
6. **Governance is the developer's choice, resolved mechanically.** Run `scripts/detect-governance.sh` (the ladder: env > config > probe); on `undecided`, ask the one-time question (step 4) and persist the answer via `scripts/set-governance.sh` — NEVER decide silently, NEVER let detection alone opt a developer in. When governance resolves to `none`, governance-system vocabulary is BANNED from every artifact and printed line (`lint-workspace.sh` greps for it).
7. **Human-facing questions MUST be concrete.** Gate questions and OPEN scenarios must be answerable without reading code: numbered repro steps from a stated start state (e.g. the project's mock-mode dev command, which page), concrete entity names from the running system, before/after state, and options phrased as user-observable outcomes ("the tab appears and becomes selected"), never code outcomes ("activeTab is set"). Internal identifiers are BANNED from question text — they belong in the evidence tables, not the question. If an OPEN scenario concerns observable UI behavior, invoke the `recon:recon-repro` skill to attach visual evidence BEFORE presenting the gate.
8. **NEVER post to Jira without explicit approval in this session** — same rule as triage. Discovery normally posts nothing; if a short status comment is ever warranted, draft it, ask via AskUserQuestion, and POST only on an explicit yes.
9. **NEVER read archived runs.** `~/.claude/recon/<TICKET>/runs/` holds artifacts from prior runs (possibly produced by older skill versions) — you MUST NOT open, list, or cite anything under it. Consume only the current-run stage directories (`triage/`, `route/`, `repro/`, …); a current run is one whose root `meta.yaml` exists alongside `triage/triage.yaml`.
10. **UI defects get a primary-scenario repro — mechanically, not by judgment call.** The trigger is a condition, not a vibe: `task_class: defect` AND the affected surface is visible UI AND `routing.route` is not a trivial-direct route (`direct` / `no-doc`) → invoke `recon:recon-repro` for the bug itself BEFORE the gate (step 7). No implementer may receive a UI-defect brief without a reproduce-the-bug path in it.

---

## Workflow

### 1. Load context

Read `triage/triage.yaml` (ticket, task_class, conflicts). Confirm you are in the repo the ticket targets. Create your stage directory: `mkdir -p ~/.claude/recon/<TICKET>/discovery`.

### 2. Map the code surface

- Locate the owning component/service for the affected behavior (Grep/Glob; serena/LSP when available). Record every claim as `file:line`.
- Find the **existing contract to reuse**: is there already a service method/transition that does what the ticket needs? (`reuses_existing_contract: true/false` — the routing stage consumes this.)
- Identify the test surface: existing test files, or the new test file the change needs.
- **Edge-case scan:** for the affected UI surface, list what *renders* the data vs what *consumes* the resulting state. Mismatches (e.g. a panel rendering ALL items while the consumer handles only VISIBLE ones) are edge-case candidates — each becomes an OPEN Gherkin scenario, never a silent assumption.

### 3. Write the behavior contract

Gherkin scenarios in `discovery.md`: the required behavior, the must-not-change behaviors (regression scenarios), and any **OPEN scenarios** from the edge-case scan, each with 2–3 labeled options (A/B/C). Option labels describe user-observable outcomes (rule 7), never internal state. If the change genuinely admits no scenario (copy fix, dead code, dep bump), say so in `discovery.md` and write none — the routing rail reads that fact.

### 4. Resolve governance (rail + at most one one-time question)

```bash
bash "<skill base dir>/../../scripts/detect-governance.sh"   # run from the repo
```

- `governance: none` or a concrete adapter → proceed to step 5 with the printed `source`.
- `governance: undecided` (a governance tool is present but the developer never chose) → AskUserQuestion, once, ever:
  - *"<tool from the script's evidence line> is set up in this repo — route recon runs through it?"* Options: `Use it` / `Don't use it` / `Per repo (auto)`.
  - Persist: `bash "<skill base dir>/../../scripts/set-governance.sh" <the tool's name | none | auto>` — then re-run `detect-governance.sh`; it now resolves from config, forever.

### 5. Route (the routing stage — never done by hand)

- **`governance: none`** → `bash "<skill base dir>/../../scripts/route-generic.sh" <TICKET> <source>` — a pure rail: 0 scenarios in `discovery.md` → `direct`, otherwise `brief`.
- **anything else** → invoke the adapter skill `recon:recon-<governance>` (Skill tool); it runs its checks and writes `route/routing.yaml` itself.

Then read back `route/routing.yaml` and note three fields for the rest of the run: `route`, `brief_kind`, `handoff`.

### 6. Draft the brief (per `brief_kind` — a field, not a judgment)

- `none` → no brief; skip to step 7.
- `implementation-brief` → write `spec-draft.md`: ticket link, Overview, **acceptance criteria as checkboxes derived 1:1 from the Gherkin scenarios**, technical design (the wiring, in ≤10 lines, naming the contract to reuse), integration guardrails (conflicts from triage), and a **Manual verification** section: the start state and numbered steps copied verbatim from `repro/repro.md`, buggy outcome marked BEFORE, expected outcome marked AFTER. If no `repro.md` exists (non-UI surface, or a mock gap blocked it), the section states why and what environment verification needs — it is never omitted. The implementer must be able to reach the affected surface without reading anything beyond this draft.
- `problem-statement` → write `spec-draft.md` as a problem statement instead: context, current behavior with evidence, desired outcome, and the open choices — the downstream document named in the handoff starts from it.

### 7. The approval gate

Invoke the `recon:recon-repro` skill BEFORE the gate when either condition holds (evaluate both; they are mechanical, not judgment calls):

- **Primary scenario (rule 10):** `task_class: defect` AND visible UI surface AND `route` ∉ {`direct`, `no-doc`} → repro the bug itself. Its screenshots are the gate's evidence and the PR's "before" half.
- **OPEN scenarios (rule 7):** any OPEN scenario concerns observable UI behavior → repro it and reference the numbered steps + screenshots in the question.

One repro session covers both when the scenarios share a start state — don't boot the dev server twice.

Present via AskUserQuestion:
- One question per OPEN scenario decision (options A/B/C with a recommendation).
- One question for the package itself: `Approve / Edit / Reject`.

**NEVER proceed past a Reject.** Record the outcome in `discovery/gate.yaml`:

```yaml
gate:
  approved: true | false
  date: YYYY-MM-DD
  open_scenario_resolutions: {}   # {scenario_key: "<chosen option> — <user-observable summary>"}
  rejected: "<user's reason — only present on Reject>"
```

On Edit, apply the edits to the artifacts and re-present. On Reject: write `approved: false` + `rejected`, then print `Next: fix what the rejection names and re-run /recon:recon-discovery <TICKET>; if the ticket itself is wrong, re-run /recon:recon-triage <TICKET> or raise it with the reporter` — and STOP.

### 8. Handoff (after approval — print, don't execute)

Print `route/routing.yaml`'s `handoff:` block **verbatim** under a `Next:` line. Nothing is added, reworded, or dropped — the routing stage authored it; discovery only relays it.

---

## Report

Print:

```
Wrote: ~/.claude/recon/<TICKET>/discovery/{discovery.md, spec-draft.md, gate.yaml}
Route: <route> (rule <matched_rule>, governance: <governance>/<governance_source>) — see route/routing.yaml
Lint: <run `bash "<skill base dir>/../../scripts/lint-workspace.sh" <TICKET>` — quote its verdict line; fix any violation before reporting>
Open decisions resolved at gate: <n>
Next: <routing.yaml handoff, verbatim | rejected — reason recorded in gate.yaml, re-run instructions above>
Optional: /recon:recon-report <TICKET> — shareable HTML dossier of this run (private artifact)
```

---

## Reference

- Line budget: anything posted to Jira from this stage is ≤15 lines with a link/reference to the artifacts; the full discovery never gets pasted into a ticket comment.
- Decision language ban: discovery output uses "candidate", "reference", "OPEN"; the only path decisions it relays are `route/routing.yaml` fields authored by the routing stage.
- Conflict guardrail template: "PR #N (TICKET) modifies <file>; rebase whichever lands second, rerun the component tests."
- Whole-chain spec (stages, invariants, artifact registry, trigger table): `../../docs/pipeline.md` relative to this skill's base directory. On conflict, this SKILL.md wins.
