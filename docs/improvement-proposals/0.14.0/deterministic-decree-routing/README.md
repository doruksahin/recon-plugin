# Apply Decree routing with a total decision rail

> Apply Decree routes from typed facts with a total, mechanically tested decision table

- **Status:** proposed — deferred until a company policy owner defines the
  missing route semantics
- **Priority:** P1
- **Theme:** determinism rail
- **Origin:** Static routing audit on 2 Aug 2026 found a valid discovery fact
  combination that matches no rule and an undefined "small blast radius" predicate.

## Problem

`pipeline.md` classifies "routing policy table, first match wins" as a rail, but
`recon-decree` asks the model to interpret the table and hand-author
`route/routing.yaml`. The same evidence can therefore route differently across
models. Worse, the table is not total: an ungoverned defect with scenarios, no
open product decision, an existing reusable contract, and a large blast radius
matches neither rule 2 nor rule 3.

This route determines whether a developer implements directly, writes a SPEC, or
opens a PRD chain. Variance here changes the company's delivery process, not just
wording.

## Before (today)

```text
facts: scenarios=3, governed=false, task_class=defect
       product_decision_open=false, reuses_existing_contract=true
       blast_radius="8 change files + 4 test files"

rule 0: no — scenarios exist
rule 1: no — files are ungoverned
rule 2: ?  — "small" has no threshold
rule 3: no — no new capability/decision/contract
rule E: no — facts do not conflict
result: no defined route; the model must improvise
```

Nothing fails if one session chooses `new-spec` and another chooses `prd-chain`.

## After (proposed)

Discovery writes governance-neutral routing inputs, the adapter adds Decree
coverage facts, and one route command owns the complete policy:

```yaml
routing_input:
  scenarios: 3
  task_class: defect
  product_decision_open: false
  reuses_existing_contract: true
  change_files: 8
  test_files: 4
```

```text
$ recon route decree ATT-6000
route: escalate (rule E-policy-gap)
reason: no approved rule maps an ungoverned reusable-contract defect of this scope
next: policy owner chooses new-spec or prd-chain; choice is recorded at the gate
```

Until the company approves the missing policy, unmatched facts fail closed to an
explicit gate instead of being improvised. Success means every named policy
fixture produces one route or a named escalation, invalid inputs fail, and the
same input fixture produces byte-identical YAML.

## Implementation sketch

- Add governance-neutral routing inputs owned by discovery; Decree coverage,
  target SPEC, mixed-governance, and terminal-status facts stay inside the adapter.
- Add a Decree routing engine behind *route-decree.sh*; policy predicates use
  explicit numeric values or named enums, never adjectives.
- Generate `matched_rule`, `rules_not_matched`, `brief_kind`, and `handoff` from
  the chosen rule; the model writes none of them.
- Add table fixtures for every named rule plus the previously unmatched
  large-defect case, mixed governed/ungoverned files, multiple governing SPECs,
  and terminal governing SPECs.
- Shrink `recon-decree` to evidence collection plus one route command.

## Open questions

- Which semantic facts—not raw file count—separate a local contract change from a
  product-requirements decision? Until a policy owner answers, use escalation.
