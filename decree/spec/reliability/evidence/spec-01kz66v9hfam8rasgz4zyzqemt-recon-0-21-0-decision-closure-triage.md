---
date: '2026-08-04'
governs:
- recon/skills/recon-triage/SKILL.md
- recon/skills/CLAUDE.md
- recon/scripts/triage-tools.py
- recon/scripts/CLAUDE.md
- recon/docs/pipeline.md
- recon/docs/registry.yaml
- recon/docs/workspace-index.md
- tools/test-triage-verifier.sh
- tools/test-replay-lab.sh
- tools/test-replay-lab-report.sh
- tools/replay-ticket.py
- tools/render-replay-lab-report.py
- tools/check-coherence.sh
- tools/CLAUDE.md
- docs/flow.html
- docs/replay-lab-report.html
- docs/improvement-proposals/0.21.0/README.md
- docs/improvement-proposals/0.21.0/decision-closure-triage/README.md
- docs/improvement-proposals/README.md
- docs/plans/2026-08-04-decision-closure-triage.md
- evals/README.md
- evals/skills/recon-replay-lab/SKILL.md
- evals/skills/recon-replay-lab/references/handoffs.md
- evals/cases/att-4845-pre-comment/oracle/decisions.json
- evals/cases/att-4845-pre-comment/fixtures/atomic-pass.yaml
- evals/cases/att-4845-pre-comment/fixtures/combined-layout-fail.yaml
id: SPEC-01KZ66V9HFAM8RASGZ4ZYZQEMT
references:
- ADR-01KZ0ZK4WYVWRY0WJM2CZ7ZS8C
status: implemented
---

# SPEC-01KZ66V9HFAM8RASGZ4ZYZQEMT Recon 0.21.0 Decision Closure Triage

## Overview

The immutable 2026-08-04 ATT-4845 replay was production-valid and READY while
the current evaluation expected BLOCKED: it recorded no decision audit and no
blockers. Detailed acceptance criteria had been mistaken for complete product
closure.

**Falsifiable claim:** For tickets containing unresolved observable choices,
the revised triage flow will retain an evidence-backed decision audit and map
each blocking OPEN decision to one atomic blocker. For tickets whose observable
outcomes are already closed, optional, or merely implementation freedom, the
same flow will not invent blockers. Success is observed through production
verifier diagnostics, generic positive and negative controls, and a new
fresh-context ATT-4845 replay.

**Non-claims:** This does not deterministically discover every semantic
decision, prove correctness for all models or hosts, preserve all seven
pre-existing ATT-4845 oracle items, or establish a general plugin-quality
improvement before a retained fresh-context replay changes the outcome.

## Technical Design

Add one mandatory `decision_audit` section to the existing `triage.yaml`; no
new workspace artifact is needed. Every candidate has a stable `DEC-N` ID, one
of `OPEN`, `CLOSED_BY_TICKET`, `CLOSED_BY_REPOSITORY`,
`OPTIONAL_OUT_OF_SCOPE`, or `IMPLEMENTATION_FREEDOM`, typed evidence, and its
relevant existing triage check. OPEN candidates carry an explicit `blocking`
boolean. Blocking OPEN entries map bijectively to `BLK-N` blocker records;
each blocker names the one decision it asks about.

The skill performs the semantic audit before the six checks. It asks whether an
engineer must guess an externally observable outcome; it treats explicit ticket
alternatives and internal implementation choices as non-blocking when either
can satisfy already-fixed observable behavior. It retains exact ticket quotes
or repository file evidence for every classification.

`triage-tools.py` remains the owner of deterministic execution: hand-parse the
new fixed indentation, validate enum/status/ID/evidence shape, verify quotes,
verify file evidence relative to `RECON_SOURCE_ROOT` (or the current working
directory), enforce one-to-one audit/blocker joins, and derive the three
dependency checks from blocking OPEN entries. It never calculates a semantic
completeness score.

Replay preparation continues to copy the production verifier. The case oracle
gains a repository-only calibration record that independently classifies the
seven historical decision families and retains only approved blocking decisions
for score coverage. The report renders that calibration; it remains excluded
from prepared runs.

## Testing Strategy

The focused verifier control covers all five statuses, one generic READY audit,
OPEN alternatives/threshold/ownership failures, bad status/check joins,
unmapped/overloaded blockers, quote and file-evidence drift, and leaked
ATT-specific vocabulary in shipped triage assets. Replay controls update their
production-valid fixtures and prove the bounded calibration and oracle
isolation. The generated report is regenerated and structure-checked.

Run focused triage/replay/report controls, replay-skill validation, Decree
lint/progress, adapter generation/check, links, and coherence. Only after they
pass, prepare a new ATT-4845 run from its frozen case and target commit; verify
PREPARED and its bundled offline verifier, then emit the fresh-context prompt
without authoring the submission.

## Acceptance Criteria

- [x] Triage records a generic decision audit before checks and uses no ATT-specific vocabulary in shipped assets.
- [x] The production verifier enforces the persisted audit schema, cited evidence, atomic blocker joins, check agreement, and derived disposition.
- [x] Generic clean and failing controls prove the listed closure classifications and invalid combinations.
- [x] ATT-4845’s seven historical oracle decisions are independently calibrated with retained reasons; only approved blocking decisions remain score targets.
- [x] Replay controls, operator docs, and generated report reflect the new audit without leaking the oracle into a prepared run.
- [x] All required gates pass and a new ATT-4845 run is PREPARED with a clean executable offline verifier.
