---
name: recon-state
description: Render a ticket's living state canvas from mechanical workspace state and, when the local host supports stable publishing, republish it to one per-ticket URL; otherwise return the rendered file. Use when asked where a ticket stands, for a recon status/state page, or at a Recon STOP or gate.
---

# Recon State

One glanceable node canvas per ticket: every pipeline stage as a card, the current stop glowing with a next-action chip, the ticket's event history as a timeline. The state is DERIVED from artifact presence by a rail — the workspace *is* the state. A host with `publish_stable_url` may keep one private artifact URL current for the ticket's whole life; other hosts return the local canvas.

## Host setup

Before the first path or tool action, read `../../docs/hosts.md`. Resolve the
absolute workspace root, host, and surface with `reconctl.sh`; inspect
`capabilities`, then run `reconctl.sh preflight base`. Retain the printed values
for the run. A failed preflight is a hard STOP. Use `publish_stable_url` only
when declared available; otherwise keep the canvas render-only and never write
`state/artifact-url`.

## Contract

- **Input:** ticket ID (precondition: a run exists — root `meta.yaml`)
- **Reads:** current-run artifacts + `history.ndjson` (timeline VIEW only — invariant 16), the shipped `template.html`
- **Writes:** ONLY inside `$RECON_ROOT/<TICKET>/state/` — `state.yaml`, `canvas.html`, `artifact-url`
- **External side effects:** when `publish_stable_url` is available, publishes/republishes `state/canvas.html` as a **private** artifact. The first publish is gated in-session; republishes to the saved URL are not. Without that capability the skill is render-only. Never posts to Jira or touches the repo.

---

## ⚠️ CRITICAL: Rules

1. **The rails decide everything.** `derive-state.sh` derives the state (a contradiction exits 1 — report it verbatim as a workspace/plugin bug and STOP; never hand-derive around it). `render-state-canvas.sh` fills the template. You author NOTHING in the canvas — no extra facts, no reworded status text.
2. **One stable URL only on capable hosts.** If `publish_stable_url` is unavailable, render and stop: do not create, update, or use `state/artifact-url`. When available, `state/artifact-url` holds the stable identity. If present: republish to it, no questions. If absent: ask ONCE — `Publish a private state canvas for <TICKET>? (creates its stable URL)` with options `Publish` / `Not now`; on Publish save the returned URL as exactly one line, and on Not now stop after rendering.
3. **Living view, frozen dossier.** The canvas ALWAYS shows the present. It may be republished freely only when `publish_stable_url` is available; it never replaces the dossier, and dossiers are never retro-updated. Do not merge the two.
4. **NEVER read `runs/`** (invariant 3). The timeline comes from `history.ndjson` only — and only as rendered output, never as an input to any judgment (invariant 16).
5. **Keep artifact identity stable:** title `<TICKET> — Recon State`, favicon `🧭` — same on every republish.

---

## Workflow

1. **Derive** — `bash "<skill base dir>/../../scripts/derive-state.sh" <TICKET>`. Exit 2 → no run: quote its host-rendered Triage instruction and stop. Exit 1 → quote the contradiction line and stop.
2. **Render** — `bash "<skill base dir>/../../scripts/render-state-canvas.sh" <TICKET>` → `state/canvas.html`.
3. **Lint** — `bash "<skill base dir>/../../scripts/lint-workspace.sh" <TICKET>`; fix any violation.
4. **Publish when available** per rule 2. Otherwise report render-only. Description: one sentence naming the ticket and its stop.
5. **Log** — only after a successful publish: `bash "<skill base dir>/../../scripts/log-event.sh" <TICKET> canvas_published` (invariant 16).

## Report

```
State: <derive-state.sh first output line, verbatim>
Rendered: $RECON_ROOT/<TICKET>/state/canvas.html
Lint: <lint-workspace.sh verdict line, verbatim>
Published: <URL> (stable for this ticket) | render-only (capability unavailable) | first publish declined
Next: <the `next:` line from state/state.yaml, verbatim>
```

---

## Reference

- Auto-refresh: other recon skills may invoke this skill at a STOP or gate when `state/artifact-url` exists. A host without `publish_stable_url` refreshes only the local render and leaves the saved URL untouched.
- Whole-chain spec (stages, invariants, artifact registry, trigger table): `../../docs/pipeline.md` relative to this skill's base directory. On conflict, this SKILL.md wins.
