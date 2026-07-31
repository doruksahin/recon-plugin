# recon

Deterministic Jira task recon pipeline for Claude Code. Runs **before** any planning: decides whether a task is actionable, maps the code surface with evidence, and routes it into [decree](https://github.com/doruksahin/decree) — ending at a human approval gate, never at code.

```
/recon:recon-triage ATT-1234
  ├─ six blocker checks → triage.yaml
  ├─ BLOCKED → drafts PM questions (+ screenshots when UI-related) → you post → stop
  └─ READY  → auto-chains recon-discovery
               ├─ code surface + Gherkin contract + decree intent-check
               ├─ routing: no-doc | amend-spec | new-spec | prd-chain | escalate
               ├─ UI defects + UI edge cases → recon-repro captures repro steps + screenshots
               └─ approval gate → prints decree handoff commands → stop
```

Your touchpoints per ticket: answer the gate, review the PR. That's it.

## Install

```
/plugin marketplace add doruksahin/recon-plugin
/plugin install recon@recon-plugin
```

## Prerequisites (each user, own machine)

1. **Your own Jira API token** in `~/.config/jira/env` (never share tokens):

   ```bash
   mkdir -p ~/.config/jira && cat > ~/.config/jira/env <<'EOF'
   JIRA_HOST=https://<your-org>.atlassian.net
   JIRA_EMAIL=<you>@<org>.com
   JIRA_API_TOKEN=<create at id.atlassian.com → Security → API tokens>
   EOF
   chmod 600 ~/.config/jira/env
   ```

2. **decree CLI** (optional but recommended) — powers the governance routing (`decree intent-check`). Without it, discovery records `governance: none` and routes without rule 1.
3. **gh CLI, logged in** — used by triage's conflict check (open PR scan). Degrades gracefully if absent.

## Skills

| Skill | Stage | What it does |
|---|---|---|
| `/recon:recon-triage` | 0 | Blocker verdict (READY/BLOCKED/NEEDS_INFO) from six mechanical checks; drafts owner-addressed questions; never plans |
| `/recon:recon-discovery` | 1 | Code surface with `file:line` evidence, Gherkin behavior contract, deterministic decree routing, approval gate |
| `/recon:recon-repro` | on demand | Live-reproduces observable behavior: numbered steps + one screenshot per state; honest about failed repros |

## I/O contract

| Skill | Input | Writes (all under `~/.claude/recon/<TICKET>/`) | External side effects |
|---|---|---|---|
| `recon-triage` | ticket ID/URL | `meta.yaml`, `ticket.json`, `triage.yaml`, auxiliary `aux-<slug>.json` fetches; on posting: `comment.txt`, `post-result.json`, `attach-result.json`; prior-run artifacts archived to `runs/<timestamp>/` | at most one Jira comment (marker-signed) — drafted first, sent only after your explicit approval |
| `recon-discovery` | ticket ID (READY triage) | `discovery.md`, `routing.yaml`, `spec-draft.md` | none — prints decree handoff commands, never executes them |
| `recon-repro` | ticket ID + claim | `repro.md` + `repro-*.png` | none (local only: boots the dev server, shows screenshots) |

Nothing is ever pushed, committed, or posted anywhere without an explicit per-action approval. Jira gets at most one short comment per stage — edited on re-runs (detected by the `recon-triage` marker line), never appended.

## Deterministic re-runs

Every triage run starts from a clean workspace: step 0 runs `recon-triage/scripts/fresh-workspace.sh`, which archives all prior artifacts (dotfiles included) into `~/.claude/recon/<TICKET>/runs/<timestamp>/` and stamps the new run with `meta.yaml` (plugin version + start time). The step lives in a script — not inline in the skill — so it executes byte-identically every run, and it runs exactly once per run: a re-invocation within 30 minutes is refused (`SKIPPED`) so a run can never archive its own in-progress artifacts. No skill may read anything under `runs/` — the only inputs are the live Jira API, git, and `gh`. Recon's own Jira comments carry a marker line and are excluded from all evidence checks, so a run is never influenced by the output of a previous (possibly older-versioned) run. Every file a run may write is declared in the I/O contract above — an undeclared artifact is a contract violation.

## Principles baked in

- Evidence per claim (`file:line` or command output) — no claim without it.
- No prose unknowns: every unknown is resolved by a command or becomes a question with a named owner.
- Human-facing questions are concrete: numbered repro steps, real entity names, user-observable outcomes; internal identifiers banned.
- Recon describes, the routing table decides, the human confirms, decree executes.
- Every visible-UI defect ships with a reproduce-the-bug path: discovery invokes recon-repro for the primary scenario (mechanical trigger: defect + visible UI + not no-doc), and `spec-draft.md` always carries a Manual verification section — start state, numbered steps, BEFORE/AFTER — so the implementer never re-derives how to reach the surface.
