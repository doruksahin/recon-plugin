---
name: recon-discovery
description: Stage 1 code discovery for a READY ticket — behavior contract, routing (via the governance adapter or the generic rail), implementer brief, approval gate. Use after recon-triage returns READY, or when asked to prepare a ticket for planning or implementation.
---

# Recon Discovery

Maps the code surface for a triaged-READY ticket, writes an evidence-backed behavior contract, has the routing stage decide the implementation path, drafts the brief, and ends at the human approval gate — never at code.

## Host setup

Before the first path or tool action, read `../../docs/hosts.md`. Resolve the
absolute workspace root, host, and surface with `reconctl.sh`; inspect
`capabilities`, then run `reconctl.sh preflight base`. Retain the printed values
for the run. A failed preflight is a hard STOP. Do not change any gate or
evidence rule.

## Contract

- **Input:** ticket ID (precondition: `$RECON_ROOT/<TICKET>/triage/triage.yaml` with `disposition: READY`)
- **Reads:** the target repo (read-only), current-run artifacts in `$RECON_ROOT/<TICKET>/` (never `runs/`), `route/routing.yaml` after the routing stage runs
- **Writes:** ONLY inside `$RECON_ROOT/<TICKET>/discovery/` — `discovery.md`, `spec-draft.md`, `gate.yaml`. Create the directory before your first write — a stage directory existing means that stage ran. Anything else fails `lint-workspace.sh`.
- **External side effects:** NONE. Never posts to Jira without explicit user approval; after the gate it PRINTS the handoff verbatim from `routing.yaml`, never executes it.
- **May invoke:** `recon:recon-repro` (primary scenario of UI defects + OPEN scenarios about visible UI), `recon:recon-triage` (missing or stale triage), and the governance adapter skill named by convention `recon:recon-<governance>` (only when governance resolves to something other than `none`)

---

## ⚠️ CRITICAL: Rules

1. **Precondition:** `$RECON_ROOT/<TICKET>/triage/triage.yaml` MUST exist with `disposition: READY`. If missing or not READY, invoke the `recon:recon-triage` skill first — NEVER skip triage.
2. **READ-ONLY on the repo.** Writes go only to `$RECON_ROOT/<TICKET>/discovery/`. You MUST NOT implement, branch, or edit code — discovery ends at the approval gate.
3. **No prose unknowns.** Every "unknown" MUST be either resolved by running a command, or converted into a question with a named owner. "It is not yet known whether…" is a forbidden sentence.
4. **Every claim carries evidence** — `file:line` or command output. A responsibility map without line numbers is not done.
5. **Routing is consumed, never composed.** The route comes from the routing stage — `scripts/route-generic.sh` (a rail) or the governance adapter skill — as `route/routing.yaml`. NEVER route by feel, NEVER edit `routing.yaml`, and quote its `handoff:` block VERBATIM wherever the handoff is shown. Discovery's authority ends at describing; the routing stage decides the path.
6. **Governance is the developer's choice, resolved mechanically.** Run `scripts/detect-governance.sh` (the ladder: env > config > probe); on `undecided`, ask the one-time question (step 4) and persist the answer via `scripts/set-governance.sh` — NEVER decide silently, NEVER let detection alone opt a developer in. When governance resolves to `none`, governance-system vocabulary is BANNED from every artifact and printed line (`lint-workspace.sh` greps for it).
7. **Human-facing questions MUST be concrete.** Gate questions and OPEN scenarios must be answerable without reading code: numbered repro steps from a stated start state (e.g. the project's mock-mode dev command, which page), concrete entity names from the running system, before/after state, and options phrased as user-observable outcomes ("the tab appears and becomes selected"), never code outcomes ("activeTab is set"). Internal identifiers are BANNED from question text — they belong in the evidence tables, not the question. If an OPEN scenario concerns observable UI behavior, invoke the `recon:recon-repro` skill to attach visual evidence BEFORE presenting the gate.
8. **NEVER post to Jira without explicit approval in this session** — same rule as triage. Discovery normally posts nothing; if a short status comment is ever warranted, draft it, ask via the host-native user interaction (see hosts.md), and POST only on an explicit yes.
9. **NEVER read archived runs.** `$RECON_ROOT/<TICKET>/runs/` holds artifacts from prior runs (possibly produced by older skill versions) — you MUST NOT open, list, or cite anything under it. Consume only the current-run stage directories (`triage/`, `route/`, `repro/`, …); a current run is one whose root `meta.yaml` exists alongside `triage/triage.yaml`.
10. **UI defects get a primary-scenario repro — mechanically, not by judgment call.** The trigger is a condition, not a vibe: `task_class: defect` AND the affected surface is visible UI AND `routing.route` is not a trivial-direct route (`direct` / `no-doc`) → invoke `recon:recon-repro` for the bug itself BEFORE the gate (step 7). No implementer may receive a UI-defect brief without a reproduce-the-bug path in it.

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

Gherkin scenarios in `discovery.md`: the required behavior, the must-not-change behaviors (regression scenarios), and any **OPEN scenarios** from the edge-case scan, each with 2–3 labeled options (A/B/C). Option labels describe user-observable outcomes (rule 7), never internal state. If the change genuinely admits no scenario (copy fix, dead code, dep bump), say so in `discovery.md` and write none — the routing rail reads that fact.

### 4. Resolve the handoff style (rail + at most one one-time question)

Internally this is the `governance` setting; every USER-FACING word about it describes what the developer gets — the **handoff style** — never the machinery. Rule 7's concreteness applies to the pipeline's own questions exactly as it does to Jira asks: options are outcomes, not config values.

```bash
bash "<skill base dir>/../../scripts/detect-governance.sh"   # run from the repo
```

- `governance: none` or a concrete adapter → proceed to step 5 with the printed `source`.
- `governance: undecided` (a doc tool is present but the developer never chose) → ask once via the host-native user interaction in `hosts.md`. Take the tool's name from the script's evidence line and ask:
  - *"This repo has <tool> set up. When a ticket is approved, how should recon hand off the work?"*
    - **Write <tool> docs (Recommended)** — approved tickets route into this repo's <tool> flow (the handoff prints its commands)
    - **Plain briefs** — approved tickets end at a standalone implementation brief; <tool> is never involved and its vocabulary never appears
    - **Follow each repo** — <tool> docs wherever a repo has it set up, plain briefs everywhere else
  - Persist the mapped value — docs → the tool's name, plain briefs → `none`, follow each repo → `auto`: `bash "<skill base dir>/../../scripts/set-governance.sh" <the tool's name | none | auto>` — then re-run `detect-governance.sh`; it now resolves from config and the question never fires again (change it anytime by re-running `set-governance.sh`).

### 5. Route (the routing stage — never done by hand)

- **`governance: none`** → `bash "<skill base dir>/../../scripts/route-generic.sh" <TICKET> <source>` — a pure rail: 0 scenarios in `discovery.md` → `direct`, otherwise `brief`.
- **anything else** → invoke the adapter skill `recon:recon-<governance>` (host-native skill invocation; see hosts.md); it runs its checks and writes `route/routing.yaml` itself.

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

Present via the host-native user interaction (see hosts.md):
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

On Edit, apply the edits to the artifacts and re-present. On Reject: write
`approved: false` + `rejected`; render the Discovery and Triage invocations
with `reconctl.sh invocation`, print `Next: fix what the rejection names and
run <Discovery invocation> again; if the ticket itself is wrong, run <Triage
invocation> or raise it with the reporter` — and STOP.

Whenever `gate.yaml` is written (approve OR reject), log it (invariant 16):

```bash
bash "<skill base dir>/../../scripts/log-event.sh" <TICKET> gate_answered approved=<true|false>
```

### 8. Handoff (after approval — print, don't execute)

Print `route/routing.yaml`'s `handoff:` block **verbatim** under a `Next:` line. Nothing is added, reworded, or dropped — the routing stage authored it; discovery only relays it. Then log `bash "<skill base dir>/../../scripts/log-event.sh" <TICKET> handoff_printed` (invariant 16).

---

## Report

If `$RECON_ROOT/<TICKET>/state/artifact-url` exists (mechanical check: `find` it), invoke the `recon:recon-state` skill first — the gate was just answered (or presented), so the ticket's canvas must be refreshed (no gate; the URL already exists).

Print:

```
Wrote: $RECON_ROOT/<TICKET>/discovery/{discovery.md, spec-draft.md, gate.yaml}
Route: <route> (rule <matched_rule>) — see route/routing.yaml
Handoff style: <plain-words line from the table below> (governance: <governance>/<source>)
Lint: <run `bash "<skill base dir>/../../scripts/lint-workspace.sh" <TICKET>` — quote its verdict line; fix any violation before reporting>
Open decisions resolved at gate: <n>
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

- No Jira posting: this stage never posts to Jira — delivery to the ticket belongs to triage's posting path; the full discovery never gets pasted into a ticket comment.
- Decision language ban: discovery output uses "candidate", "reference", "OPEN"; the only path decisions it relays are `route/routing.yaml` fields authored by the routing stage.
- Conflict guardrail template: "PR #N (TICKET) modifies <file>; rebase whichever lands second, rerun the component tests."
- Whole-chain spec (stages, invariants, artifact registry, trigger table): `../../docs/pipeline.md` relative to this skill's base directory. On conflict, this SKILL.md wins.
