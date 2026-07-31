---
description: Stage 1 code discovery and governance routing for a READY ticket. Use after recon-triage returns READY, or when asked to prepare a ticket for planning, decree routing, or a SPEC.
---

# Recon Discovery

Maps the code surface for a triaged-READY ticket, writes an evidence-backed behavior contract, and routes it deterministically into decree (amend-spec / new-spec / prd-chain). Ends at the human approval gate — never at code.

## Contract

- **Input:** ticket ID (precondition: `~/.claude/recon/<TICKET>/triage.yaml` with `disposition: READY`)
- **Reads:** the target repo (read-only), `decree why` / `decree intent-check` output
- **Writes:** `~/.claude/recon/<TICKET>/{discovery.md, routing.yaml, spec-draft.md}` (plus `decree index rebuild` refreshing decree's own index)
- **External side effects:** NONE. Never posts to Jira without explicit user approval; after the gate it PRINTS handoff commands, never executes them.
- **May invoke:** `recon:recon-repro` (OPEN scenarios about visible UI), `recon:recon-triage` (missing or stale triage)

---

## ⚠️ CRITICAL: Rules

1. **Precondition:** `~/.claude/recon/<TICKET>/triage.yaml` MUST exist with `disposition: READY`. If missing or not READY, invoke the `recon:recon-triage` skill first — NEVER skip triage.
2. **READ-ONLY on the repo.** Writes go only to `~/.claude/recon/<TICKET>/`. You MUST NOT implement, branch, or edit code — discovery ends at the approval gate.
3. **No prose unknowns.** Every "unknown" MUST be either resolved by running a command, or converted into a question with a named owner. "It is not yet known whether…" is a forbidden sentence.
4. **Every claim carries evidence** — `file:line` or command output. A responsibility map without line numbers is not done.
5. **Routing MUST come from the policy table below**, emitted as `routing.yaml` with `matched_rule` AND `rules_not_matched` (with reasons). NEVER route by feel.
6. **The approval gate is mandatory.** Present the package via AskUserQuestion (including any OPEN scenario decisions) and STOP after approval with printed handoff commands. Implementation belongs to a different session.
7. **Human-facing questions MUST be concrete.** Gate questions and OPEN scenarios must be answerable without reading code: numbered repro steps from a stated start state (e.g. the project's mock-mode dev command, which page), concrete entity names from the running system, before/after state, and options phrased as user-observable outcomes ("the tab appears and becomes selected"), never code outcomes ("activeTab is set"). Internal identifiers are BANNED from question text — they belong in the evidence tables, not the question. If an OPEN scenario concerns observable UI behavior, invoke the `recon:recon-repro` skill to attach visual evidence BEFORE presenting the gate.
8. **NEVER post to Jira without explicit approval in this session** — same rule as triage. Discovery normally posts nothing; if a short status comment is ever warranted, draft it, ask via AskUserQuestion, and POST only on an explicit yes.

---

## Workflow

### 1. Load context

Read `triage.yaml` (ticket, task_class, conflicts). Confirm you are in the repo the ticket targets.

### 2. Map the code surface

- Locate the owning component/service for the affected behavior (Grep/Glob; serena/LSP when available). Record every claim as `file:line`.
- Find the **existing contract to reuse**: is there already a service method/transition that does what the ticket needs? (`reuses_existing_contract: true/false` — this drives routing.)
- Identify the test surface: existing test files, or the new test file the change needs.
- **Edge-case scan:** for the affected UI surface, list what *renders* the data vs what *consumes* the resulting state. Mismatches (e.g. a panel rendering ALL items while the consumer handles only VISIBLE ones) are edge-case candidates — each becomes an OPEN Gherkin scenario, never a silent assumption.

### 3. Write the behavior contract

Gherkin scenarios in `discovery.md`: the required behavior, the must-not-change behaviors (regression scenarios), and any **OPEN scenarios** from the edge-case scan, each with 2–3 labeled options (A/B/C). Option labels describe user-observable outcomes (rule 7), never internal state.

### 4. Run the deterministic governance checks

```bash
decree index rebuild        # ALWAYS first — `decree why` fails on a stale index
decree why <candidate files>
decree intent-check --plan "<one-line candidate plan>" --files <candidate files>
```

If the `decree` CLI is not installed or the repo has no `decree.toml`, record `governance: none` and route with rule 1 unavailable — do not treat this as an error.

### 5. Route via the policy table (top-down, first match wins)

| Rule | Condition | Route | ddd entry |
|---|---|---|---|
| 0 | No behavior contract possible (you cannot write a Gherkin scenario: copy fix, dead code, dep bump) | `no-doc` — implement directly, ticket ref in commit | — |
| 1 | All candidate files governed by a SPEC in non-terminal status | `amend-spec` — add criteria checkboxes to that SPEC | Phase 4 |
| 2 | Ungoverned + defect + no open product decision + reuses existing contract + small blast radius | `new-spec` — small SPEC, criteria from the Gherkin, `governs:` the files | Phase 3 |
| 3 | New capability, or product decision involved, or `reuses_existing_contract: false` (new state/dependency/pattern = a real choice exists) | `prd-chain` — PRD (+ ADR if options exist) then SPEC | Phase 0/1 |
| E | Facts conflict (two SPECs govern different halves; governing SPEC is terminal/implemented) | `escalate` — present both options at the gate with evidence | user decides |

Write `routing.yaml`:

```yaml
routing:
  route: no-doc | amend-spec | new-spec | prd-chain | escalate
  matched_rule: <0|1|2|3|E>
  target: <SPEC id or null>
  ddd_entry: <phase or null>
  open_scenario_decisions: <n>
  evidence:
    intent_check: "<verbatim key lines>"
    task_class: "<from triage>"
    product_decision_open: <bool>
    reuses_existing_contract: "<file:line of the contract, or false>"
    blast_radius: "<n change files + n test files>"
  rules_not_matched:
    rule_X: "<one-line reason>"
```

### 6. Draft the next document

For `new-spec` / `amend-spec`: write `spec-draft.md` — frontmatter (`governs:`, ticket link), Overview, **acceptance criteria as checkboxes derived 1:1 from the Gherkin scenarios**, technical design (the wiring, in ≤10 lines, naming the contract to reuse), and integration guardrails (conflicts from triage). For `prd-chain`: draft the PRD problem statement instead.

### 7. The approval gate

If any OPEN scenario concerns visible UI behavior, invoke the `recon:recon-repro` skill first and reference its numbered steps + screenshots in the question (rule 7).

Present via AskUserQuestion:
- One question per OPEN scenario decision (options A/B/C with a recommendation).
- One question for the package itself: `Approve / Edit / Reject`.

**NEVER proceed past a Reject.** On Edit, apply the edits to the artifacts and re-present.

### 8. Handoff (after approval — print, don't execute)

```
Next:
→ decree new spec "<title>"        # fill from spec-draft.md, then decree lint
→ /decree:ddd                      # will report Phase <n> and drive implementation
→ implementation session brief: ~/.claude/recon/<TICKET>/spec-draft.md
```

---

## Report

Print:

```
Wrote: ~/.claude/recon/<TICKET>/discovery.md, routing.yaml, spec-draft.md
Route: <route> (rule <n>) → ddd <phase>
Open decisions resolved at gate: <n>
Next: <handoff commands above>
```

---

## Reference

- Line budget: anything posted to Jira from this stage is ≤15 lines with a link/reference to the artifacts; the full discovery never gets pasted into a ticket comment.
- Decision language ban: discovery output uses "candidate", "reference", "OPEN"; the only decisions it states are `routing.yaml` fields backed by the table.
- Conflict guardrail template: "PR #N (TICKET) modifies <file>; rebase whichever lands second, rerun the component tests."
