# Validate triage.yaml mechanically

> Schema + regex lint for triage.yaml: rule-7 identifier bans, length caps, ask shape

- **Status:** proposed
- **Priority:** P1
- **Theme:** determinism rail
- **Origin:** ATT-5107 triage run, 1 Aug 2026 — rule 7 compliance (no internal
  identifiers, one-sentence asks) rested entirely on the model remembering a
  paragraph of prose.

## Problem

Rule 7 of `recon-triage` ("human-facing questions MUST be concrete… internal
identifiers are BANNED from all human-facing text") is prose the model must hold in
attention while writing every ask. About half of it is mechanically checkable, and
verbosity — the main slop vector — is a *budget* problem that caps solve better
than style guidance.

## Before (today)

A realistic slip that nothing fails on:

```yaml
ask: "should the WelcomeModalService keep using getVideoUrl() with the ?h= hash param,
or do we refactor toward the new CDN approach? Also wondering about the poster prop."
```

Three violations ship silently: internal identifiers (`WelcomeModalService`,
`getVideoUrl()`), two questions fused into one ask, and a question a PM cannot
answer without reading code.

## After (proposed)

```
$ bash recon/scripts/verify-triage.sh ATT-5107
blocker 2 ask: FAIL — identifier-like token 'getVideoUrl()' (pattern: \w+\(\))
blocker 2 ask: FAIL — camelCase token 'WelcomeModalService' (pattern: [a-z][A-Z])
blocker 2 ask: FAIL — 214 chars (cap: 200)
blocker 2 ask: FAIL — contains 2 '?' (must be exactly 1, at end)
```

The ATT-5107 run's real ask passes all checks (118 chars, one terminal `?`, no
identifier-shaped tokens):

> "who uploads the new welcome video, and what are the resulting video id and hash
> (or CDN URL) the modal should play?"

Checks, all cheap:

| Field | Check |
| --- | --- |
| top-level | required keys present; `disposition`/check values in enum |
| `blockers` | non-empty when BLOCKED/NEEDS_INFO; each has title/owner/ask/detail |
| `title` | ≤ 5 words |
| `ask` | ends `?`; exactly one `?`; ≤ 200 chars; no `[a-z][A-Z]`, `\w+\(\)`, `` ` ``, `_[a-z]` |
| `detail.state` | ≤ 300 chars |
| `detail.options[]` | each ≤ 200 chars |
| headline/lede (dossier judgment slots) | ≤ 140 / ≤ 2 sentences |

What regexes *cannot* check — "answerable without reading code" — stays as a single
prose line. Everything else gets deleted from SKILL.md rule 7.

## Implementation sketch

- New `recon/scripts/verify-triage.sh` (shared home for
  [derive-disposition](../derive-disposition/README.md) and later
  [verify-quotes](../verify-quotes/README.md) and [slop-lint](../slop-lint/README.md)).
- Python-in-bash like the existing rails; no new dependencies.
- Wire into `lint-workspace.sh`; posting path re-runs it after any `Edit first` loop.
- Trim rule 7 in SKILL.md to the non-mechanical residue + a pointer to the script.

## Open questions

- Exact caps need calibration against a few past runs (ATT-5047, ATT-5107) so real,
  good asks don't fail. Start loose (200/300), tighten with evidence.
- CamelCase regex will false-positive on product names like "AdCreative" — needs an
  allowlist file next to the script.
