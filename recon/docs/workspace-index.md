# Recon workspace — what each file is

You are looking at `$RECON_ROOT/<TICKET>/` — the working directory of one recon
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
the starting host/surface, and the ticket. Its presence means "a current run exists"; its age drives the
once-per-run guard. If you need to know whether artifacts here are trustworthy
under the current skill version, this is the file to check.

### `index.md`
This file. Copied verbatim from the plugin's `docs/workspace-index.md` by the
step-0 script — never hand-edited, always identical across tickets.

### `history.ndjson`
The cross-run ticket ledger: one JSON line per pipeline event (`run_started`,
`verdict`, `routed`, `gate_answered`, …), appended ONLY by `log-event.sh`
(closed vocabulary, with current host/surface provenance) and preserved across runs by the step-0 script. It is
OUTPUT, NEVER EVIDENCE (invariant 16): no check or decision reads it — it
exists so humans and the state canvas can tell the ticket's story.

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
per fetch, named after what it is. On the posting path, draft time adds
`aux-user-<slug>.json` — the Jira user-search responses that resolve each blocker
owner's handle to an accountId. Their role: every evidence line in
`triage.yaml` that cites an external resource has its raw material here, so the
verdict is auditable without re-fetching anything.

### `triage/triage.yaml`
**The stage-1 verdict.** Disposition (`READY | BLOCKED | NEEDS_INFO`), the six
check results, cross-checks (status drift, stale blockers), blockers with named
owners (handles + resolved accountIds), ride-along PR conflicts, and one TYPED
evidence entry per claim (`kind: quote | http | git | file | note`). The
disposition is derived from the checks, and every quote is verified verbatim
against `ticket.json`, by `verify-triage.sh`. Discovery's precondition: it will
not start unless this says `READY`.

### `triage/jira/` — present only if the posting path ran (BLOCKED/NEEDS_INFO)
- **`comment.txt`** — the exact comment body for Jira, RENDERED from
  `triage.yaml` + `meta.yaml` by `render-comment.sh` (never hand-written) and
  saved *before* the human approved posting. The body is the mechanical n+4
  progressive-disclosure shape — header, one line per blocker, attachment-links
  line, reply line, marker line — so full detail never lives here; it lives in
  the dossier's question packs. Ends with the `~recon-triage v<version>~` marker.
- **`bundle-manifest.txt`** — written by `package-artifacts.sh`: one line per
  bundled file (size + relative path). The zip it describes
  (`recon-artifacts-<TICKET>.zip`) is staged in a temp dir — never inside this
  workspace — and attached to the Jira ticket on an approved post; its contents
  ARE this workspace, so the manifest is the exact record of what was delivered.
- **`post-gate-questions.txt`** — the posting gate exactly as presented, rendered
  by `render-post-gate.sh` from `comment.txt` + `bundle-manifest.txt` + the
  staged zip: the comment bytes that will be posted, the attachment names with
  their real sizes, the bundle file count, and the three options. Never written
  by hand — to change it, edit `triage.yaml` and re-render the chain.
- **`post-gate.yaml`** — the posting-gate exchange record: one entry per time
  the gate was presented, each holding the user's exact answer and its mapped
  `outcome` (`posted`, `edited`, or `declined`). The Edit loop is visible here,
  and a run where a human said "don't post" says so — it no longer looks like
  a session that died before reaching the gate.
- **`post-result.json`** — the Jira API response after an approved POST/edit.
  Proof of what actually landed on the ticket — audit evidence for THIS run.
  Edit-vs-create detection always comes from the live ticket's fetched comments,
  never from this file.
- **`attach-result.json`** — written by `attach-artifacts.sh` on the posting
  path: the IDs of the stale recon attachments it deleted plus the upload
  responses for the new ones. Cleared at the start of each attach run, so if it
  is absent after a run, the attach never completed.

---

## `discovery/` — stage 2: code discovery (present when triage said READY)

### `discovery/discovery.md`
The behavior contract: Gherkin scenarios for the required behavior, the
must-not-change regression behaviors, and any OPEN scenarios (edge cases the
code allows but no one has decided) with A/B/C options phrased as user-observable
outcomes. Headings carry stable `REQ-N`, `REG-N`, and `OPEN-N` IDs; those IDs
join the contract to brief checkboxes and gate resolutions. Implementers verify
their work against these scenarios. An evidenced `No scenarios:` declaration is
valid when no behavior contract is possible.

### `discovery/gate-questions.md`
The gate questions exactly as presented — rendered by `render-gate.sh` from
`discovery.md` + `routing.yaml`, never written by hand: one block per `OPEN-N`
(scenario, options, the single `(recommended)` marker) plus the `PACKAGE`
block. The skill quotes these bytes at the gate, so what the approver was
asked is on the record, not a chat paraphrase.

### `discovery/gate.yaml`
The human approval record: whether the package was approved, when, every
`OPEN-N` decision the gate resolved (exact key parity, including rejected
packages), the verbatim `exchanges` (per question: what was presented, the
recommendation, the user's exact answer, and its mapped resolution), and — on
a reject — the reason. The gate is discovery's act, so its record lives here,
separate from routing.

### `discovery/spec-draft.md`
The implementer's brief — self-sufficient by contract: acceptance criteria derived
1:1 from the Gherkin with the same stable IDs, a ≤10-line technical design naming the contract to reuse,
integration guardrails (conflicting PRs), and a **Manual verification** section
with the start state and numbered steps to reach the affected surface (copied from
`repro/repro.md`; states why, if repro could not run). An implementing session
should need nothing else. This file is intentionally absent when routing says
`brief_kind: none`; that is a verified route outcome, not an incomplete stage.

---

## `route/` — the routing stage (present after discovery routed)

### `route/routing.yaml`
**The implementation path, mechanically derived — and the handoff as data.**
Which route the routing stage chose, the matched rule, why every other rule did
*not* match, how governance was resolved (`governance` + `governance_source` —
the developer's standing choice always outranks detection), `brief_kind` (what
kind of brief discovery must draft), `repo_commit` (the full SHA-1/SHA-256 git
HEAD object ID that pins every
line-number claim), and `handoff:` — the exact next commands, which every
consumer quotes verbatim and never rewrites. Produced by a plain script when no
governance system is in play, or by the team's governance adapter skill when one
is; the adapter's vocabulary appears only in runs that chose it.

### `route/aux-intent-check.txt`
Raw output of the governance adapter's check command — present only when an
adapter ran. The `evidence` lines in `routing.yaml` quote from it; this file
makes them auditable in full.

---

## `repro/` — stage R: live reproduction (present when a repro trigger fired)

### `repro/repro.md`
The reproduction record: fixed frontmatter names the ticket, whether reproduction
succeeded, its reachable start state, and any failure reason. On success,
contiguous numbered steps are human-rerunnable in ~60 seconds and each references
the same-numbered exhibit. On failure, the reason is explicit and no success
steps or exhibits are invented. `verify-repro.sh` accepts only regular,
non-symlinked in-workspace paths and validates structure, PNG chunk/order/CRC/
zlib/IEND integrity, and coarse current-run provenance before any caller consumes
it; the skill separately judges whether each image visibly proves its claim.

### `repro/exhibits/<n>-<slug>.png`
One screenshot per state, numbered in step order (`1-baseline.png`,
`2-dropdown-open.png`, …). Captured live this run by a logged `screenshot`
action inside the recorded session — never reused from history. They serve
three consumers: the gate's questions, the spec draft's Manual verification,
and the eventual PR's "before" evidence. Missing, orphaned, corrupt, stale,
or misnumbered images fail package verification.

### `repro/session/` — the recorded session bundle
Finalized by `record-repro.sh stop`: `session-log.json` (the timestamped
action log `repro.md` steps are transcribed from), `session.webm` (the full
session video — in the delivery zip, a PM can watch the anomaly),
`metadata.json`, `console-output.log`, and `server.log` when the rail started
the dev server. Required for every successful repro; a failed repro keeps the
bundle only when the recording actually started. `verify-repro.sh`
cross-checks exhibits against the logged screenshot actions.

---

## `report/` — the dossier (on demand, or auto on the posting path)

### `report/dossier.html`
A self-contained HTML rendering of this run (fixed template, screenshots
embedded). Produced in one of two modes: **on demand** (the user asked for a
report) it is published as a private artifact; on the **posting path**
(BLOCKED/NEEDS_INFO) it is rendered render-only and attached to the Jira ticket
on an approved post as `recon-dossier-<TICKET>.html` alongside
`recon-artifacts-<TICKET>.zip` — no artifact publishing. In both modes it is a
**view, never a source**: every claim in it traces back to the files above;
nothing in it is new information.
If the dossier and an artifact disagree, the artifact wins.

---

## `state/` — the living state canvas (present once recon-state ran)

### `state/state.yaml`
Flat derived state, written by `derive-state.sh` from artifact presence alone:
the stop label, one status per canvas node, `fact.*` counts, a canonical
`next_action`, and neutral next-action prose. Re-derived on every refresh.

### `state/canvas.html`
The node-canvas view, rendered mechanically from `state.yaml` (+ the ledger
timeline) by `render-state-canvas.sh`. Republished to the ticket's stable
artifact URL only when the local host supports stable publishing; otherwise it
remains a local LIVING view, unlike the frozen dossier.

### `state/publish-gate.yaml`
The publish gate's exchange record, appended by `record-publish-gate.sh`: the
question exactly as the rail asks it, the options, the user's exact words, and
whether that answer was `published` or `declined`. It exists so an absent
`artifact-url` stops meaning three things at once — never asked, asked and
declined, or a host that cannot publish at all. Render-only hosts never create
it. Like `artifact-url`, it belongs to the current run.

### `state/artifact-url`
Exactly one line: the ticket's stable canvas artifact URL, written after the
first gated publish by a host with `publish_stable_url`. Render-only hosts
never create or modify it.

---

## `runs/` — archived history (do not read)

### `runs/<timestamp>/…`
Complete snapshots of previous runs, moved here wholesale by step 0 before each
new run begins. Possibly produced by older plugin versions. No skill, agent, or
report may open, list, or cite anything under this directory — determinism
depends on it. Humans may of course dig here; that is what it is for.
