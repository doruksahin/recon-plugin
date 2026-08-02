# recon/scripts/ — the rails

Every script here is a rail: a step with zero model freedom, invoked by a
SKILL.md with `bash "<skill base dir>/../../scripts/<name>.sh" <TICKET>`. Exit
codes are uniform — 0 clean, 1 violation/failure, 2 missing inputs or broken
install. Mechanical checks are `find`-based, never `ls`/`grep` (user shells
alias those). Adding a file here without a role line below fails
`tools/check-coherence.sh` (role coverage).

| File | Role |
| --- | --- |
| `fresh-workspace.sh` | Step 0: archives every prior artifact into `runs/<ts>/`, stamps `meta.yaml` (plugin version + start time), copies `index.md`. Once-per-run guard (30 min). |
| `lint-workspace.sh` | Invariant 10: every workspace file must match a pattern in `../docs/registry.yaml`; also the governance vocabulary fence when routing resolved to `none`. Every stage runs it in its Report step. |
| `verify-triage.sh` | Invariant 15: re-derives the disposition from the six checks, validates the `triage.yaml` schema, verifies every `kind: quote` verbatim against `ticket.json`. Wrapper over `triage-tools.py verify`. |
| `render-comment.sh` | Invariant 13: emits `triage/jira/comment.txt` from `triage.yaml` + `meta.yaml` — the model never writes the comment. Wrapper over `triage-tools.py render`. |
| `triage-tools.py` | Shared engine behind verify-triage.sh and render-comment.sh: hand-rolled parser for the fixed `triage.yaml` schema (no PyYAML), disposition derivation, quote corpus + normalization, comment rendering. Not invoked directly. |
| `verify-comment-shape.sh` | Invariant 13's independent check: `comment.txt` is exactly n+4 non-empty lines with numbered `*i. Title* — [~mention]: ask?` blocker lines and the marker line last. |
| `package-artifacts.sh` | Zips the workspace (never `runs/`) into `recon-artifacts-<TICKET>.zip` in a temp dir and writes `bundle-manifest.txt` for the gate display. |
| `attach-artifacts.sh` | Invariant 14: deletes stale `recon-*-<TICKET>.*` Jira attachments, uploads the new ones, writes `attach-result.json`. Always runs BEFORE the comment posts. |
| `detect-governance.sh` | Resolves the governance ladder: env var → `~/.config/recon/config` → repo probe. Detection alone never opts a developer in (`undecided` → one persisted question). |
| `set-governance.sh` | Persists the user's governance answer to `~/.config/recon/config` so the question is asked once. |
| `route-generic.sh` | The `governance: none` routing producer: writes `route/routing.yaml` with route, matched rule, rule trace, and the verbatim `handoff:` block. |
| `doctor.sh` | The recon-help engine: prints version (from its own plugin.json), the skill list (from each sibling SKILL.md's frontmatter description), and live setup checks (Jira env + GET /myself, handoff style via detect-governance.sh). Read-only; every printed fact is derived at run time so help cannot drift. |
| `activate-plugin.sh` | The recon-publish distribution rail — plugin-AGNOSTIC (built for later extraction to a shared devkit): reads the source repo's marketplace.json + each plugin.json, copies the new version into the plugin cache (old pinned dirs never deleted), repoints `installed_plugins.json` (validated first — surprise shape fails loudly, that file is Claude Code internal format), fast-forwards the marketplace clone. |

New-script checklist: role line here · registry entry in `../docs/registry.yaml`
if it writes a new workspace artifact · rails/trigger tables in
`../docs/pipeline.md` · caller step in the invoking SKILL.md — then let
`check-links.sh` + `check-coherence.sh` confirm nothing was missed.
