# Recon workspace — what each file is

You are looking at `~/.claude/recon/<TICKET>/` — the working directory of one recon
run for one Jira ticket. It is produced by the `recon` plugin
(https://github.com/doruksahin/recon-plugin). Two rules govern everything here:

1. **Flat + stage dirs = the current run. `runs/` = archived history.** Nothing in
   `runs/` may be read by any pipeline skill — it exists only so no run is ever
   influenced by a previous one.
2. **Every file is registered.** A file not listed below is a contract violation
   (`recon/scripts/lint-workspace.sh` checks this mechanically). Each stage writes
   only inside its own directory.

This index is static: it describes every file the pipeline *can* produce. A missing
directory means that stage did not run — that is information, not an error.

---

## Root

### `meta.yaml`
The run sentinel, written by the step-0 script before anything else. Records which
plugin version produced this run (`plugin_version`), when it started (`started`),
and the ticket. Its presence means "a current run exists"; its age drives the
once-per-run guard. If you need to know whether artifacts here are trustworthy
under the current skill version, this is the file to check.

### `index.md`
This file. Copied verbatim from the plugin's `docs/workspace-index.md` by the
step-0 script — never hand-edited, always identical across tickets.

---

## `triage/` — stage 1: blocker triage (always present after a run)

### `triage/ticket.json`
The raw Jira issue as fetched this run (REST API v2, plain-text bodies): summary,
status, description, all comments, labels, links, assignee, reporter, type. This is
the *evidence source* for the six checks. Comments containing the `recon-triage`
marker are the pipeline's own prior output and are excluded from evidence.

### `triage/aux-<slug>.json`
Auxiliary read-only fetches made while evaluating the checks — anything beyond the
ticket itself that a check needed to verify. Examples: `aux-confluence.json` (a
linked Confluence page fetched to prove the evidence link is accessible, HTTP
status and all), `aux-att-4797.json` (a related ticket fetched to evaluate a
shared-root-cause claim), `aux-children.json` (an epic's child issues). One file
per fetch, named after what it is. Their role: every evidence line in
`triage.yaml` that cites an external resource has its raw material here, so the
verdict is auditable without re-fetching anything.

### `triage/triage.yaml`
**The stage-1 verdict.** Disposition (`READY | BLOCKED | NEEDS_INFO`), the six
check results, cross-checks (status drift, stale blockers), blockers with named
owners, ride-along PR conflicts, and one evidence line per claim. Discovery's
precondition: it will not start unless this says `READY`.

### `triage/jira/` — present only if the posting path ran (BLOCKED/NEEDS_INFO)
- **`comment.txt`** — the exact comment body drafted for Jira, saved *before* the
  human approved posting. Ends with the `~recon-triage v<version>~` marker.
- **`post-result.json`** — the Jira API response after an approved POST/edit.
  Proof of what actually landed on the ticket, and which comment ID to edit next
  time.
- **`attach-result.json`** — responses from attachment uploads (screenshots
  attached to the ticket), when the drafted comment carried visual evidence.

---

## `discovery/` — stage 2: code discovery (present when triage said READY)

### `discovery/discovery.md`
The behavior contract: Gherkin scenarios for the required behavior, the
must-not-change regression behaviors, and any OPEN scenarios (edge cases the
code allows but no one has decided) with A/B/C options phrased as user-observable
outcomes. Implementers verify their work against these scenarios.

### `discovery/routing.yaml`
**The governance decision, mechanically derived.** Which route the policy table
matched (`no-doc | amend-spec | new-spec | prd-chain | escalate`), the matched
rule, why every other rule did *not* match, the evidence (decree intent-check
output, blast radius, the contract to reuse as `file:line`), `repo_commit` (the
git HEAD that pins every line-number claim), and the `gate:` block recording the
human's approval and OPEN-scenario decisions.

### `discovery/spec-draft.md`
The implementer's brief — self-sufficient by contract: acceptance criteria derived
1:1 from the Gherkin, a ≤10-line technical design naming the contract to reuse,
integration guardrails (conflicting PRs), and a **Manual verification** section
with the start state and numbered steps to reach the affected surface (copied from
`repro/repro.md`; states why, if repro could not run). An implementing session
should need nothing else.

---

## `repro/` — stage R: live reproduction (present when a repro trigger fired)

### `repro/repro.md`
The reproduction record: a stated, reachable start state (dev command + page +
preconditions), numbered steps a human can re-run in ~60 seconds, each step's
observable result, and the concrete form of any question the repro was meant to
make answerable. A failed reproduction is documented honestly here — that is a
finding, not a gap.

### `repro/exhibits/<n>-<slug>.png`
One screenshot per state, numbered in step order (`1-baseline.png`,
`2-dropdown-open.png`, …). Captured live this run — never reused from history.
They serve three consumers: the gate's questions, the spec draft's Manual
verification, and the eventual PR's "before" evidence.

---

## `report/` — on demand: the dossier

### `report/dossier.html`
A self-contained HTML rendering of this run (fixed template, screenshots
embedded), published as a private artifact. It is a **view, never a source**:
every claim in it traces back to the files above; nothing in it is new
information. If the dossier and an artifact disagree, the artifact wins.

---

## `runs/` — archived history (do not read)

### `runs/<timestamp>/…`
Complete snapshots of previous runs, moved here wholesale by step 0 before each
new run begins. Possibly produced by older plugin versions. No skill, agent, or
report may open, list, or cite anything under this directory — determinism
depends on it. Humans may of course dig here; that is what it is for.
