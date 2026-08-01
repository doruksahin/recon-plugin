# 0001 — Jira REST API over MCP

- Status: accepted
- Date: 2026-07-31
- Deciders: Doruk

## Context

The pipeline's design formula demands that execution move onto rails with mechanical evidence: curl-based rails save byte-exact request/response artifacts (`ticket.json`, `post-result.json`, `attach-result.json`) that the lint registry (`lint-workspace.sh`) audits. The question arose whether to switch Jira access from the REST API (curl rails, creds in `~/.config/jira/env`) to a Jira MCP server (e.g. Atlassian's remote OAuth-based MCP).

## Decision

Stay on Jira REST API v2 via curl inside plugin scripts. MCP is not adopted for any pipeline surface.

Grounds:

1. **Determinism / auditability.** MCP tool results flow through model context; artifacts would be model-transcribed — the exact slop vector the rails eliminate. curl writes the byte-exact response to disk with no model in the path.
2. **Capability.** Comment EDIT (the marker edit-not-append rule, triage rule 9) and attachment upload/delete (replace-not-accumulate, invariant 14) are load-bearing; Atlassian's MCP does not expose them.
3. **Portability.** OAuth MCP sessions may be absent in headless runs; per-coworker OAuth setup adds a dependency without removing the env-file need (scripts still require it).

## Consequences

- Every coworker installing the plugin creates a Jira API token once (`~/.config/jira/env`: `JIRA_HOST`, `JIRA_EMAIL`, `JIRA_API_TOKEN`).
- All Jira mutations stay on the auditable curl rails — `attach-artifacts.sh` plus the SKILL-specified comment create/edit call — each leaving its byte-exact response artifact (`attach-result.json`, `post-result.json`).
- API v2 wiki-markup bodies remain the comment format.

## Revisit triggers

- Atlassian MCP ships comment-edit + attachment CRUD.
- Jira API token creation becomes a real onboarding blocker.
- Atlassian deprecates API-token basic auth.

## Considered and rejected

| Option | Reason rejected |
|---|---|
| Jira MCP (Atlassian remote, OAuth) | this record |
| API v3 / ADF expand-sections for in-comment progressive disclosure | attachment-based disclosure won — v2 wiki markup + `[^…]` links proved sufficient (verified 2026-07-31 on ATT-5107) |
| GitHub Pages artifact hosting | public exposure / wrong audience |
| Google Drive artifact hosting | new credential system, weak determinism |
| Confluence page hub | best rendering, biggest build — revisit if attachment UX proves insufficient |
