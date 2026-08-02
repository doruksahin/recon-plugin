# Credential preflight before the ticket fetch

> GET /myself before the ticket fetch; expired tokens fail loudly with a fix

- **Status:** proposed
- **Priority:** P1
- **Theme:** operational robustness
- **Origin:** ATT-5107 triage run, 1 Aug 2026 — an expired token produced a
  misleading dead-end instead of an auth error.

## Problem

`recon-triage` step 1 covers only the missing-env-file case. When the token is
present but rejected (Atlassian API tokens now have mandatory expiry, so this WILL
recur), Jira Cloud does not 401 the issue GET — it treats the request as anonymous
and returns a *permissions*-shaped error. The run dies pointing at the wrong cause.

## Before (1 Aug run, verbatim)

```
$ curl … /rest/api/2/issue/ATT-5107?fields=…
{"errorMessages":["Issue does not exist or you do not have permission to see it."]}
```

That reads as "wrong ticket ID" or "no project access". Only a manual follow-up
revealed the truth:

```
$ curl … /rest/api/2/myself
Client must be authenticated to access this resource.
HTTP:401
```

Diagnosis cost several extra steps (checking the env file for CRLF/quoting, token
length, etc.) before concluding: token expired.

## After (proposed)

Step 1 starts with a preflight that turns the failure into a one-step fix:

```
$ bash recon/scripts/jira-preflight.sh
FAIL — token rejected (GET /rest/api/2/myself → 401)
       JIRA_EMAIL=doruk.sahin@appier.com, token present (192 chars, ATATT3…)
       Likely expired — regenerate at:
       https://id.atlassian.com/manage-profile/security/api-tokens
       then update JIRA_API_TOKEN in ~/.config/jira/env and re-run.
```

On success it prints the authenticated `displayName`/`accountId` (which
[owner-resolution-order](../owner-resolution-order/README.md) can reuse) and the
skill proceeds. The SKILL.md gains one line ("run the preflight; stop on FAIL") and
loses the missing-env-file prose, which moves into the script's own error.

## Implementation sketch

- New *recon/scripts/jira-preflight.sh*: source env → strip host prefix →
  `GET /myself` → 200: print identity; 401/403: print the remediation block; missing
  env file: print the create-it instructions currently in SKILL.md's Reference.
- Best shipped as part of a shared *jira-get.sh* helper (see
  [golden-fixtures](../golden-fixtures/README.md) — same seam serves fixtures).
- Call it in `recon-triage` step 1 and `recon-repro`/`recon-report` wherever they
  touch Jira.

## Open questions

- Should the preflight also warn on *approaching* expiry? Atlassian doesn't expose
  token expiry via API, so probably not — keep it reactive and simple.
