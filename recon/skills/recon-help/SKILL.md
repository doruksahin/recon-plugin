---
name: recon-help
description: Explain Recon and verify its local setup from live doctor output. Use when asked how Recon works, which command to run, whether setup is healthy, or when onboarding a colleague.
---

# Recon Help

One screen that orients a new user and verifies their setup. Everything it
states is derived live by the doctor rail — this skill carries almost no facts
of its own, so it cannot drift from the pipeline it describes.

Read `../../docs/hosts.md` before translating any host-specific interaction.
Run `doctor.sh`; it owns `reconctl` host/surface detection, invocation
rendering, and triage preflight, and prints the active workspace root.

## Contract

- **Input:** none
- **Reads:** the installed plugin's own files (version, sibling SKILL.md descriptions), `~/.config/jira/env` (GET /myself only), the current repo's governance probe
- **Writes:** NOTHING — no workspace, no Jira, no config
- **May invoke:** nothing

---

## ⚠️ CRITICAL: Rules

1. **Facts come from the rail, never from memory.** Run `doctor.sh` and present
   its output — do NOT restate skill lists, versions, or setup state from your
   own knowledge, and do NOT "fix" its output. If the script and your
   expectations disagree, the script wins.
2. **Read-only.** A failing check is REPORTED with the script's remediation
   text; this skill never edits config files, credentials, or the repo. The one
   exception a user may ask for: choosing a handoff style — that runs
   `set-governance.sh`, quote the command, run it only if the user says so.

---

## Workflow

1. Run the doctor from the current directory (the handoff-style check is
   repo-dependent, so where you run it matters — say so if the user seems to be
   asking about a different repo):

```bash
bash "<skill base dir>/../../scripts/doctor.sh"
```

2. Present its output essentially verbatim (fenced), then add AT MOST three
   sentences of orientation around it:
   - What recon is: a read-only Jira-ticket recon pipeline that runs BEFORE any
     planning — it decides blocked-or-ready with evidence, maps the code
     surface, and ends at a human approval gate; it never writes code.
   - The stage legend, quoted from the state machine in
     [pipeline.md](../../docs/pipeline.md): numbered stages run in sequence
     (0 workspace → 1 triage → 2 discovery); lettered stages fire on triggers
     (R repro · RT routing · D dossier).
   - Where to go deeper: `README.md` (overview + diagram), `recon/docs/pipeline.md`
     (machine spec), and each skill's own SKILL.md.

3. If a check printed ✗ or !, surface it as the FIRST thing after the output —
   a new user's next step is fixing that line, not reading more docs.

---

## Report

The doctor output block, the ≤3 orientation sentences, and (only when present)
the failing-check callout. Nothing else.
