# Delegation is not an answer

> A reply closes a blocker only if it supplies the asked value; delegation ≠ answer

- **Status:** proposed
- **Priority:** P2
- **Theme:** operational robustness
- **Origin:** ATT-5107 triage run, 1 Aug 2026 — Osman's post-marker reply
  ("Hi [Barım] can you help [Doruk] with his 2nd question?") arrived after the
  marker comment, so by the current rule it counted as a reply to its questions.
  It answered nothing.

## Problem

Rule 9 of `recon-triage`: "a human comment posted after a marker comment counts as
a reply to its questions." That heuristic is right about *attention* (someone
engaged) but wrong about *resolution*. Delegations, re-pings, and "looking into it"
comments all match it. The 1 Aug run had to override the rule by judgment — the
kind of silent mid-run call that produces run-to-run inconsistency, and the
stale-blocker check's promise to "re-evaluate answered questions automatically"
oversells what actually happens.

## Before (today)

Ticket state on re-run:

```
31 Jul 19:22  [marker comment v0.6.0 — asks 1..3]
31 Jul 19:35  Osman: "Hi [Barım] can you help [Doruk] with his 2nd question?"
```

By the written rule, blocker 2 has "a reply". A literal-minded run could mark it
answered and flip toward READY on a comment that supplied no video id, no hash,
no URL. The 1 Aug run kept it open — correctly, but based on nothing pinned.

## After (proposed)

SKILL.md defines reply classification with a closing criterion tied to the ask:

- A blocker **closes** only when a human comment after the marker **supplies the
  decision or value its ask requested** (the ask names the value: a design link or
  a build-to-PNG go-ahead; a video id + hash or URL; event names + properties).
- A reply that re-assigns or re-pings **updates the blocker** — new `owner`, new
  dated `state` line — and keeps it open.
- Anything else ("will check", "+1") only updates `state`.

Re-run output for the 1 Aug state becomes deterministic:

```
blocker 2 'Video hosting': OPEN — post-marker reply classified as delegation
          (no video id / hash / URL present); owner updated → barim
```

And the [golden-fixtures](../golden-fixtures/README.md) `answered-blocker` fixture
pins both directions: a delegation keeps it open, a comment containing the actual
id + hash closes it.

## Implementation sketch

- Rewrite the answered-blocker sentence in rule 9 + the stale-blockers cross-check
  to the three-way classification above (this stays judgment — but now
  judgment-with-evidence: the verdict line must quote the reply and name the
  missing/supplied value).
- Optional rail: blockers gain a `closes_when:` field ("a video id and hash, or a
  CDN URL, posted on this ticket") written at draft time — the re-run then checks
  the reply against a criterion frozen *before* the reply existed.

## Open questions

- Is `closes_when:` worth the schema weight, or is the three-way prose rule +
  quoted-evidence requirement enough? Start with prose + fixture; add the field if
  drift is observed.
