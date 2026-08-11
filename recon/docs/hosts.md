# Local Host Contract

<!-- coherence:version -->Recon `v0.20.0` executes on Claude Code and local Codex (app or CLI). Hosted
ChatGPT, Codex Cloud, MCP, remote state, and remote publishing are not runtime
targets for this release.

Before a skill's first path or tool action, capture the contract and preflight
in one pure-output invocation:

```bash
CTL="<skill base dir>/../../scripts/reconctl.sh"
bash "$CTL" start <base|triage|repro>
```

The snapshot emits `root`, `host`, `surface`, namespaced `capability.*` lines,
the requested `profile`, each preflight check, and one final
`preflight: PASS|FAIL` verdict. It writes no context file and creates no
workspace state.
Retain the printed values for the skill run. The older scalar commands remain
available for point lookups and compatibility, but skill startup does not
reconstruct one contract from separate shell calls.

`RECON_HOST` and `RECON_SURFACE` are optional explicit overrides and have the
highest precedence. Without them, `reconctl.sh` recognizes Claude Code and
Codex environment signals; an unrecognized environment resolves to `unknown`
and receives no optimistic capabilities.

A nested session carries both marker families — Codex exports its markers into
every command it runs, and `CLAUDECODE` is inherited by every child process —
so presence alone cannot say which host is driving. Both present resolves to
`unknown`, `preflight` emits `check.host: WARN`, and `RECON_HOST` is the only
way to decide. Never infer the host from anything else.

Shell calls are isolated on some hosts. For later calls, either pass the
snapshot values in that call or substitute the resolved absolute root. The
snapshot is startup context, not frozen runtime identity: rails that record
provenance call `reconctl.sh` themselves and therefore observe the current host
and surface even after a cross-harness continuation.

The workspace default remains `~/.claude/recon` for compatibility. Set an
absolute `RECON_ROOT` to use another local or shared directory.

## Capabilities

| Capability | Claude Code | Local Codex |
| --- | --- | --- |
| Ask or approve | `AskUserQuestion` | `request_user_input` when available; otherwise ask and stop |
| Invoke a Recon skill | `Skill` tool or `/recon:<skill>` | Native skill invocation or `$<skill>` |
| Render local HTML | available | available |
| Display a local file | `SendUserFile` | Markdown with an absolute local path |
| Publish once | native Artifact tool | unavailable; render-only |
| Update one stable URL | native Artifact tool with the saved URL | unavailable; never write `state/artifact-url` |
| Repro recorder | pinned proofshot + agent-browser CLIs via `record-repro.sh` (`preflight repro` decides) | same — one recorder contract on every host |
| Local shell/filesystem | available | available |
| Network/Jira | local environment; `preflight triage` decides | `CODEX_SANDBOX_NETWORK_DISABLED=1` means unreachable; otherwise `preflight triage` decides |

The table is explanatory. `reconctl.sh start` and `capabilities` are the
executable sources for host mechanics.

## Package parity and drift prevention

Recon is one workflow with two native host packages. The shared workflow is
not two independently maintained copies: the same `recon/skills/*/SKILL.md`
files, `recon/scripts/` rails, docs, and templates execute on both hosts. Host
mechanics may differ only through the capability contract above.

| Concern | Claude Code | Codex | Ownership and rule |
| --- | --- | --- | --- |
| Runtime skills and rails | Same shipped files | Same shipped files | Author the shared source once; never fork a host-specific skill body. |
| Native manifest | `recon/.claude-plugin/plugin.json` | `recon/.codex-plugin/plugin.json` | The Claude manifest is canonical. The Codex manifest is generated; do not hand-edit it. |
| Marketplace registration | `.claude-plugin/marketplace.json` | `.agents/plugins/marketplace.json` | The Codex marketplace entry is generated from the canonical source; do not hand-edit it. |
| Skill UI metadata | Claude discovers each registered skill | `skills/*/agents/openai.yaml` | Codex UI metadata is generated from the shared skill frontmatter plus the generator's interface map; do not hand-edit it. |
| User-facing invocation | `Skill` or `/recon:<skill>` | Native selection or `$<skill>` | Render through `reconctl.sh invocation`; never persist either spelling in durable artifacts. |
| Presentation and publication | Can publish artifacts and stable URLs | Render-only; cannot write `state/artifact-url` | Follow `reconctl.sh capabilities`; this does not alter workflow semantics. |

The package differences above are intentional. They must never change the
artifact schemas, evidence requirements, routing rules, gate semantics, or
shared skill instructions.

### Source-to-install synchronization

The source repository is the only editable location. An installed Claude cache,
Codex marketplace clone, or host skill directory is a distribution mirror, not
an alternate source of truth. In particular, do not copy or symlink individual
Recon skills into generic host skill directories: each skill relies on its
siblings at the plugin root (`scripts/`, `docs/`, templates, and manifest), and
that bypasses native-plugin verification.

For every change to canonical manifest fields or skill frontmatter:

1. Edit the shared source only.
2. Run `python3 tools/generate-adapters.py` to update the checked-in Codex
   adapters.
3. Run `python3 tools/generate-adapters.py --check` and
   `bash tools/check-coherence.sh`. A failing check is drift: repair the owner
   or regenerate the named mirror; never patch an installed host copy.
4. Release through the release rail. After release approval, refresh the two
   installations only through `recon/scripts/activate-plugin.sh` (Claude) and
   `recon/scripts/activate-codex-plugin.sh` (Codex).

Codex activation is stronger than a version comparison: it rejects an
unexpected, dirty, sparse, or untracked materialized plugin tree and attests
the installed package's source commit and tree before reporting success. A
host may legitimately run an older released install until activation occurs;
that is an installation lag, not permission to edit the installed package.

### Drift response

| Observation | Required response |
| --- | --- |
| Generated-adapter check fails | Regenerate from the canonical source, review the resulting files, then commit source and generated mirrors together. |
| Coherence check fails | Treat the reported owner/mirror mismatch as the diagnosis and repair it at the owner named by the Change protocol. |
| Claude and Codex behave differently | First compare `reconctl.sh start` capability snapshots. A documented capability difference is expected; any change to shared workflow semantics is a bug. |
| A live installation differs from the released source | Do not repair the cache. Return to the source checkout, validate it, release if appropriate, and use the host activation rail. |

`recon/scripts/doctor.sh` is the read-only per-install diagnostic. Its output,
not a remembered version or a manually inspected cache, is the current host's
setup evidence.

## Canonical actions

Durable artifacts store canonical action IDs, never host commands:

- `recon.triage`
- `recon.discovery`
- `recon.repro`
- `recon.report`
- `recon.state`
- `human.approval`
- `implementation.start`

Render a human-facing skill invocation only at the point of display:

```bash
bash "$CTL" invocation recon.triage ATT-1234
```

This prints the Claude slash command, the bare-name Codex skill mention
(`$recon-triage` — Codex never namespaces a skill by its plugin), or a neutral
label for an unknown host. It is the only command renderer shared skills and
scripts may use.

## Rules

1. Stop before mutation when the required preflight profile fails.
2. Never claim a capability succeeded when `capabilities` marks it unavailable.
3. Approval gates remain gates. If no interactive tool exists, ask normally
   and stop before the side effect.
4. Only `publish_stable_url: available` may create, update, or use
   `state/artifact-url`; all other cases are render-only.
5. A failed `repro` preflight (recorder missing or version-mismatched)
   produces an honest failed-repro finding; it never permits fabricated
   steps, fabricated screenshots, or an unrecorded browser session.
6. Host mechanics may change invocation and presentation, not artifact
   schemas, evidence requirements, routing, or approval semantics.
