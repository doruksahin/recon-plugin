## v0.21.0 (2026-08-11)

### Features

- **repro**: recover a stranded recorder start without killing a foreign server

### Bug Fixes

- **tools**: make the release and activation rails fail honestly

## v0.20.0 (2026-08-11)

### Features

- **review**: add version-scoped team review lifecycle

### Bug Fixes

- **tools**: keep the system map coherent during a bump
- **review**: accept canonical YAML dates
- **tools**: accept unquoted UTC YAML timestamps
- **review**: require private GitHub evidence storage

## v0.19.0 (2026-08-05)

### BREAKING CHANGE

- triage.yaml now requires requirement_coverage and decision_audit closure records before verification.

### Features

- **improvements**: retain requirement closure lifecycle
- **triage**: enforce closure with replay verification

### Bug Fixes

- **governance**: close Decree report verification gaps
- **governance**: verify complete Decree reports
- **triage**: bind file evidence to descriptors
- **governance**: make Decree reports portable

## v0.18.0 (2026-08-03)

### Features

- **discovery**: deliver approved READY packets to Jira

## v0.17.0 (2026-08-02)

### BREAKING CHANGE

- recon-state must present the publish question from
`record-publish-gate.sh <TICKET> question` and record every answer through
`record-publish-gate.sh <TICKET> answer <published|declined> "<verbatim>"`,
which writes the new registered artifact state/publish-gate.yaml.
- recon-discovery must obtain the one-time handoff-style answer
through `set-governance.sh question` + `set-governance.sh answer <value> <tool>
"<verbatim>"`. `answer` refuses — and persists nothing — without the
developer's exact words.
- the BLOCKED/NEEDS_INFO posting path must render
triage/jira/post-gate-questions.txt before presenting the gate and record every
answer in triage/jira/post-gate.yaml (exchanges list, each entry with
presented/answer_verbatim/outcome, outcome in posted|edited|declined, exactly
one terminal entry last) — verify-post-gate.sh rejects a run without them, and
log-event.sh's closed vocabulary gains post_declined.

### Features

- **gate**: record the state-canvas publish exchange
- **gate**: record the handoff-style exchange beside the config
- **gate**: record the posting-gate exchange from railed questions

## v0.16.0 (2026-08-02)

### BREAKING CHANGE

- discovery/gate.yaml must now carry an exchanges list (one
entry per OPEN-N plus PACKAGE, each with presented/answer_verbatim/resolution,
recommendation on OPEN entries) and the gate must be presented from the
rail-rendered discovery/gate-questions.md — verify-discovery.sh post-gate
rejects packages without them. OPEN scenario options in discovery.md must be
visible '- A: <outcome>' list lines with exactly one option ending in
'(recommended)'.
- recon-repro requires proofshot@1.6.0 and agent-browser
on PATH (npm install -g proofshot@1.6.0 agent-browser); reproduced: true
packages without a recorded session bundle now fail verify-repro.sh, and
repro/session/* joins the artifact registry.

### Features

- **report**: point the dossier at the recorded session bundle
- **gate**: record the gate exchange verbatim from railed questions
- **repro**: render the session viewer at evidence time
- **repro**: record every repro session with a pinned proofshot runtime

### Bug Fixes

- **tools**: make the git fixtures hermetic against inherited env
- **repro**: stop the dev server the recording started

## v0.15.0 (2026-08-02)

### BREAKING CHANGE

- Repro and Discovery artifacts now require fixed metadata, stable visible IDs, a complete pinned route envelope, and verifier-clean parity before handoff.

### Features

- **pipeline**: verify the company handoff chain

## v0.14.1 (2026-08-02)

### Bug Fixes

- **portability**: correct Codex host detection, invocation syntax, and network policy

## v0.14.0 (2026-08-02)

### Features

- **portability**: support native local Codex execution

## v0.13.0 (2026-08-02)

### Features

- **state**: recon-state skill — derived state canvas, ledger timeline, stable artifact URL
- **workspace**: cross-run ticket ledger — history.ndjson + log-event rail

## v0.12.0 (2026-08-02)

### Features

- **publish**: recon-publish skill — gated release + distribution as one flow

## v0.11.0 (2026-08-02)

### Features

- **tools**: root CLAUDE.md editor guidance, with its skill list enforced

## v0.10.0 (2026-08-02)

### Features

- **help**: recon-help skill + doctor.sh — help that cannot drift
- **discovery**: handoff-style question and report speak outcomes

## v0.9.0 (2026-08-02)

### Features

- **tools**: coherence rail — one owner per fact, mirrors checked pre-commit
- **triage**: derived disposition, verbatim quotes, rendered comment

## v0.8.0 (2026-08-01)

### Features

- **tools**: commitizen release rail — generated changelog, commit-msg gate
- **tools**: pre-commit link check — lychee + working-tree path resolution

## v0.7.0 (2026-08-01)

### Features

- **report**: render-only mode + blockers question packs; rail demands n>=1
- **triage**: n+4 progressive-disclosure comment + attachment delivery path
- **scripts**: register bundle-manifest in workspace lint
- **scripts**: verify-comment-shape.sh comment rail (n+4)
- **scripts**: attach-artifacts.sh replace-not-accumulate rail
- **scripts**: package-artifacts.sh delivery-bundle rail
- SRP routing stage — governance adapter skill, generic rail, opt-in ladder
- stage-scoped workspace layout + lint rail + per-workspace index.md
- recon-report skill — HTML dossier as a pure view over run artifacts
- mandatory primary-scenario repro for UI defects + Manual verification in spec drafts
- deterministic re-runs — step-0 archive, runs/ read ban, marker-signed comments
- actionable outros — blocked re-entry, per-route handoff, reject path
- recon plugin v0.1.0 — triage, discovery, repro skills

### Bug Fixes

- **triage**: close review gaps — draft-time mentions, n>=1 posting rule, resolution rail
- **scripts**: verify-comment-shape.sh — anchor links line, marker-last, numbering, CRLF
- **scripts**: attach-artifacts.sh — clear stale audit file, honest delete output
- **scripts**: package-artifacts.sh — space-safe include list, empty-workspace guard
- once-per-run step-0 guard + gate schema + report/naming polish
- create recon workspace dir before curl; tolerate missing decree CLI

### Internal

- step-0 as shipped script + complete artifact contract
