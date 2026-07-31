---
description: Decree governance adapter for the recon pipeline — routes a discovered ticket into decree (no-doc / amend-spec / new-spec / prd-chain) via the policy table. Invoked by recon-discovery when governance resolves to decree; not a user entry point.
---

# Recon Decree (governance adapter)

The decree adapter of the recon pipeline's routing stage. Consumes discovery's behavior contract, runs the decree CLI checks, routes via the policy table, and writes `route/routing.yaml` — including the handoff as verbatim data. **All decree vocabulary in the pipeline lives in this skill and its outputs**; a developer whose governance resolves to `none` never loads this file.

## Contract

- **Input:** ticket ID (preconditions: `discovery/discovery.md` exists; governance resolved to `decree` by `scripts/detect-governance.sh`)
- **Reads:** the target repo (read-only), `discovery/` artifacts, `decree` CLI output
- **Writes:** ONLY inside `~/.claude/recon/<TICKET>/route/` — `routing.yaml`, `aux-intent-check.txt` (raw CLI output). Create the directory before your first write. Anything else fails `lint-workspace.sh`.
- **Local side effects:** `decree index rebuild` (refreshes decree's own index)
- **External side effects:** NONE. Never posts anywhere; never executes its own handoff.
- **Invoked by:** `recon:recon-discovery` (adapter convention: skill name = `recon-<governance>`). Do not invoke directly unless re-routing an existing discovery.

---

## ⚠️ CRITICAL: Rules

1. **READ-ONLY on the repo.** You MUST NOT implement, branch, or edit code.
2. **Routing MUST come from the policy table below** — emitted with `matched_rule` AND `rules_not_matched` (one-line reason each). NEVER route by feel.
3. **Every claim carries evidence** — CLI output, `file:line`, or a fact from `discovery/` artifacts. Raw `decree intent-check` output is saved to `route/aux-intent-check.txt` so the verdict is auditable.
4. **The handoff is data.** Write the route's exact next commands into `routing.yaml`'s `handoff:` block. Consumers (discovery's report, the dossier) quote it verbatim — never compose handoff prose anywhere else.
5. **NEVER read archived runs** (`runs/` — pipeline invariant 3).
6. **Record `repo_commit`** (`git rev-parse HEAD`) — it pins every `file:line` claim.

---

## Workflow

### 1. Load context

Read `triage/triage.yaml` (task_class) and `discovery/discovery.md` (the contract; OPEN scenarios count). Confirm you are in the repo the ticket targets. `mkdir -p ~/.claude/recon/<TICKET>/route`.

### 2. Run the decree checks

```bash
decree index rebuild        # ALWAYS first — `decree why` fails on a stale index
decree why <candidate files>
decree intent-check --plan "<one-line candidate plan>" --files <candidate files> \
  | tee ~/.claude/recon/<TICKET>/route/aux-intent-check.txt
```

If the `decree` CLI errors or the repo has no `decree.toml`, STOP and report it — governance resolved to `decree`, so a broken decree setup is a finding for the user, not something to silently route around.

### 3. Route via the policy table (top-down, first match wins)

| Rule | Condition | Route | ddd entry |
|---|---|---|---|
| 0 | No behavior contract possible (`discovery.md` has no scenarios: copy fix, dead code, dep bump) | `no-doc` — implement directly, ticket ref in commit | — |
| 1 | All candidate files governed by a SPEC in non-terminal status | `amend-spec` — add criteria checkboxes to that SPEC | Phase 4 |
| 2 | Ungoverned + defect + no open product decision + reuses existing contract + small blast radius | `new-spec` — small SPEC, criteria from the Gherkin, `governs:` the files | Phase 3 |
| 3 | New capability, or product decision involved, or `reuses_existing_contract: false` (new state/dependency/pattern = a real choice exists) | `prd-chain` — PRD (+ ADR if options exist) then SPEC | Phase 0/1 |
| E | Facts conflict (two SPECs govern different halves; governing SPEC is terminal/implemented) | `escalate` — present both options at the gate with evidence | user decides |

### 4. Write `route/routing.yaml`

```yaml
routing:
  route: no-doc | amend-spec | new-spec | prd-chain | escalate
  matched_rule: <0|1|2|3|E>
  governance: decree
  governance_source: "<from detect-governance.sh>"
  target: <SPEC id or null>
  ddd_entry: <phase or null>
  brief_kind: implementation-brief | problem-statement | none   # none only for no-doc
  target_governs: []          # files the new/amended SPEC must list under governs:
  evidence:
    intent_check: "<verbatim key lines — full output in aux-intent-check.txt>"
    task_class: "<from triage>"
    product_decision_open: <bool>
    reuses_existing_contract: "<file:line of the contract, or false>"
    blast_radius: "<n change files + n test files>"
    repo_commit: "<git rev-parse HEAD>"
  rules_not_matched:
    rule_X: "<one-line reason>"
  handoff: |
    <the matched route's block below, verbatim, with <TICKET> substituted>
```

`brief_kind`: `prd-chain` → `problem-statement`; `no-doc` → `none`; all other routes → `implementation-brief`.

Handoff blocks (write the matching one into `handoff:`):

**new-spec**
```
→ decree new spec "<title>"        # fill from discovery/spec-draft.md (add governs: from target_governs), then decree lint
→ /decree:ddd                      # picks up at Phase 3 and drives implementation
→ implementation brief: ~/.claude/recon/<TICKET>/discovery/spec-draft.md
```

**amend-spec**
```
→ add the acceptance-criteria checkboxes from discovery/spec-draft.md to <SPEC-id>
  (extend its governs: with target_governs if not covered), then decree lint
→ /decree:ddd                      # picks up at Phase 4 — the new unchecked items
```

**prd-chain**
```
→ /decree:prd                      # problem statement already drafted in ~/.claude/recon/<TICKET>/discovery/
→ /decree:ddd                      # drives Phase 1→2→3 from there
```

**no-doc**
```
→ implement directly; reference <TICKET> in the commit message
```

**escalate** — no handoff of its own: after the gate selects a route, rewrite `routing.yaml` with the chosen route's block.

---

## Report

Print (control returns to recon-discovery, which continues with the brief, repro triggers, and the gate):

```
Wrote: ~/.claude/recon/<TICKET>/route/{routing.yaml, aux-intent-check.txt}
Route: <route> (rule <n>) → ddd <phase|—>
Lint: <run `bash "<skill base dir>/../../scripts/lint-workspace.sh" <TICKET>` — quote its verdict line>
```

---

## Reference

- Whole-chain spec (stages, invariants, artifact registry, trigger table): `../../docs/pipeline.md` relative to this skill's base directory. On conflict, this SKILL.md wins.
- Decision language: routing states only `routing.yaml` fields backed by the table; "candidate", "reference", "OPEN" elsewhere.
- Adapter convention: the routing stage invokes the skill named `recon-<governance>`. A future governance system means a sibling adapter skill with this same contract — same inputs, same `route/routing.yaml` shape, its own vocabulary quarantined the same way.
