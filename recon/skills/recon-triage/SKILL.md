---
description: Stage 0 blocker triage for a Jira ticket before any planning. Use when given a Jira ticket URL/ID to assess, when a task enters TODO, or when asked whether a task is blocked, ready, or actionable.
---

# Recon Triage

Read-only blocker triage: decides READY / BLOCKED / NEEDS_INFO for a Jira ticket, with evidence, before any planning or code work happens.

## Contract

- **Input:** ticket ID or URL (`ATT-1234` / `https://<host>/browse/ATT-1234`)
- **Reads:** Jira API (GET only), local git branches + `gh pr list` (read-only), ticket links via WebFetch
- **Writes:** ONLY inside `~/.claude/recon/<TICKET>/triage/` — `ticket.json`, `triage.yaml`, auxiliary GET results as `aux-<slug>.json` (e.g. `aux-children.json`, `aux-confluence.json`); on the posting path, under `triage/jira/`: `comment.txt` (exact posted body), `bundle-manifest.txt` (delivery-bundle manifest, written by `package-artifacts.sh`), `post-result.json` (API response), `attach-result.json` (attachment uploads, written by `attach-artifacts.sh`). The delivery zip (`recon-artifacts-<TICKET>.zip`) is staged in a temp dir by `package-artifacts.sh`, never inside the workspace. Root `meta.yaml` + `index.md` belong to the step-0 script; prior-run artifacts are archived into `runs/<timestamp>/` (step 0). Anything else fails `lint-workspace.sh`.
- **External side effects:** NONE by default. At most: one Jira comment (create, or edit of a prior recon comment) PLUS replacement of recon-owned attachments (the `recon-*-<TICKET>.*` namespace) — both drafted/staged first, sent ONLY after the single explicit approval in this session.
- **May invoke:** `recon:recon-discovery` (on READY), `recon:recon-repro` (UI-related blocker questions), `recon:recon-report` (render-only, BLOCKED/NEEDS_INFO posting path)

---

## ⚠️ CRITICAL: Rules

1. **READ-ONLY.** You MUST NOT write code, create branches, or modify any repo. The only writes allowed are artifacts under `~/.claude/recon/<TICKET-ID>/`, plus delivery files staged in the temp dir on the posting path (the `package-artifacts.sh` zip and the renamed dossier copy — step 4's posting path).
2. **NEVER post to Jira without explicit approval in this session.** You draft comments and stage attachments; the user approves via AskUserQuestion before any mutating Jira call (comment create/edit, attachment delete/upload). NEVER skip this, even if the user previously approved a different comment.
3. **Every checklist answer MUST carry evidence** — a command output, a `file:line`, an HTTP status, or an exact quote from the ticket. A check without evidence is not done.
4. **The verdict MUST be the `triage.yaml` schema below**, written to `~/.claude/recon/<TICKET-ID>/triage/triage.yaml`. Prose around it is ≤10 lines.
5. **On READY, auto-chain:** immediately invoke the `recon:recon-discovery` skill (Skill tool) in the same run — unless the user said "triage only".
6. **Triage decides; it never plans.** NEVER include implementation direction, candidate code changes, or governance decisions ("no SPEC needed") in triage output. That authority belongs to later stages.
7. **Human-facing questions MUST be concrete.** Every question must be answerable without reading code. The concreteness pack — numbered repro steps from a stated start state (e.g. the project's mock-mode dev command, which page), concrete entity names from the running system ("Collection3", not "a collection"), the before and after state, and options phrased as user-observable outcomes ("the tab appears and becomes selected"), never code outcomes ("activeTab is set") — goes in the dossier question packs (`blockers[].detail` in `triage.yaml`); the comment's `ask` line stays ONE rule-7-clean sentence ending in "?". Internal identifiers (service/method/prop names) are BANNED from all human-facing text, `ask` and `detail` alike. If a question concerns observable UI behavior, invoke the `recon:recon-repro` skill to attach visual evidence BEFORE presenting the draft.
8. **Fresh workspace, every run — and step 0 runs exactly ONCE per run.** Step 0 archives all prior artifacts into `runs/<timestamp>/` BEFORE anything else — no exceptions, no "resume". NEVER re-invoke it mid-run: it would archive this run's own in-progress artifacts (the script guards this and prints `SKIPPED`; treat that as "continue, workspace is already initialized" — never set `RECON_STEP0_FORCE` mid-run). You MUST NEVER open, list, or cite anything under `runs/` — the only inputs to triage are the live Jira API, git, `gh`, and resources fetched this run. Prior recon artifacts are the output of an older run (possibly an older skill version), never evidence.
9. **Recon's own Jira comments are output, not evidence.** Every comment recon posts ends with the marker line `~recon-triage v<plugin_version>~` (version from `meta.yaml`). When reading ticket comments, any comment whose body contains `recon-triage` is pipeline output: it MUST NOT count toward `outcome_decidable`, `product_decision_open`, or any other check. Marker comments are used for exactly two things: (a) edit-vs-create — if one exists, edit the most recent instead of adding another; (b) answered-blocker detection — a human comment posted after a marker comment counts as a reply to its questions.

---

## Workflow

### 0. Fresh workspace (mandatory, before anything else)

Every run starts from an empty workspace — prior artifacts are archived mechanically, never inspected. Run the step-0 script; NEVER reimplement it inline (byte-identical execution is the point):

```bash
bash "<skill base dir>/../../scripts/fresh-workspace.sh" <TICKET>
```

`<skill base dir>` is the "Base directory for this skill" path shown when this skill loaded (the scripts live at the plugin root, `recon/scripts/`). The script archives everything (dotfiles included) into `runs/<timestamp>/`, stamps `meta.yaml` with the plugin version, and copies the static `index.md` (the workspace's own documentation); quote its output lines in your progress note. If the script is missing, STOP and report a broken plugin install — do not improvise a replacement.

After this the workspace contains ONLY `meta.yaml`, `index.md`, and (possibly) `runs/`. From here on, `runs/` does not exist for you (rule 8). Create your stage directory before your first write: `mkdir -p ~/.claude/recon/<TICKET>/triage` — a stage directory existing means that stage ran.

### 1. Fetch the ticket

Parse the ticket ID from the argument (accepts `ATT-1234` or a full `https://<host>/browse/ATT-1234` URL). Credentials live in `~/.config/jira/env` (`JIRA_HOST`, `JIRA_EMAIL`, `JIRA_API_TOKEN`). Note: `JIRA_HOST` may include the `https://` prefix — strip it:

```bash
set -a && source ~/.config/jira/env && set +a
HOST="${JIRA_HOST#https://}"; HOST="${HOST%/}"
curl -sS -u "$JIRA_EMAIL:$JIRA_API_TOKEN" \
  "https://$HOST/rest/api/2/issue/<TICKET>?fields=summary,status,description,comment,labels,issuelinks,assignee,reporter,issuetype" \
  -o ~/.claude/recon/<TICKET>/triage/ticket.json
```

Use API v2 (plain-text bodies). Read description AND all comments — blockers often live in comments. Before evaluating anything, partition the comments: any comment whose body contains `recon-triage` is recon's own output and is excluded from every check (rule 9); only human comments are evidence.

### 2. Run the six checks (each with mechanical evaluation)

| # | Check | How to evaluate |
|---|---|---|
| 1 | `outcome_decidable` | Description states expected behavior or acceptance criteria you could write a pass/fail test against. ACs with "would be useful", "maybe", "TBD" → `partial`. |
| 2 | `evidence_ok` | Try each linked resource: WebFetch external links (a 403/404 is evidence of inaccessibility), note attachments. Google Drive / auth-walled links that can't be verified → flag. |
| 3 | `product_decision_open` | Unanswered questions in **human** comments; vague ACs; any decision only a PM can make. Recon marker comments never count as open questions (rule 9) — but a human reply posted after one counts as answering its questions. |
| 4 | `design_dependency` | Ticket needs a design (Figma/claude.ai/other) — is it linked AND accessible? |
| 5 | `backend_dependency` | Needed endpoints/fields exist? Check the repo's generated API client when applicable. Also: assets that need hosting someone else controls. |
| 6 | `conflicts` | `git branch -a \| grep -i <ticket/surface keywords>` and `gh pr list --state open` — any open work touching the same surface. |

Additional cross-checks (cheap, always run):
- **Status drift:** ticket "In Progress" but no branch/PR exists → flag it.
- **Stale blockers:** flags/blocker comments that newer evidence contradicts → note as `stale_blocker_note`, don't count as active blockers blindly.

### 3. Emit the verdict

Write `~/.claude/recon/<TICKET>/triage/triage.yaml`:

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
blockers: []          # each entry:
#  - title: "Updated design"            # ≤5 words, names the blocker
#    owner: osman                       # handle; resolve to accountId at draft time (step 4)
#    ask: "deliver the updated design, or should I build to the attached PNG?"
#                                       # ONE sentence, ends in "?", rule-7 clean
#    detail:                            # rule-7 question pack — rendered ONLY in the dossier
#      state: "<where this blocker stands, dated>"
#      options: ["<user-observable outcome a>", "<user-observable outcome b>"]
#      evidence: ["<quote / file:line / HTTP status>"]
#      repro_ref: repro/exhibits/…      # when recon-repro ran
conflicts: []         # [{ticket, pr, state, surface, note}]
evidence:             # one line per claim above
  - "<command/file:line/quote>"
```

Disposition rule: any of checks 2–5 failing with an unanswered owner-question → `BLOCKED`. Only soft ambiguity (check 1 `partial`) → `NEEDS_INFO` — and NEEDS_INFO MUST materialize each ambiguity as a blocker entry (owner = whoever can decide it; the `ask` IS the clarifying question). All clear → `READY` (conflicts don't block; they ride along as guardrails). BLOCKED and NEEDS_INFO both require `blockers` to be non-empty — the posting path demands n ≥ 1; if no blocker entry can be written, the ticket is not NEEDS_INFO.

### 4. Branch on disposition

- **READY** → invoke the `recon:recon-discovery` skill now (rule 5 above).
- **BLOCKED / NEEDS_INFO** → run the posting path below in order, then STOP — the pipeline for this ticket ends until answers arrive.

#### Posting path (BLOCKED / NEEDS_INFO)

1. **Structure the blockers.** Every `triage.yaml` blocker follows the schema above: `title` (≤5 words), `owner`, a one-sentence `ask` ending in "?", and a `detail` question pack — list entries at exactly the schema's two-space indentation (`  - title:`; the shape rail counts that pattern). Rule 7 applies to `ask` AND `detail`: internal identifiers are BANNED from both.
2. **Repro first.** Any blocker concerning observable UI behavior → invoke the `recon:recon-repro` skill and capture its evidence BEFORE drafting (rule 7).
3. **Render the dossier.** Invoke the `recon:recon-report` skill in render-only mode → writes `report/dossier.html`. NO artifact publishing on this path — the Jira attachment is the delivery.
4. **Draft the comment** — EXACT shape, n+4 non-empty lines, generated from `triage.yaml` ONLY:

   ```
   h2. Recon triage: <DISPOSITION> — <n> blocker(s) (<d MMM>)

   *1. <title>* — [~accountid:…]: <ask>

   Full detail, options, and evidence: [^recon-dossier-<TICKET>.html] · [^recon-artifacts-<TICKET>.zip]
   Reply here — answers on this ticket un-block the pipeline.
   ~recon-triage v<plugin_version from meta.yaml>~
   ```

   One `*i. <title>* — [~accountid:…]: <ask>` line per blocker, numbered 1..n. Resolve each `owner` handle to its accountId at draft time — `comment.txt` is the exact posted body: `GET "https://$HOST/rest/api/2/user/search?query=<name>"` (same creds/HOST as step 1), save each response as `triage/aux-user-<slug>.json`, and take `accountId` from it; NEVER guess an accountId or fall back to a display name. NO history, NO stale-blocker narration, NO technical values beyond what an ask needs — that lives in the dossier's question packs. Split-scope proposals appear ONLY inside an ask line. Save to `triage/jira/comment.txt`, then run:

   ```bash
   bash "<skill base dir>/../../scripts/verify-comment-shape.sh" <TICKET>
   ```

   Fix and re-run until it prints `shape: clean`.
5. **Package the bundle** — AFTER the dossier exists, so the zip contains it:

   ```bash
   bash "<skill base dir>/../../scripts/package-artifacts.sh" <TICKET>
   ```

   Writes `triage/jira/bundle-manifest.txt` and stages `recon-artifacts-<TICKET>.zip` in a temp dir (never inside the workspace). Quote its `MANIFEST:` and `ZIP:` lines in your progress note.
6. **Gate (single approval).** AskUserQuestion shows the comment draft AND the attachment manifest: the two filenames (`recon-dossier-<TICKET>.html`, `recon-artifacts-<TICKET>.zip`), their sizes, and the bundle file count from the `MANIFEST:` line. Options: `Post to Jira now (comment + 2 attachments)` / `Edit first` / `Don't post`. One "post" answer authorizes the comment AND both attachments. NEVER post or attach without it (rule 2). On `Edit first`: after ANY change to `comment.txt`, re-run `verify-comment-shape.sh` until `shape: clean` AND re-run step 5 (package) — the zip bundles `comment.txt`, so the gate-displayed bundle must match the posted bytes — then re-show this gate: the posted bytes are always shape-verified and freshly approved. Any edit that changes `triage.yaml` blockers also requires re-running posting-path steps 3–5 (dossier render, package) so the attached dossier and zip match the comment being approved.
7. **On "post": attachments FIRST, then the comment.** Duplicate filenames bind `[^…]` links to the OLDER attachment, so replacement MUST precede the comment. The uploaded filename is the file's basename, so stage a renamed dossier copy in the temp dir (never inside the workspace):

   ```bash
   cp ~/.claude/recon/<TICKET>/report/dossier.html "${TMPDIR:-/tmp}/recon-dossier-<TICKET>.html"
   bash "<skill base dir>/../../scripts/attach-artifacts.sh" <TICKET> \
     "${TMPDIR:-/tmp}/recon-dossier-<TICKET>.html" "<ZIP path from step 5's ZIP: line>"
   ```

   The script deletes prior `recon-*-<TICKET>.*` attachments, uploads the new files, and writes `triage/jira/attach-result.json`; it is safe to re-run after a failure. THEN create the comment with the exact bytes of `comment.txt` — or, if the fetched comments already contain a marker comment, EDIT the most recent one instead (rule 9); never add a second marker comment. Save the API response to `triage/jira/post-result.json`. Then STOP.

---

## Report

Print:

First run the workspace lint (same scripts dir as step 0) and include its verdict line:

```bash
bash "<skill base dir>/../../scripts/lint-workspace.sh" <TICKET>
```

```
Step 0: <the script's `archived:` output line, verbatim>
Wrote: ~/.claude/recon/<TICKET>/triage/{ticket.json, triage.yaml} (+ jira/{comment.txt,
       bundle-manifest.txt} on the posting path; + jira/{attach-result.json,
       post-result.json} only after a "post" answer)
Lint: <lint-workspace.sh verdict line, verbatim — fix any violation before reporting>
Shape: <verify-comment-shape.sh verdict line, verbatim — posting path only; omit on READY>
Disposition: <READY|BLOCKED|NEEDS_INFO> (<n> blockers, <n> conflicts)
Next: <one of:
  READY    → recon:recon-discovery invoked (running now)
  BLOCKED / NEEDS_INFO → comment + attachments posted; pipeline paused. When answers
             arrive, re-run /recon:recon-triage <TICKET> — the stale-blocker check
             re-evaluates answered questions automatically.
  BLOCKED / NEEDS_INFO → comment NOT posted (your choice); raise the questions
             yourself, then re-run /recon:recon-triage <TICKET>.>
```

---

## Reference

- Anti-slop: never append multiple recon comments to a ticket. Detection is mechanical: a prior recon comment is any comment whose body contains `recon-triage` (rule 9). If one or more exist, edit the most recent via the Jira comment-edit API; never create a second.
- Attachments named `recon-*-<TICKET>.*` are recon-owned: `attach-artifacts.sh` replaces them (delete-then-upload), never accumulates — and always BEFORE the comment is created/edited, so `[^…]` links resolve to the new files (Jira binds duplicate filenames to the OLDER attachment).
- Determinism: given the same ticket state, a run must produce the same verdict regardless of what earlier runs left behind. That is why step 0 archives unconditionally, `runs/` is unreadable, and marker comments are excluded from evidence — the only inputs are the live ticket, git, and `gh`.
- Jira wiki markup for drafted comments: `h2.` headings, `||header||` tables, `{quote}`.
- If `~/.config/jira/env` is missing, tell the user to create it with `JIRA_HOST`, `JIRA_EMAIL`, `JIRA_API_TOKEN` — do not hunt for credentials elsewhere.
- Whole-chain spec (stages, invariants, artifact registry, trigger table): `../../docs/pipeline.md` relative to this skill's base directory. On conflict, this SKILL.md wins.
