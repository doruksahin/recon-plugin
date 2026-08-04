# Recon pipeline — versioned improvement proposals

Improvement records are grouped by the version they were proposed or shipped
for. The path is the durable ID:
`docs/improvement-proposals/<target-version>/<slug>/README.md`.

Read [CLAUDE.md](CLAUDE.md) before adding or changing a record. In particular,
new proposals must reserve a **future** SemVer cohort; do not add work to a
released or historical version directory. v0.19.0 is the active future cohort;
unrelated new intake starts at v0.22.0 or a later explicitly planned release.

## Design basis

The v0.15 review applied Skillshare's [Skill Design](https://skillshare.runkids.cc/docs/understand/philosophy/skill-design)
and [Skill Design Patterns](https://skillshare.runkids.cc/docs/understand/philosophy/skill-design-patterns):
keep routing metadata compact, disclose operational detail only after activation,
move repeatable decisions into deterministic commands, and compose authoring
skills with independent reviewer rails. Model judgment remains only where the
evidence needs semantic or visual interpretation.

## Cohort ledger

| Target version | Cohort state | Records | Outcome |
| --- | --- | ---: | --- |
| [v0.9.0](0.9.0/README.md) | released | 4 | Initial deterministic rails and document coherence |
| [v0.10.0](0.10.0/README.md) | released | 2 | Governance handoff UX and live doctor |
| [v0.12.0](0.12.0/README.md) | released | 1 | Gated release and distribution skill |
| [v0.13.0](0.13.0/README.md) | released | 2 | Ticket ledger and living state canvas |
| [v0.14.0](0.14.0/README.md) | historical proposed | 12 | Deferred and unshipped rails retained as an auditable cohort |
| [v0.15.0](0.15.0/README.md) | released | 5 | Verified company handoff chain |
| [v0.16.0](0.16.0/README.md) | released | 1 | Recorded repro runtime and proof package |
| v0.17.0 | released | 0 | Gate exchange records |
| [v0.18.0](0.18.0/README.md) | in-progress | 1 | Approved READY delivery to Jira with dossier and evidence bundle |
| [v0.19.0](0.19.0/README.md) | in-progress | 1 | Frozen real-ticket replay and distinct decision-coverage scoring |
| [v0.20.0](0.20.0/README.md) | in-progress | 1 | Offline-valid prepared replay verification |
| [v0.21.0](0.21.0/README.md) | in-progress | 1 | Generic evidence-backed decision closure |

## v0.15 verified company chain

The five v0.15 decisions compose one bounded handoff chain rather than five
isolated cleanups:

```text
attested plugin bytes → bounded routing metadata → atomic runtime snapshot
  → verified repro evidence → verified Discovery + gate + implementation handoff
```

Activation proves the company is running the released plugin; routing loads the
right narrow skill; startup gives that skill one coherent capability snapshot;
and the two artifact gates prevent bad evidence or a lost human decision from
reaching an implementer. Each boundary either fails mechanically or names the
remaining human judgment explicitly.
