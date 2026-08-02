# Resolve owners from ticket data first

> Resolve accountIds from ticket data first; user search only as fallback

- **Status:** proposed
- **Priority:** P2
- **Theme:** operational robustness
- **Origin:** ATT-5107 triage run, 1 Aug 2026 — the mandated user search returned
  TWO "Osman Dacik" accounts; the skill's "NEVER guess" rule gave no disambiguation
  procedure, so the run improvised one.

## Problem

The posting path mandates: resolve each `owner` handle via
`GET /rest/api/2/user/search?query=<name>` and "take `accountId` from it; NEVER
guess". That assumes the search returns one hit. Duplicate display names are common
in large orgs (deactivated accounts, re-provisioned users), and picking the wrong
one silently pings a dead account — the blocker question reaches nobody.

## Before (1 Aug run, verbatim)

```
Osman → Osman Dacik | 712020:738fd3d2-2187-4344-9ba2-a196668d256c
Osman → Osman Dacik | 712020:561eebb4-2ec1-45e0-ba5f-99eccbe3da2d
```

The skill offered no rule for this. The run resolved it by checking `ticket.json`:
the reporter field and the 30/31 Jul comment authors all carry `712020:738fd3d2-…`,
so that account is the one actually active on the ticket. Correct — but improvised,
which is exactly what this pipeline is designed to prevent.

## After (proposed)

Invert the order and codify the tie-break. Owner resolution procedure:

1. **Ticket-local first:** collect accountIds already on the ticket —
   `reporter`, `assignee`, comment authors, and `[~accountid:…]` mentions in
   human comment bodies (all sitting in the already-fetched `ticket.json`).
   If the owner's display name matches exactly one ticket-local account, use it.
   Zero extra HTTP calls; immune to the duplicate trap.
2. **Search as fallback** only for people not yet on the ticket. If search returns
   multiple hits, FAIL loudly at the gate instead of picking:

```
owner 'osman': FAIL — 2 accounts match 'Osman Dacik' and neither appears on the
ticket; ask the user which accountId to use (never pick silently)
```

3. Resolved ids are written into `triage.yaml` as `owner_account_id:` so the
   comment renderer ([render-comment](../render-comment/README.md)) does no lookups.

## Implementation sketch

- Small `recon/scripts/resolve-owner.sh <TICKET> <name>`: step 1 from ticket.json,
  step 2 via search (saving `aux-user-<slug>.json` as today), multi-hit → exit 1
  with the candidates listed.
- SKILL.md posting-path step 4 shrinks to "run resolve-owner.sh per owner".
- Schema: add `owner_account_id` next to `owner` in the blockers schema.

## Open questions

- Display-name matching for step 1: exact match vs normalized (case/diacritics —
  "Barım" vs "barim.cerkez" showed handles and display names diverge; match against
  both `displayName` and the mention ids found in comment bodies).
