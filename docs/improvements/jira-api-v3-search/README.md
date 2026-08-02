# Migrate search calls to Jira API v3

> Migrate search references to /rest/api/3/search/jql; v2 search is removed

- **Status:** proposed
- **Priority:** P3
- **Theme:** operational robustness
- **Origin:** ATT-5107 triage run, 1 Aug 2026 — a diagnostic JQL search against
  `/rest/api/2/search` hit Atlassian's removal notice.

## Problem

Atlassian removed the v2/v3 legacy search endpoint (deprecation CHANGE-2046). The
pipeline standardizes on API v2 for plain-text bodies — which is still correct for
issue GET, comment PUT/POST, attachments, and user search — but any current or
future check that *searches* (JQL) breaks. Today nothing in the shipped scripts
searches; the risk is a skill or future improvement (e.g. a conflicts check for
"other open tickets on the same surface") reaching for the obvious-but-dead
endpoint, since SKILL.md's "Use API v2" reads as a blanket rule.

## Before (1 Aug run, verbatim)

```
$ curl … "/rest/api/2/search?jql=key%3DATT-5107&fields=summary,status"
{"errorMessages":["The requested API has been removed. Please migrate to the
/rest/api/3/search/jql API. A full migration guideline is available at
https://developer.atlassian.com/changelog/#CHANGE-2046"]}
```

## After (proposed)

- Docs: `recon-triage` SKILL.md's "Use API v2 (plain-text bodies)" gains the one
  needed qualifier: **except search — JQL goes to `POST/GET /rest/api/3/search/jql`**
  (v3 returns ADF bodies, so search results are used for keys/status only; full
  bodies still come from the v2 issue GET).
- If/when a JQL-based check lands, it uses the v3 shape from day one:

```
$ curl … "/rest/api/3/search/jql?jql=project%3DATT%20AND%20summary~%22welcome%20modal%22&fields=summary,status"
{"issues":[{"key":"ATT-5107","fields":{"status":{"name":"In Progress"},…}}]}
```

- Pairs naturally with the shared *jira-get.sh* helper proposed in
  [credential-preflight](../credential-preflight/README.md): the helper owns the
  endpoint map (`issue`→v2, `search`→v3, `user/search`→v2), so individual skills
  never pick versions again.

## Implementation sketch

- One-line doc change in `recon-triage/SKILL.md` step 1.
- Endpoint map in the shared Jira helper when it exists.
- No behavior change today — this is a landmine-removal doc fix.

## Open questions

- None.
