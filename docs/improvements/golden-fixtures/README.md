# Golden-ticket fixtures for the pipeline

> Canned ticket.json fixtures + golden-output diffs; regression-test the pipeline

- **Status:** proposed
- **Priority:** P3
- **Theme:** determinism rail
- **Origin:** ATT-5107, 30 Jul → 1 Aug 2026 — between v0.6.0 and v0.7.0 the comment
  format changed completely (inline per-blocker state → short asks + dossier
  attachment). Whether every detail of that change was intentional is undiffable:
  the old behavior survives only in a Jira comment's edit history.

## Problem

The only way to exercise the pipeline today is against live Jira, so behavior
changes between plugin versions are invisible until they land on a real ticket.
There is no way to answer "did this SKILL.md edit change what we post?" before
shipping. Determinism you can't measure is a claim, not a property.

## Before (today)

- Testing = run `/recon:recon-triage <real-ticket>` and eyeball the output.
- The v0.6.0 → v0.7.0 comment-format change shipped with no before/after diff.
- The delegation-vs-answer judgment (Osman's 31 Jul reply re-pinging Barım) was
  made silently mid-run — correct this time, pinned nowhere.

## After (proposed)

```
recon/fixtures/
  blocked-att-5107/
    ticket.json          # captured from the 1 Aug run (anonymized if needed)
    users-osman.json
    users-barim.json
    expected/
      triage.yaml
      comment.txt
  ready-simple/ …
  answered-blocker/ …    # same ticket + one comment supplying video id + hash
```

```
$ bash tools/test-pipeline.sh
blocked-att-5107:   PASS (triage.yaml + comment.txt match golden)
ready-simple:       PASS
answered-blocker:   FAIL — blocker 2 still open in triage.yaml;
                    expected closed (fixture comment supplies video id + hash)
```

Every Jira read already funnels through `curl` in the scripts, so one env var
(`JIRA_FIXTURE_DIR`) lets a wrapper serve files instead of HTTP. The
`answered-blocker` fixture turns the hardest judgment call in the pipeline
([answered-blocker-rule](../answered-blocker-rule/README.md)) into a permanent
regression test.

## Implementation sketch

- `JIRA_FIXTURE_DIR` seam in the scripts' curl helper (or a *jira-get.sh* wrapper
  all skills are told to use — which also centralizes
  [credential-preflight](../credential-preflight/README.md)).
- *tools/test-pipeline.sh* runner: for each fixture, invoke the deterministic legs
  (derive, render, verify) and `diff` against `expected/`.
- Fixtures captured from real runs, scrubbed of anything sensitive.
- **Depends on:** [derive-disposition](../derive-disposition/README.md) and
  [render-comment](../render-comment/README.md) — outputs must be script-produced
  before byte-diffing them is meaningful. The model-judgment leg (filling checks
  and blockers) can only be smoke-tested via the cc-devkit tmux harness; the golden
  diffs cover everything downstream of `triage.yaml`.

## Open questions

- How much of the model leg to include: pure script-level tests first (cheap, in
  CI/git hooks), full skill-in-a-session tests second (manual, via
  `test-skills`)?
- Fixture anonymization policy for names/accountIds before committing them.
