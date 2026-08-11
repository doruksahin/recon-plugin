# Recon pipeline — versioned improvement proposals

Improvement records are grouped by the planning version originally reserved for
them. The path is the durable ID:
`docs/improvement-proposals/<target-version>/<slug>/README.md`.

The directory name is evidence identity, not published-version history. When
multiple unreleased cohorts land together, the release rail derives the actual
next SemVer from Git and the records keep their original paths. Cohorts v0.19.0
through v0.22.0 were therefore consolidated into the v0.19.0 release;
v0.20.0, v0.21.0, and v0.22.0 are not skipped releases or upgrade steps.

Read [CLAUDE.md](CLAUDE.md) before adding or changing a record. In particular,
new proposals must reserve a **future** SemVer cohort; do not add work to a
released, consolidated, or historical version directory. Unrelated new intake
starts at v0.24.0 or a later explicitly planned cohort.

## Design basis

The v0.15 review applied Skillshare's [Skill Design](https://skillshare.runkids.cc/docs/understand/philosophy/skill-design)
and [Skill Design Patterns](https://skillshare.runkids.cc/docs/understand/philosophy/skill-design-patterns):
keep routing metadata compact, disclose operational detail only after activation,
move repeatable decisions into deterministic commands, and compose authoring
skills with independent reviewer rails. Model judgment remains only where the
evidence needs semantic or visual interpretation.

## Cohort ledger

| Planning cohort | Cohort state | Records | Outcome |
| --- | --- | ---: | --- |
| [v0.9.0](0.9.0/README.md) | released | 4 | Initial deterministic rails and document coherence |
| [v0.10.0](0.10.0/README.md) | released | 2 | Governance handoff UX and live doctor |
| [v0.12.0](0.12.0/README.md) | released | 1 | Gated release and distribution skill |
| [v0.13.0](0.13.0/README.md) | released | 2 | Ticket ledger and living state canvas |
| [v0.14.0](0.14.0/README.md) | historical proposed | 12 | Deferred and unshipped rails retained as an auditable cohort |
| [v0.15.0](0.15.0/README.md) | released | 5 | Verified company handoff chain |
| [v0.16.0](0.16.0/README.md) | released | 1 | Recorded repro runtime and proof package |
| v0.17.0 | released | 0 | Gate exchange records |
| [v0.18.0](0.18.0/README.md) | released | 1 | Approved READY delivery to Jira with dossier and evidence bundle |
| [v0.19.0](0.19.0/README.md) | released (v0.19.0) | 1 | Frozen real-ticket replay and distinct decision-coverage scoring |
| [v0.20.0](0.20.0/README.md) | released (v0.19.0) | 1 | Offline-valid prepared replay verification |
| [v0.21.0](0.21.0/README.md) | released (v0.19.0) | 1 | Generic evidence-backed decision closure |
| [v0.22.0](0.22.0/README.md) | released (v0.19.0) | 1 | Durable requirement-closure improvement loop |
| [v0.23.0](0.23.0/README.md) | in progress | 1 | Version-scoped private team-review laboratory |
| [v0.24.0](0.24.0/README.md) | in progress | 1 | Recorder failed-start recovery with marker-owned server shutdown |

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
