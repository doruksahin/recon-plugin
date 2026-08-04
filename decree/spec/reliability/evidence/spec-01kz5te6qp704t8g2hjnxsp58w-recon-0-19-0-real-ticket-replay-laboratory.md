---
date: '2026-08-04'
governs:
- AGENTS.md
- evals/CLAUDE.md
- evals/README.md
- evals/skills/recon-replay-lab/SKILL.md
- evals/skills/recon-replay-lab/agents/openai.yaml
- evals/skills/recon-replay-lab/references/handoffs.md
- evals/skills/recon-replay-lab/references/interpretation.md
- evals/cases/att-4845-pre-comment/case.json
- evals/cases/att-4845-pre-comment/input/ticket.json
- evals/cases/att-4845-pre-comment/oracle/decisions.json
- evals/cases/att-4845-pre-comment/fixtures/atomic-pass.yaml
- evals/cases/att-4845-pre-comment/fixtures/combined-layout-fail.yaml
- tools/replay-ticket.py
- tools/render-replay-lab-report.py
- tools/test-replay-lab.sh
- tools/test-replay-lab-report.sh
- tools/check-coherence.sh
- tools/CLAUDE.md
- docs/plans/2026-08-04-real-ticket-replay-laboratory.md
- docs/replay-lab-report.html
- docs/improvement-proposals/0.19.0/README.md
- docs/improvement-proposals/0.19.0/real-ticket-replay-lab/README.md
- docs/improvement-proposals/README.md
- docs/improvement-proposals/CLAUDE.md
- docs/CLAUDE.md
- CLAUDE.md
id: SPEC-01KZ5TE6QP704T8G2HJNXSP58W
references:
- ADR-01KZ0ZK4WYVWRY0WJM2CZ7ZS8C
status: implemented
---

# SPEC-01KZ5TE6QP704T8G2HJNXSP58W Recon 0.19.0 Real Ticket Replay Laboratory

## Overview

Create a repository-only laboratory that can replay Recon's judgment against a
frozen real Jira ticket and target-repository commit. The first case is
ATT-4845 immediately before the first human analysis comment. It exists to
measure one observed failure precisely: a structurally valid triage can merge
two independent product decisions into one blocker and still pass today's
verifier.

Version 1 proves only three things: the prepared replay pack excludes the
oracle, the candidate remains valid under Recon's production triage verifier,
and distinct candidate blockers cover all case-specific decision families.
It does not claim automatic model execution, general output quality, or
cross-host repeatability. Those require more real cases and retained live runs.

## Technical Design

### Case contract

`evals/cases/<case-id>/` owns four layers:

- `case.json` identifies the source ticket, cutoff, sanitized ticket snapshot,
  target repository name and immutable commit, oracle path, and input hash.
- `input/` contains only material visible to the replaying agent. ATT-4845's
  snapshot has no post-cutoff comment, account identifier, credential, or Jira
  API URL.
- `oracle/decisions.json` names the expected disposition and independently
  scorable decision families. Each family contains AND-groups of lexical
  signals; one term from every group must appear in a blocker's title, ask, or
  detail.
- `fixtures/` contains a clean seven-blocker control and a clean six-blocker
  negative control that merges keyword presentation with intro-layout
  behavior. Fixtures exercise the scorer; they are not evidence of model
  quality.

The oracle never enters a prepared replay directory. Case validation rejects
unsafe relative paths, unknown schema versions, a ticket key mismatch, a
non-empty pre-comment comment set, input hash drift, malformed decision rules,
duplicate decision IDs, and a non-immutable repository commit.

### Replay rail

`tools/replay-ticket.py` exposes five deterministic commands:

1. `validate <case-dir>` validates the case contract without contacting Jira
   or the target repository.
2. `prepare <case-dir> --repo <path> --out <new-dir>` verifies that the target
   commit exists, exports that exact commit with `git archive`, copies only the
   sanitized input, emits replay instructions and a receipt, then atomically
   publishes a new replay directory. It refuses to overwrite an existing
   destination.
3. `score <case-dir> <triage.yaml>` first runs the production
   `triage-tools.py verify` path against the frozen ticket. It then parses the
   same fixed artifact and computes a deterministic maximum one-to-one matching
   between required decisions and blockers. One combined blocker cannot earn
   credit for two independent decisions. The report names matched, missed, and
   overloaded blockers and exits non-zero unless the artifact is valid, the
   expected disposition matches, and every decision family is covered.
4. `state <run-dir> [--case <case-dir>]` validates the prepared receipt and derives one
   conversation-independent state from retained files: `PREPARED`,
   `SUBMITTED`, or `SCORED`. Missing, contradictory, symlinked, or hash-drifted
   artifacts fail closed with exit 2 and an actionable diagnostic. Successful
   output includes the exact next action; no model owns the transition logic.
5. `evaluate <run-dir> [--case <case-dir>]` accepts only `SUBMITTED`, calls the same
   scorer, and atomically retains `score.txt` plus a machine-readable
   `result.json`. It returns the score status (0 pass, 1 quality failure),
   refuses overwrite, and leaves no partial result on contract failure.

For repository cases, `state` and `evaluate` derive
`evals/cases/<receipt.case_id>` from the run receipt, so the run path is the
only handoff handle. `--case` exists solely for isolated or external fixtures
and is still checked against the receipt.

The runner is standard-library Python and repository-only; it does not ship in
the plugin or alter the runtime pipeline. A replaying human or harness remains
responsible for launching a fresh model context from the prepared directory and
retaining the resulting `submission/triage.yaml`.

### LLM operator handoff

`evals/skills/recon-replay-lab/` is a repository-local operator skill. It is
deliberately outside `recon/skills/`, so internal cases, oracle interpretation,
and evaluation procedures cannot ship in the product plugin. Root guidance
routes start, resume, state, score, and comparison requests to this skill.

The skill has two explicit phases:

1. In the operator context, validate and prepare the run, explain the frozen
   inputs and exclusions, print a copy-ready fresh-context handoff, then stop.
   This context may know the case and oracle, so it must never author the
   submission.
2. In a fresh replay context, the receiving LLM follows `REPLAY.md`, writes only
   `submission/triage.yaml`, returns the run path, and stops. The operator then
   resumes by calling `state` and `evaluate`, not by reconstructing progress
   from conversation memory.

`SKILL.md` owns only routing, phase boundaries, and required explanations.
`references/handoffs.md` owns copy-ready handoff shapes; load it only when a
handoff is being emitted. `references/interpretation.md` owns score
interpretation and non-claims; load it only after evaluation. Parsing, state,
scoring, output mutation, exit codes, and overwrite behavior remain rail-owned.

### Progressive disclosure and release record

`evals/README.md` is the compact operator entry point and case ledger.
`evals/CLAUDE.md` owns role lines for top-level laboratory entries. A v0.19.0
proposal records the observed ATT-4845 origin and concrete before/after
diagnostic; the implementation plan records command-level rollout and the
claim boundary. Root editor guidance links the laboratory but does not preload
case or oracle detail.

### Generated operator report

The laboratory has one generated, self-contained operator view at
*docs/replay-lab-report.html*. Its owner is
*tools/render-replay-lab-report.py*, which reads `case.json`, the sanitized
ticket, the decision oracle, both scorer fixtures, the replay rail, and the
governing SPEC. The generator executes the real `validate` and `score`
commands while rendering; their observed stdout and exit codes become the
report's before/after evidence rather than copied prose.

The report must visually distinguish the repository case tree from a prepared
run tree, explain ownership and disclosure boundaries, enumerate the seven
ATT-4845 decisions, show the one-to-one matching rule, provide exact operator
commands and scenarios, and state non-claims. Every factual reference carries
a current repo-relative path, computed line number, and SHA-256 prefix. It has
no remote fonts, scripts, or assets.

`python3 tools/render-replay-lab-report.py --check` regenerates the expected
bytes in memory and fails on any difference from the checked-in HTML.
`tools/check-coherence.sh` invokes that check, making the HTML a generated view
instead of an independently authored mirror.

## Testing Strategy

`tools/test-replay-lab.sh` uses isolated temporary directories and asserts:

- the real ATT-4845 case validates;
- the seven-blocker fixture passes with 7/7 distinct decisions;
- the six-blocker fixture remains valid under the production verifier but
  fails lab scoring with 6/7, names the missed decision, and identifies the
  overloaded blocker;
- tampered input fails the stored SHA-256 check;
- a synthetic git repository prepares from an immutable commit, the prepared
  tree has no oracle file or oracle content, and an existing destination is
  never overwritten.
- a prepared run derives `PREPARED`, a returned artifact derives `SUBMITTED`,
  evaluation persists both result artifacts and derives `SCORED`, and an
  evaluation retry cannot change the retained result;
- receipt mismatch, result inconsistency, symlinked artifacts, and candidate
  hash drift fail closed instead of guessing a state;
- the local skill validates structurally and its start/resume handoffs contain
  the exact rail commands, phase stop, run path, and return contract.

After focused tests, run Decree lint/progress, link and coherence checks,
adapter drift check, and the existing repository test chain. The first
milestone may claim a deterministic evaluation rail for this case only. A
plugin-quality improvement requires a retained fresh-context replay before and
after a later skill change; a general workflow claim requires at least three
representative real tickets under the same rubric.

## Acceptance Criteria

- [x] ATT-4845 is frozen at the pre-comment cutoff as a sanitized, hash-pinned case with a separate oracle.
- [x] `validate`, `prepare`, and `score` implement the bounded contracts above with stable diagnostics and exit codes.
- [x] The clean atomic fixture scores 7/7 and the clean combined-layout negative control scores 6/7 while naming the overload.
- [x] Prepare exports the exact target commit, leaks no oracle material, and refuses overwrite.
- [x] The laboratory entry doc, v0.19.0 proposal, implementation plan, and repository role docs describe the same claim boundary.
- [x] Decree, focused replay tests, links, coherence, adapters, and existing repository tests pass.
- [x] A self-contained generated HTML report explains both folder trees, the end-to-end workflow, ATT-4845 decisions, scenarios, before/after evidence, action steps, reasoning, claim boundaries, and current source references.
- [x] The report generator derives command evidence, hashes, and line references from live sources; its `--check` mode runs in coherence, and focused HTML tests assert section/navigation integrity, local references, copy targets, and desktop/narrow responsive contracts. Direct visual inspection remains operator review because the local browser security policy blocks `file://` reports and forbids a serving workaround.
- [x] `state` and `evaluate` derive and persist the three replay states, preserve scorer exit semantics, reject inconsistent or overwritten runs, and pass clean plus fault-injected controls.
- [x] The repository-local `recon-replay-lab` skill validates, is routed by project guidance, keeps oracle-aware and replaying LLM contexts separate, and emits complete start/resume handoffs from progressively disclosed references.
- [x] The operator entry point and generated HTML explain the LLM handoff loop, exact next actions, persisted state, before/after user experience, and the bounded outcome demonstrated by an end-to-end ATT-4845 control run.

### Deferred (v2)

- [ ] Launch Claude Code and Codex automatically in isolated fresh contexts and retain host/model/version metadata.
- [ ] Add at least two more real cases covering READY and NEEDS_INFO or a distinct BLOCKED class.
- [ ] Add independent semantic review for valid synonyms that the lexical oracle cannot recognize.
- [ ] Compare a plugin change before/after across the representative case set with repeated runs and variance.
