# Verify quoted evidence against the source

> Type evidence lines; substring-check every quote against ticket.json

- **Status:** in-progress — implemented 1 Aug 2026 (typed evidence schema + verbatim
  quote pass in `recon/scripts/verify-triage.sh`; marker-comment sources rejected;
  curly-quote/whitespace normalization); pending commit/release
- **Priority:** P1
- **Theme:** determinism rail
- **Origin:** ATT-5107 triage run, 1 Aug 2026 — blocker evidence quoted Osman's
  comments verbatim, but only model discipline made it verbatim; a paraphrase
  wearing quote marks would have shipped identically.

## Problem

Evidence lines in `triage.yaml` are free text. Quotes are the highest-stakes
hallucination surface in the pipeline: a fabricated or paraphrased quote doesn't
just decorate a claim, it can *decide a blocker* — and today nothing distinguishes
a verbatim quote from an invented one.

## Before (today)

This plausible-looking evidence line would ship unchallenged:

```yaml
evidence:
  - "Osman Dacik, 30 Jul: 'the design is outdated, please build to the screenshot'"
```

Osman never said that. He said the design update *"might have been forgotten"* —
still an open decision. The fabricated version closes blocker 1 (build to the PNG)
on the strength of a quote that doesn't exist in `ticket.json`.

## After (proposed)

Evidence entries get a `kind`, and the validator greps every `quote` against the
fetched ticket:

```yaml
evidence:
  - kind: quote
    text: "he would update the layout and the buttons for this ticket"
    source: comment 2186726
  - kind: http
    text: "design link (claude.ai share URL) → HTTP 403 (anonymous, this run)"
  - kind: git
    text: "git branch -a | grep -iE 'welcome|onboard|5107' → none"
```

```
$ bash recon/scripts/verify-triage.sh ATT-5107
quote check: FAIL — "the design is outdated, please build to the screenshot"
             not found in ticket.json (description + comments 2185850–2187660)
quote check: PASS — "he would update the layout and the buttons for this ticket"
             found in comment 2186726
```

The check is a plain substring match against the same `ticket.json` the run already
saved — no extra fetches, fully deterministic, and it converts "the model quoted
faithfully" from an assumption into a lint result. `http`/`git`/`file` kinds get
lighter shape checks (an HTTP status present; a known command prefix).

## Implementation sketch

- Extend the `evidence` schema in `recon-triage/SKILL.md` step 3 (both the
  per-blocker `detail.evidence` and the top-level `evidence:` list).
- Add the quote-grep pass to `verify-triage.sh`
  ([validate-triage-yaml](../validate-triage-yaml/README.md)); normalize whitespace
  and curly/straight quotes before matching, since Jira bodies mix both.
- `recon-report` renders `kind` labels in the dossier evidence lists for free.

## Open questions

- Ellipsized quotes ("he would update … forgotten") — either ban mid-quote ellipses
  or split into multiple short quotes; short full substrings are the safer rule.
- Depends mildly on [validate-triage-yaml](../validate-triage-yaml/README.md)
  landing first (same script, schema change rides along).
