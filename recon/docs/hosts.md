# Local Host Contract

Recon `0.14.0` executes on Claude Code and local Codex (app or CLI). Hosted
ChatGPT, Codex Cloud, MCP, remote state, and remote publishing are not runtime
targets for this release.

Before a skill's first path or tool action, resolve the contract mechanically:

```bash
CTL="<skill base dir>/../../scripts/reconctl.sh"
RECON_ROOT="$(bash "$CTL" root)"
RECON_HOST="$(bash "$CTL" detect-host)"
RECON_SURFACE="$(bash "$CTL" detect-surface)"
bash "$CTL" capabilities "$RECON_HOST"
bash "$CTL" preflight <base|triage>
```

`RECON_HOST` and `RECON_SURFACE` are optional explicit overrides and have the
highest precedence. Without them, `reconctl.sh` recognizes Claude Code and
Codex environment signals; an unrecognized environment resolves to `unknown`
and receives no optimistic capabilities.

A nested session carries both marker families — Codex exports its markers into
every command it runs, and `CLAUDECODE` is inherited by every child process —
so presence alone cannot say which host is driving. Both present resolves to
`unknown`, `preflight` emits `check.host: WARN`, and `RECON_HOST` is the only
way to decide. Never infer the host from anything else.

Shell calls are isolated on some hosts. For later calls, either pass
`RECON_ROOT`, `RECON_HOST`, and `RECON_SURFACE` in that call or substitute the
resolved absolute root in the command. Rails that need identity call
`reconctl.sh` themselves, so provenance does not depend on model memory.

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
| Browser/repro | preview/browser tools | in-app browser or computer-use when available |
| Local shell/filesystem | available | available |
| Network/Jira | local environment; `preflight triage` decides | `CODEX_SANDBOX_NETWORK_DISABLED=1` means unreachable; otherwise `preflight triage` decides |

The table is explanatory. `reconctl.sh capabilities` is the executable source
for host mechanics.

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
5. Missing browser capability produces an honest failed-repro finding; it
   never permits fabricated steps or screenshots.
6. Host mechanics may change invocation and presentation, not artifact
   schemas, evidence requirements, routing, or approval semantics.
