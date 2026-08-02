# recon/scripts/ — the rails

Every script here is a rail: a step with zero model freedom, invoked by a
SKILL.md with `bash "<skill base dir>/../../scripts/<name>.sh" <TICKET>`. Exit
codes are uniform — 0 clean, 1 violation/failure, 2 missing inputs or broken
install. Mechanical checks are `find`-based, never `ls`/`grep` (user shells
alias those). Adding a file here without a role line below fails
`tools/check-coherence.sh` (role coverage).

| File | Role |
| --- | --- |
| `fresh-workspace.sh` | Step 0: passes base preflight, archives prior artifacts into `runs/<ts>/`, stamps `meta.yaml` (version, time, starting host/surface), copies `index.md`. Once-per-run guard (30 min). |
| `lint-workspace.sh` | Invariant 10: every workspace file must match a pattern in `../docs/registry.yaml`; also the governance vocabulary fence when routing resolved to `none`. Every stage runs it in its Report step. |
| `verify-triage.sh` | Invariant 15: re-derives the disposition from the six checks, validates the `triage.yaml` schema, verifies every `kind: quote` verbatim against `ticket.json`. Wrapper over `triage-tools.py verify`. |
| `verify-repro.sh` | Invariant 17 repro gate: validates fixed frontmatter, honest success/failure shape, contiguous visible step/exhibit parity (HTML-comment tokens do not count), regular non-symlinked in-workspace paths, full PNG chunk/CRC/zlib/IEND structure, no orphans, and coarse current-run provenance. Wrapper over `artifact-tools.py verify-repro`. |
| `verify-discovery.sh` | Invariant 17 handoff gate: validates regular in-workspace inputs, visible stable Gherkin IDs, the complete route producer/trace/full-Git-object envelope, route/brief shape, visible implementation-checkbox or problem-statement ID parity, block-scalar handoff, and exact approved OPEN resolution joins. Wrapper over `artifact-tools.py verify-discovery`. |
| `render-comment.sh` | Invariant 13: emits `triage/jira/comment.txt` from `triage.yaml` + `meta.yaml` — the model never writes the comment. Wrapper over `triage-tools.py render`. |
| `triage-tools.py` | Shared engine behind verify-triage.sh and render-comment.sh: hand-rolled parser for the fixed `triage.yaml` schema (no PyYAML), disposition derivation, quote corpus + normalization, comment rendering. Not invoked directly. |
| `artifact-tools.py` | Dependency-free parser/validation engine behind the repro and Discovery verifier wrappers, including shared rendered/semantic Markdown views that prevent comments and code examples from becoming evidence. It reads current-run packages and writes nothing. Not invoked directly. |
| `verify-comment-shape.sh` | Invariant 13's independent check: `comment.txt` is exactly n+4 non-empty lines with numbered `*i. Title* — [~mention]: ask?` blocker lines and the marker line last. |
| `package-artifacts.sh` | Zips the workspace (never `runs/`) into `recon-artifacts-<TICKET>.zip` in a temp dir and writes `bundle-manifest.txt` for the gate display. |
| `attach-artifacts.sh` | Invariant 14: deletes stale `recon-*-<TICKET>.*` Jira attachments, uploads the new ones, writes `attach-result.json`. Always runs BEFORE the comment posts. |
| `detect-governance.sh` | Resolves the governance ladder: env var → `~/.config/recon/config` → repo probe. Detection alone never opts a developer in (`undecided` → one persisted question). |
| `set-governance.sh` | Persists the user's governance answer to `~/.config/recon/config` so the question is asked once. |
| `route-generic.sh` | The `governance: none` routing producer: requires a current Git commit, then writes `route/routing.yaml` with route, matched rule, rule trace, full commit object ID, and the verbatim `handoff:` block. |
| `log-event.sh` | Invariant 16: appends one JSON line with current host/surface per pipeline event to `history.ndjson` (closed vocabulary; output, never evidence). |
| `derive-state.sh` | Closed state derivation table → `state/state.yaml` with stop, nodes, facts, canonical `next_action`, and host-neutral next prose. Unrecognized combinations exit 1. |
| `render-state-canvas.sh` | Fills the recon-state `template.html` from `state/state.yaml` (+ the ledger as timeline VIEW) → `state/canvas.html`. An unresolved template marker fails the render — the model authors nothing in the canvas. |
| `doctor.sh` | Recon-help engine: prints version, generated skill list, detected host/surface, host-rendered entrypoint, shared triage preflight, and handoff style. Read-only. |
| `activate-plugin.sh` | The recon-publish distribution rail — plugin-AGNOSTIC (built for later extraction to a shared devkit): reads the source repo's marketplace.json + each plugin.json, copies the new version into the plugin cache (old pinned dirs never deleted), repoints `installed_plugins.json` (validated first — surprise shape fails loudly, that file is Claude Code internal format), fast-forwards the marketplace clone. |
| `activate-codex-plugin.sh` | Codex activation rail: requires clean same-origin source/configured checkouts at the released commit, rejects ignored/untracked, sparse/assume-unchanged, or special plugin entries, attests the materialized plugin tree before/after public-CLI installation and again after the install report, then verifies Codex's enabled version/path; if not configured, prints setup commands. |
| `reconctl.sh` | Local runtime contract: root/ticket paths, Claude/Codex host and surface detection, canonical invocation rendering, capability levels, scalar preflight, and one pure-output atomic `start base|triage` snapshot. Read-only. |

New-script checklist: role line here · registry entry in `../docs/registry.yaml`
if it writes a new workspace artifact · rails/trigger tables in
`../docs/pipeline.md` · caller step in the invoking SKILL.md — then let
`check-links.sh` + `check-coherence.sh` confirm nothing was missed.
