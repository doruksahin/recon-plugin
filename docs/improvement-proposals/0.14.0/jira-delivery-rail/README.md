# Bind approval to one idempotent Jira delivery

> Bind Jira approval to exact bytes, then deliver attachments and one comment idempotently

- **Status:** proposed — requires a dedicated safety release with a fake-Jira
  retry/concurrency harness
- **Priority:** P1
- **Theme:** operational robustness
- **Origin:** ATT-5107 on 1 Aug 2026 motivated mechanical comment rendering and
  attachment replacement, but the 2 Aug audit found the final marker lookup and
  comment create/edit still executed from prompt instructions.
- **Depends on:** render-comment

## Problem

The posting path has strong components but no single transaction contract. The
model displays a draft and manifest, receives approval, then separately stages a
renamed dossier, replaces attachments, finds the newest marker comment, chooses
POST or edit, sends the body, saves responses, and logs the event.

A retry can use bytes different from those approved, create a second marker
comment, or post before replacement attachments. These are high-risk operations
where the skill-design rule is low freedom and exact verification.

## Before (today)

```text
gate shown: comment.txt sha256=aaa... + bundle.zip sha256=bbb...
user: Post
agent re-renders after gate                  # bytes may now differ
agent uploads attachments
agent chooses create instead of edit         # duplicate marker comment
agent posts comment
```

No rail binds the approval to the bytes or checks the whole ordering.

## After (proposed)

```text
$ recon jira stage-delivery ATT-5107
plan: d7e3... · comment aaa... · dossier 91c... · bundle bbb...
action: edit comment 2186001 · attachments: replace 2
```

The gate displays that plan digest. After approval:

```text
$ recon jira apply-delivery ATT-5107 --approved-plan d7e3...
verify plan: PASS — staged bytes unchanged
remote preconditions: PASS — marker and attachment state unchanged
attachments: replaced 2 (before comment)
comment: edited 2186001 (marker count after apply: 1)
audit: responses saved · events logged
delivery: COMPLETE
```

Re-running the same approved plan returns `COMPLETE` without a second comment or
duplicate attachments. A changed byte invalidates the digest and requires a new
gate.

## Implementation sketch

- Add a staged delivery-plan artifact containing hashes, sizes, intended comment
  action, live marker IDs/body hashes, and recon-owned attachment IDs/names/sizes.
- Add *jira-delivery.sh* with `stage` and `apply` operations; `apply` requires the
  exact approved digest, re-fetches remote preconditions, and owns
  attachment-first ordering.
- Move marker selection, comment create/edit, response persistence, and delivery
  event logging into the rail.
- Fail staging when multiple marker comments already exist; applying cannot claim
  one-marker success while silently leaving duplicates behind.
- Keep the delivery plan and receipt outside the attachment bundle so staging
  cannot create a self-referential zip digest.
- Keep the human approval in `recon-triage`; replace all post-gate execution prose
  with one apply command.
- Add fake-Jira fixtures for create, edit, retry, changed bytes, partial upload,
  and multiple stale marker comments.

## Open questions

- Jira cannot provide a real multi-call transaction. The rail should use an
  idempotent state machine and safe retry points rather than claim atomicity. A
  lost POST response must be reconciled by re-fetching marker comments and
  comparing exact body bytes before another create is attempted.
