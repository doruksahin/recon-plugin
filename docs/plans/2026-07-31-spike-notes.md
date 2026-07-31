# Spike notes — v0.7.0 comment + delivery redesign

## Task 0 — target ticket

- Doruk's decision (2026-07-31): **no sandbox ticket**. All spikes run against the real
  blocked ticket **ATT-5107** (https://appier.atlassian.net/browse/ATT-5107).
- Low-noise constraints derived from that decision:
  - The `[^filename]` rendering check EDITS the existing recon marker comment
    (append link line → verify via `expand=renderedBody` → restore original body).
    Never a second comment (plugin rule 9: one marker comment per ticket).
  - Deletes touch ONLY attachments matching `recon-*-ATT-5107.*`. Colleagues' real
    attachments must be listed before/after and proven untouched.
  - All spike attachments are removed at the end of Task 1.

## Task 1 — Spike A: attachment semantics

(pending)

## Task 2 — Spike B: PDF render decision

(pending)
