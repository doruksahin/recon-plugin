---
date: '2026-08-04'
governs:
- recon/skills/recon-triage/SKILL.md
- recon/skills/CLAUDE.md
- recon/scripts/triage-tools.py
- recon/scripts/CLAUDE.md
- recon/docs/pipeline.md
- tools/test-triage-verifier.sh
- tools/CLAUDE.md
id: SPEC-01KZ6GYNQQXY7EQEDC4M4JFP88
references:
- ADR-01KZ0ZK4WYVWRY0WJM2CZ7ZS8C
- SPEC-01KZ66V9HFAM8RASGZ4ZYZQEMT
status: implemented
---

# SPEC-01KZ6GYNQQXY7EQEDC4M4JFP88 Recon 0.22.0 Normative Requirement Closure

## Overview

The existing decision-closure triage records discovered candidates, but it
does not make exhaustive normative-requirement coverage or the audited closure
surface explicit. Extend that contract so triage inventories every normative
ticket obligation, classifies each atomic audit item exactly once, and records
that identity/mapping, ownership/update path, threshold completeness, and
ordering completeness were deliberately checked.

This extends `SPEC-01KZ66V9HFAM8RASGZ4ZYZQEMT`. It retains the existing five
classification outcomes and one-to-one blocking decision/blocker join. It does
not add ticket vocabulary, deterministic semantic extraction, a new workspace
artifact, or any implementation-stage behavior.

## Technical Design

Keep `triage.yaml` as the single artifact and `decision_audit` as its
classification list. Add a fixed `requirement_coverage` mapping whose five
boolean attestations state that the normative inventory and the four generic
closure surfaces were audited. Every decision-audit entry gains one required
`surface` value from `direct_obligation`, `identity_mapping`,
`ownership_update_path`, `threshold_completeness`, or
`ordering_completeness`. The existing `status` field remains the exact
classification: `CLOSED_BY_TICKET`, `OPEN`, `OPTIONAL_OUT_OF_SCOPE`,
`IMPLEMENTATION_FREEDOM`, or `CLOSED_BY_REPOSITORY` (the
repository-resolvable case).

The skill must split ticket prose into atomic normative obligations before
classification. It must check all four closure surfaces for applicability,
including exhaustive identities and mappings, an authoritative update owner
and delivery path, testable threshold bounds and boundary behavior, and
complete ordering/precedence/tie behavior. Distinct open decisions stay in
distinct audit entries even when prompted by the same ticket sentence.

`triage-tools.py` remains the deterministic owner. Its fixed parser validates
the coverage mapping, rejects missing or false attestations, validates the
surface enum, preserves exact ticket and repository evidence checks, and
retains the bijection between every blocking `DEC-N` and one `BLK-N`. Semantic
inventory and applicability remain model judgment with visible evidence; the
rail verifies the retained shape and links without pretending to parse ticket
meaning.

### Attempt 2 refinement: exhaustive context mappings

For a normative requirement whose observable result varies by context, the
identity/mapping audit is exhaustive only when it retains one atomic
`identity_mapping` item for every relevant context identity. Named contexts and
applicable omitted, default, and alias cases stay distinct. Each item records a
fixed `context_kind`, one `context_identity`, and one `observable_result`; an
unselected identity or result is written as `UNRESOLVED` and remains an OPEN
decision rather than being inferred from adjacent prose or repository shape.

Add `context_mapping_exhaustive: true` to the coverage mapping. It attests that
all relevant context identities were enumerated, while the verifier proves the
retained shape: identity/mapping items carry the three mapping fields, other
surfaces do not, CLOSED items contain no `UNRESOLVED` value, and OPEN mapping
items contain at least one. The existing audit/blocker bijection keeps every
distinct unresolved mapping as its own atomic blocker. A
`CLOSED_BY_REPOSITORY` classification requires at least one verified `file`
evidence entry, so repository resolution is cited rather than assumed.

## Testing Strategy

Extend `tools/test-triage-verifier.sh` with generic fixtures for all five
classification outcomes and all five surface values. Add failing controls for
missing/incomplete coverage, missing or unknown surfaces, and preserve the
existing missing, overloaded, and mismatched blocker-link controls. Keep the
generic READY control to prove that a fully closed requirement audit does not
invent blockers. Run the focused verifier control, adapter drift check, link
and coherence checks, Decree lint/progress, and the repository's full commit
guardrail.

Attempt 2 adds generic controls for the exhaustive-context coverage attestation,
mapping-field surface rules, OPEN/resolved consistency, distinct-context
blocker linkage, and repository-closure file evidence. The existing generic
READY fixture remains unchanged in disposition and continues to pass.

## Acceptance Criteria

- [x] Triage guidance inventories every normative requirement and explicitly audits identity/mapping, ownership/update path, thresholds, and ordering.
- [x] Every audit entry has exactly one allowed classification and one allowed closure surface.
- [x] The verifier rejects absent or incomplete coverage attestations and invalid audit surfaces.
- [x] Every blocking OPEN decision remains bijectively linked to exactly one atomic blocker.
- [x] Generic READY and BLOCKED controls pass without case-specific vocabulary in shipped assets.
- [x] Pipeline and directory ownership documentation mirror the revised contract.
- [x] The full commit guardrail passes.
- [x] Context-varying requirements retain one identity/mapping item per relevant named, omitted, default, or alias context.
- [x] Every identity/mapping item retains one context identity and one observable result, with unresolved values allowed only on OPEN items.
- [x] The verifier rejects missing exhaustive-context coverage, cross-surface mapping fields, merged mapping/blocker joins, and uncited repository closure.
- [x] The generic READY control and the full commit guardrail pass after the attempt-2 refinement.
