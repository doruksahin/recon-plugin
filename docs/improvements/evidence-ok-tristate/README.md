# Make evidence_ok tri-state

> Split evidence_ok into true / auth-walled / broken; stop the permanent false flag

- **Status:** proposed
- **Priority:** P2
- **Theme:** operational robustness
- **Origin:** ATT-5107 triage run, 1 Aug 2026 — both linked resources failed
  anonymous verification (claude.ai design → 403, Drive folder → Google login
  redirect) even though the assignee demonstrably had both.

## Problem

`evidence_ok` is boolean, and the check runs as anonymous WebFetch. For this org
the two standard evidence hosts — claude.ai design shares and Google Drive — are
*always* auth-walled, so `evidence_ok: false` fires on every run regardless of
whether the evidence is actually reachable by the people doing the work. A signal
that is red by construction stops carrying information, and it visually inflates
the failed-check count in every dossier ("5 flagged" when one flag is structural).

## Before (1 Aug run, verbatim)

```
Design link  → HTTP 403 Forbidden (anonymous fetch)
Drive folder → 302 → accounts.google.com/ServiceLogin
```

```yaml
evidence_ok: false
```

…while a 30 Jul human comment on the same ticket says: "I pulled the design export
and both Drive assets and checked them against the design's own measurements." The
false flag had to be neutralized by hand in `stale_blocker_note`.

## After (proposed)

```yaml
evidence_ok: auth-walled   # true | auth-walled | broken
evidence_ok_note: "design 403 + Drive login wall (anonymous); assignee access
                   confirmed by 30 Jul human comment"
```

Semantics per value:

| Value | Meaning | Effect on disposition |
| --- | --- | --- |
| `true` | every linked resource verified this run | none |
| `auth-walled` | resource(s) behind auth; access confirmed by a human comment or known-good host | none — noted in dossier, never a blocker by itself |
| `broken` | 404 / revoked share / dead host — genuine link rot | counts toward BLOCKED as today |

This composes with [derive-disposition](../derive-disposition/README.md): the
derivation treats only `broken` as a failing check, so the verdict formula stays
mechanical while the false-positive class disappears.

## Implementation sketch

- Schema change in `recon-triage` step 2/3 (check table + triage.yaml schema).
- A small host classification: `claude.ai/design`, `drive.google.com`,
  `docs.google.com` → expected-auth-walled; anything returning 404/410 → broken.
- Dossier six-checks table renders `auth-walled` as a neutral (accent) result, not
  a fail.
- Update the derive-disposition formula in the same commit.

## Open questions

- Should "access confirmed by a human comment" be required to downgrade
  auth-walled → non-blocking, or is the known-host list enough? (Stricter: require
  the confirming quote as `kind: quote` evidence — pairs with
  [verify-quotes](../verify-quotes/README.md).)
- Optional richer path: verify auth-walled links through the user's own browser
  session (Claude-in-Chrome) instead of anonymous fetch — bigger machinery, only
  worth it if link rot behind auth walls actually bites.
