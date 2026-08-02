# Render the dossier from artifacts

> Render dossiers from artifacts; let the model author only headline and lede

- **Status:** proposed — deferred until discovery and repro expose verified,
  parse-stable contracts
- **Priority:** P1
- **Theme:** determinism rail
- **Origin:** The 2 Aug 2026 skill-design audit confirmed that `recon-report`
  still hand-fills a fixed template; the earlier render-comment improvement left
  this exact `judgment.yaml` follow-up open.
- **Depends on:** render-comment

## Problem

The dossier is described as a view with no new facts, yet a model currently
transcribes every verdict, blocker, route, evidence line, exhibit, and handoff into
HTML. The fixed template constrains layout but does not prove that copied facts
match the source artifacts. A fluent paraphrase, omitted blocker, or stale handoff
can ship while workspace lint remains clean.

This dossier is what PMs and engineers read when the Jira comment intentionally
stays short, so transcription drift weakens the company's evidence chain.

## Before (today)

```yaml
# triage/triage.yaml
ask: "which event names and properties should analytics receive?"
```

```html
<!-- still passes workspace lint -->
<p>Ask analytics to confirm the tracking setup.</p>
```

The HTML is plausible, but it dropped the exact decision the owner must supply.

## After (proposed)

The model authors only two bounded judgment fields:

```yaml
headline: "Three owner decisions block implementation"
lede: "Design, video hosting, and analytics names must be supplied on the ticket."
```

Everything else is rendered mechanically:

```text
$ recon render dossier ATT-5107
sources: 7 artifacts · 3 blockers · 5 exhibits · 1 gate
judgment: 2 fields · 149 characters
template markers: 0
provenance: 42 rendered coordinates mapped to declared source fields
wrote: report/dossier.html (1.8 MB)
```

Success means the same artifacts plus the same two judgment strings produce
byte-identical HTML, and every displayed fact can be traced to one source field.

## Implementation sketch

- Add a small report-judgment artifact with only `headline` and `lede`.
- Add *render-dossier.sh* plus a dependency-free parser/renderer after discovery
  and repro expose verified parse-stable structures; do not infer a second schema
  from arbitrary Markdown headings.
- Embed exhibits, pin links, render missing stages, and copy handoff bytes in code.
- Fail on unresolved markers, undeclared source values, oversized output, or
  malformed judgment fields.
- Delete the slot-filling workflow and slot map from `recon-report`; retain only
  the two-field judgment step, renderer call, lint, and publish capability gate.

## Open questions

- Start with BLOCKED/NEEDS_INFO dossiers whose source is structured
  `triage.yaml`. Extend READY dossiers only after discovery/repro formats are
  mechanically verified and versioned.
