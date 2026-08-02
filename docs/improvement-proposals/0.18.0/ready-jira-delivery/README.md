# Publish approved READY dossiers and evidence bundles to Jira

> Publish approved READY dossiers and evidence bundles to Jira

- **Status:** in-progress
- **Priority:** P1
- **Theme:** operational robustness
- **Origin:** ATT-5047 Recon run on 2 Aug 2026 reached READY, completed Discovery,
  and produced approved repro and implementation-brief artifacts, but Jira received
  no Recon comment or attachments because delivery existed only for BLOCKED and
  NEEDS_INFO.

## Problem

READY is the path that produces the most complete implementation packet, yet the
current delivery boundary ends before Jira. Ticket readers cannot see the verified
triage result, repro evidence, approved OPEN decisions, route, or brief unless
they have local workspace access. BLOCKED and NEEDS_INFO instead package and attach
their dossier and bundle behind an explicit delivery gate.

## Before (v0.17.0)

```text
triage disposition: READY
→ recon-discovery
→ approval gate
→ print local handoff

Jira comment: none
Jira attachments: none
```

The triage skill's attachment and ZIP path runs only under its BLOCKED / NEEDS_INFO
branch. Its comment renderer rejects READY, so a model cannot safely reuse it for
an approved Discovery package.

## After (v0.18.0)

```text
discovery gate: approved
→ render dossier from the final current-run package
→ render the deterministic READY delivery comment
→ package recon-dossier-ATT-5047.html + recon-artifacts-ATT-5047.zip
→ delivery gate approves exact comment + attachment manifest
→ replace Recon-owned attachments
→ create or edit the one Recon marker comment

Jira: one READY comment + recon-dossier-ATT-5047.html + recon-artifacts-ATT-5047.zip
```

The Discovery gate approves the implementation package. A second, explicit Jira
delivery gate approves the exact comment and both attachment names, sizes, and
bundle file count. A READY delivery updates the most recent Recon marker comment
rather than accumulating status comments.

## Implementation sketch

- Add a deterministic *render-ready-comment* rail and shape verifier for the
  approved Discovery summary, decision count, route, and marker.
- Extend the reusable bundle and attachment rails' allowed caller path to accept
  the final READY dossier and package it after the Discovery approval.
- Make the READY Discovery delivery sequence render dossier → comment → bundle →
  explicit gate → attachments first → comment create/edit, with responses and
  ledger events recorded under the current ticket workspace.
- Update the workspace registry, pipeline state/trigger tables, triage and
  Discovery contracts, and regression fixtures so READY delivery cannot silently
  skip or use stale pre-gate artifacts.

## Open questions

None — the product decision is that every approved READY ticket publishes the
same dossier-and-bundle delivery shape as a blocked ticket, behind its single
explicit Jira delivery approval.
