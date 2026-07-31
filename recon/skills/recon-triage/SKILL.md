---
description: Stage 0 blocker triage for a Jira ticket before any planning. Use when given a Jira ticket URL/ID to assess, when a task enters TODO, or when asked whether a task is blocked, ready, or actionable.
---

# Recon Triage

Read-only blocker triage: decides READY / BLOCKED / NEEDS_INFO for a Jira ticket, with evidence, before any planning or code work happens.

## Contract

- **Input:** ticket ID or URL (`ATT-1234` / `https://<host>/browse/ATT-1234`)
- **Reads:** Jira API (GET only), local git branches + `gh pr list` (read-only), ticket links via WebFetch
- **Writes:** `~/.claude/recon/<TICKET>/ticket.json`, `~/.claude/recon/<TICKET>/triage.yaml`
- **External side effects:** NONE by default. The only possible one: a single Jira comment (create, or edit of a prior recon comment) — always drafted first, sent ONLY after explicit user approval in this session.
- **May invoke:** `recon:recon-discovery` (on READY), `recon:recon-repro` (UI-related blocker questions)

---

## ⚠️ CRITICAL: Rules

1. **READ-ONLY.** You MUST NOT write code, create branches, or modify any repo. The only writes allowed are artifacts under `~/.claude/recon/<TICKET-ID>/`.
2. **NEVER post to Jira without explicit approval in this session.** You draft comments; the user approves via AskUserQuestion before any POST to the Jira API. NEVER skip this, even if the user previously approved a different comment.
3. **Every checklist answer MUST carry evidence** — a command output, a `file:line`, an HTTP status, or an exact quote from the ticket. A check without evidence is not done.
4. **The verdict MUST be the `triage.yaml` schema below**, written to `~/.claude/recon/<TICKET-ID>/triage.yaml`. Prose around it is ≤10 lines.
5. **On READY, auto-chain:** immediately invoke the `recon:recon-discovery` skill (Skill tool) in the same run — unless the user said "triage only".
6. **Triage decides; it never plans.** NEVER include implementation direction, candidate code changes, or governance decisions ("no SPEC needed") in triage output. That authority belongs to later stages.
7. **Human-facing questions MUST be concrete.** Every question in a drafted comment must be answerable without reading code: numbered repro steps from a stated start state (e.g. the project's mock-mode dev command, which page), concrete entity names from the running system ("Collection3", not "a collection"), the before and after state, and options phrased as user-observable outcomes ("the tab appears and becomes selected"), never code outcomes ("activeTab is set"). Internal identifiers (service/method/prop names) are BANNED from human-facing questions. If a question concerns observable UI behavior, invoke the `recon:recon-repro` skill to attach visual evidence BEFORE presenting the draft.

---

## Workflow

### 1. Fetch the ticket

Parse the ticket ID from the argument (accepts `ATT-1234` or a full `https://<host>/browse/ATT-1234` URL). Credentials live in `~/.config/jira/env` (`JIRA_HOST`, `JIRA_EMAIL`, `JIRA_API_TOKEN`). Note: `JIRA_HOST` may include the `https://` prefix — strip it:

```bash
mkdir -p ~/.claude/recon/<TICKET>
set -a && source ~/.config/jira/env && set +a
HOST="${JIRA_HOST#https://}"; HOST="${HOST%/}"
curl -sS -u "$JIRA_EMAIL:$JIRA_API_TOKEN" \
  "https://$HOST/rest/api/2/issue/<TICKET>?fields=summary,status,description,comment,labels,issuelinks,assignee,reporter,issuetype" \
  -o ~/.claude/recon/<TICKET>/ticket.json
```

Use API v2 (plain-text bodies). Read description AND all comments — blockers often live in comments.

### 2. Run the six checks (each with mechanical evaluation)

| # | Check | How to evaluate |
|---|---|---|
| 1 | `outcome_decidable` | Description states expected behavior or acceptance criteria you could write a pass/fail test against. ACs with "would be useful", "maybe", "TBD" → `partial`. |
| 2 | `evidence_ok` | Try each linked resource: WebFetch external links (a 403/404 is evidence of inaccessibility), note attachments. Google Drive / auth-walled links that can't be verified → flag. |
| 3 | `product_decision_open` | Unanswered questions in comments; vague ACs; any decision only a PM can make. |
| 4 | `design_dependency` | Ticket needs a design (Figma/claude.ai/other) — is it linked AND accessible? |
| 5 | `backend_dependency` | Needed endpoints/fields exist? Check the repo's generated API client when applicable. Also: assets that need hosting someone else controls. |
| 6 | `conflicts` | `git branch -a \| grep -i <ticket/surface keywords>` and `gh pr list --state open` — any open work touching the same surface. |

Additional cross-checks (cheap, always run):
- **Status drift:** ticket "In Progress" but no branch/PR exists → flag it.
- **Stale blockers:** flags/blocker comments that newer evidence contradicts → note as `stale_blocker_note`, don't count as active blockers blindly.

### 3. Emit the verdict

Write `~/.claude/recon/<TICKET>/triage.yaml`:

```yaml
recon: triage
ticket: ATT-XXXX
title: "<summary>"
task_class: defect | capability-change | chore   # defect = existing behavior broken
disposition: READY | BLOCKED | NEEDS_INFO
outcome_decidable: true | partial | false
evidence_ok: true | false
product_decision_open: true | false
design_dependency: true | false
backend_dependency: true | false
status_drift: "<note or omit>"
stale_blocker_note: "<note or omit>"
blockers: []          # [{owner: <person/role>, question: "<specific, answerable>"}]
conflicts: []         # [{ticket, pr, state, surface, note}]
evidence:             # one line per claim above
  - "<command/file:line/quote>"
```

Disposition rule: any of checks 2–5 failing with an unanswered owner-question → `BLOCKED`. Only soft ambiguity (check 1 `partial`) → `NEEDS_INFO`. All clear → `READY` (conflicts don't block; they ride along as guardrails).

### 4. Branch on disposition

- **BLOCKED / NEEDS_INFO** → draft a Jira comment: ≤15 lines, one line per blocker phrased as a specific question with a named owner, plus any split-scope recommendation. Show the draft, then AskUserQuestion: `Post to Jira now / Edit first / Don't post`. POST via the API **only** after an explicit "post" answer. Then STOP — the pipeline for this ticket ends until answers arrive.
- **READY** → invoke the `recon:recon-discovery` skill now (rule 5 above).

---

## Report

Print:

```
Wrote: ~/.claude/recon/<TICKET>/ticket.json, triage.yaml
Disposition: <READY|BLOCKED|NEEDS_INFO> (<n> blockers, <n> conflicts)
Next: <one of:
  READY    → recon:recon-discovery invoked (running now)
  BLOCKED  → comment posted; pipeline paused. When answers arrive, re-run
             /recon:recon-triage <TICKET> — the stale-blocker check re-evaluates
             answered questions automatically.
  BLOCKED  → comment NOT posted (your choice); raise the questions yourself,
             then re-run /recon:recon-triage <TICKET>.>
```

---

## Reference

- Anti-slop: never append multiple recon comments to a ticket — if a triage comment already exists from a prior run, update/replace it (Jira comment edit) rather than adding another.
- Jira wiki markup for drafted comments: `h2.` headings, `||header||` tables, `{quote}`.
- If `~/.config/jira/env` is missing, tell the user to create it with `JIRA_HOST`, `JIRA_EMAIL`, `JIRA_API_TOKEN` — do not hunt for credentials elsewhere.
