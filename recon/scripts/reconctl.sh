#!/bin/bash
# reconctl.sh — deterministic local runtime contract for Claude Code + Codex.
# Read-only: it resolves paths, host identity, invocation labels, capabilities,
# and preconditions. Workspace mutation remains in the stage-specific rails.
set -euo pipefail

command_name="${1:-help}"

normalize_label() {
  printf '%s' "${1:-}" \
    | tr '[:upper:] _' '[:lower:]--' \
    | sed 's/[^a-z0-9-]/-/g; s/--*/-/g; s/^-//; s/-$//'
}

normalize_host() {
  local raw
  raw="$(normalize_label "${1:-}")"
  case "$raw" in
    claude|claude-code|claudecode) printf 'claude-code\n' ;;
    codex|codex-cli|codex-app|codex-desktop) printf 'codex\n' ;;
    "") printf 'unknown\n' ;;
    *) printf '%s\n' "$raw" ;;
  esac
}

# Marker families. CLAUDECODE is inherited by every child process, and Codex
# exports its own markers into each command it runs, so a nested session (Codex
# launched from a Claude Code shell, or the reverse) carries BOTH families and
# presence alone cannot say which host is actually driving. Guessing there once
# printed a Claude slash command on Codex and, worse, granted Claude's stable-URL
# publishing to a host that cannot republish. Ambiguity therefore resolves to
# `unknown` — no optimistic capabilities — and RECON_HOST is the way to decide.
claude_markers() {
  [ -n "${CLAUDECODE:-}" ] || [ -n "${CLAUDE_CODE_ENTRYPOINT:-}" ]
}

codex_markers() {
  [ -n "${CODEX_THREAD_ID:-}" ] || [ -n "${CODEX_SANDBOX:-}" ] || \
  [ -n "${CODEX_CI:-}" ] || [ -n "${CODEX_PERMISSION_PROFILE:-}" ] || \
  [ -n "${CODEX_INTERNAL_ORIGINATOR_OVERRIDE:-}" ]
}

host_ambiguous() {
  [ -z "${RECON_HOST:-}" ] && claude_markers && codex_markers
}

detect_host() {
  if [ -n "${RECON_HOST:-}" ]; then
    normalize_host "$RECON_HOST"
  elif host_ambiguous; then
    printf 'unknown\n'
  elif claude_markers; then
    printf 'claude-code\n'
  elif codex_markers; then
    printf 'codex\n'
  else
    printf 'unknown\n'
  fi
}

# Codex states its own network policy; do not spend a probe to rediscover it.
network_disabled() {
  [ "${CODEX_SANDBOX_NETWORK_DISABLED:-0}" = "1" ]
}

detect_surface() {
  local host="${1:-}" origin
  if [ -n "${RECON_SURFACE:-}" ]; then
    normalize_label "$RECON_SURFACE"
    printf '\n'
    return
  fi
  [ -n "$host" ] || host="$(detect_host)"
  case "$host" in
    claude-code) printf 'claude-code\n' ;;
    codex)
      origin="$(normalize_label "${CODEX_INTERNAL_ORIGINATOR_OVERRIDE:-}")"
      case "$origin" in
        *desktop*|*app*) printf 'codex-app\n' ;;
        *cli*) printf 'codex-cli\n' ;;
        *) printf 'codex-local\n' ;;
      esac
      ;;
    *) printf 'unknown\n' ;;
  esac
}

recon_root() {
  local root="${RECON_ROOT:-$HOME/.claude/recon}"
  case "$root" in
    /*) printf '%s\n' "${root%/}" ;;
    *) echo "RECON_ROOT must be an absolute path: $root" >&2; exit 2 ;;
  esac
}

validate_ticket() {
  local ticket="${1:-}"
  case "$ticket" in
    *[!A-Za-z0-9-]*|"") echo "invalid ticket id: $ticket" >&2; exit 2 ;;
  esac
}

action_skill() {
  case "${1:-}" in
    recon.triage|recon-triage) printf 'recon-triage\n' ;;
    recon.discovery|recon-discovery) printf 'recon-discovery\n' ;;
    recon.repro|recon-repro) printf 'recon-repro\n' ;;
    recon.report|recon-report) printf 'recon-report\n' ;;
    recon.state|recon-state) printf 'recon-state\n' ;;
    recon.help|recon-help) printf 'recon-help\n' ;;
    recon.publish|recon-publish) printf 'recon-publish\n' ;;
    recon.decree|recon-decree) printf 'recon-decree\n' ;;
    *) echo "unknown Recon action: ${1:-}" >&2; exit 2 ;;
  esac
}

action_title() {
  case "$(action_skill "$1")" in
    recon-triage) printf 'Recon Triage' ;;
    recon-discovery) printf 'Recon Discovery' ;;
    recon-repro) printf 'Recon Repro' ;;
    recon-report) printf 'Recon Report' ;;
    recon-state) printf 'Recon State' ;;
    recon-help) printf 'Recon Help' ;;
    recon-publish) printf 'Recon Publish' ;;
    recon-decree) printf 'Recon Decree' ;;
  esac
}

invocation() {
  local action="${1:-}" ticket="${2:-}" host skill title
  skill="$(action_skill "$action")"
  [ -z "$ticket" ] || validate_ticket "$ticket"
  host="$(detect_host)"
  case "$host" in
    claude-code) printf '/recon:%s' "$skill" ;;
    # Codex mentions skills by bare name, never plugin-namespaced (see the
    # generated agents/openai.yaml default prompts, and OpenAI's own plugins:
    # $visualize, $excel-live-control).
    codex) printf '$%s' "$skill" ;;
    *)
      title="$(action_title "$action")"
      printf 'Run %s' "$title"
      [ -z "$ticket" ] || printf ' for'
      ;;
  esac
  [ -z "$ticket" ] || printf ' %s' "$ticket"
  printf '\n'
}

emit_capability() {
  printf '%s%s: %s\n' "${1:-}" "$2" "$3"
}

network_capability() {
  local prefix="${1:-}"
  if network_disabled; then
    emit_capability "$prefix" network "unavailable — CODEX_SANDBOX_NETWORK_DISABLED=1"
  else
    emit_capability "$prefix" network "local environment; verify with preflight"
  fi
}

capability_values() {
  local host="$1" prefix="${2:-}"
  case "$host" in
    claude-code)
      emit_capability "$prefix" ask_user "AskUserQuestion"
      emit_capability "$prefix" invoke_skill "Skill tool or /recon:<skill>"
      emit_capability "$prefix" browser "preview_start + read_page + computer"
      emit_capability "$prefix" render_local "available"
      emit_capability "$prefix" display_file "SendUserFile"
      emit_capability "$prefix" publish_once "available — Artifact tool"
      emit_capability "$prefix" publish_stable_url "available — Artifact tool with the saved URL"
      emit_capability "$prefix" local_shell "available"
      network_capability "$prefix"
      ;;
    codex)
      emit_capability "$prefix" ask_user "request_user_input when available; otherwise ask and stop"
      emit_capability "$prefix" invoke_skill 'native skill invocation or $<skill>'
      emit_capability "$prefix" browser "in-app browser/computer-use when available"
      emit_capability "$prefix" render_local "available"
      emit_capability "$prefix" display_file "Markdown with an absolute local path"
      emit_capability "$prefix" publish_once "unavailable; render-only"
      emit_capability "$prefix" publish_stable_url "unavailable; never write state/artifact-url"
      emit_capability "$prefix" local_shell "available"
      network_capability "$prefix"
      ;;
    *)
      emit_capability "$prefix" ask_user "ask in conversation and stop"
      emit_capability "$prefix" invoke_skill "use a host-native skill picker"
      emit_capability "$prefix" browser "unavailable until explicitly verified"
      emit_capability "$prefix" network "unavailable until explicitly verified"
      emit_capability "$prefix" render_local "unavailable until explicitly verified"
      emit_capability "$prefix" display_file "unavailable until explicitly verified"
      emit_capability "$prefix" publish_once "unavailable"
      emit_capability "$prefix" publish_stable_url "unavailable; never write state/artifact-url"
      emit_capability "$prefix" local_shell "unavailable until explicitly verified"
      ;;
  esac
}

capabilities() {
  local host="${1:-}"
  [ -n "$host" ] || host="$(detect_host)"
  host="$(normalize_host "$host")"
  printf 'host: %s\n' "$host"
  printf 'surface: %s\n' "$(detect_surface)"
  capability_values "$host"
}

emit_check() {
  printf 'check.%s: %s' "$1" "$2"
  [ -z "${3:-}" ] || printf ' — %s' "$3"
  printf '\n'
}

existing_parent() {
  local candidate="$1" parent
  while [ ! -e "$candidate" ]; do
    parent="${candidate%/*}"
    [ -n "$parent" ] || parent="/"
    [ "$parent" != "$candidate" ] || break
    candidate="$parent"
  done
  printf '%s\n' "$candidate"
}

validate_preflight_profile() {
  case "${1:-}" in
    base|triage|repro) ;;
    *) echo "unknown preflight profile: ${1:-} (expected base|triage|repro)" >&2; exit 2 ;;
  esac
}

preflight_snapshot() {
  local profile="$1" root="$2" host="$3" surface="$4" include_runtime="$5"
  local parent failures=0 cmd env_file code tmp pinned installed

  printf 'profile: %s\n' "$profile"
  if [ "$include_runtime" = "1" ]; then
    printf 'host: %s\n' "$host"
    printf 'surface: %s\n' "$surface"
    printf 'root: %s\n' "$root"
  fi

  # Not a failure: the pipeline still runs, but presentation and publishing
  # degrade to the `unknown` contract until RECON_HOST resolves the ambiguity.
  if host_ambiguous; then
    emit_check host WARN "Claude Code and Codex markers both present — set RECON_HOST to decide"
  fi

  for cmd in bash python3 git; do
    if command -v "$cmd" >/dev/null 2>&1; then
      emit_check "command.$cmd" PASS "$(command -v "$cmd")"
    else
      emit_check "command.$cmd" FAIL "required command missing"
      failures=$((failures + 1))
    fi
  done

  parent="$(existing_parent "$root")"
  if [ -d "$parent" ] && [ -w "$parent" ]; then
    emit_check workspace PASS "writable via $parent"
  else
    emit_check workspace FAIL "no writable existing directory at or above $root"
    failures=$((failures + 1))
  fi

  # The recorded repro runtime: proofshot drives the separate agent-browser
  # CLI, and the verifier vendors proofshot's session-log schema, so the
  # version is PINNED here (the single owner of that fact). Absence or a
  # mismatch fails closed — an unrecorded repro is never a fallback.
  if [ "$profile" = "repro" ]; then
    for cmd in proofshot agent-browser; do
      if command -v "$cmd" >/dev/null 2>&1; then
        emit_check "command.$cmd" PASS "$(command -v "$cmd")"
      else
        emit_check "command.$cmd" FAIL "npm install -g proofshot@${RECON_PROOFSHOT_VERSION:-1.6.0} agent-browser"
        failures=$((failures + 1))
      fi
    done
    if command -v proofshot >/dev/null 2>&1; then
      pinned="${RECON_PROOFSHOT_VERSION:-1.6.0}"
      installed="$(proofshot --version 2>/dev/null | tr -d '[:space:]')" || installed=""
      if [ "$installed" = "$pinned" ]; then
        emit_check proofshot_version PASS "$installed (pinned)"
      else
        emit_check proofshot_version FAIL "installed '$installed', pinned '$pinned' — npm install -g proofshot@$pinned"
        failures=$((failures + 1))
      fi
    else
      emit_check proofshot_version SKIP "proofshot missing"
    fi
  fi

  if [ "$profile" = "triage" ]; then
    for cmd in curl gh; do
      if command -v "$cmd" >/dev/null 2>&1; then
        emit_check "command.$cmd" PASS "$(command -v "$cmd")"
      else
        emit_check "command.$cmd" FAIL "required command missing"
        failures=$((failures + 1))
      fi
    done

    if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
      emit_check gh_auth PASS "authenticated"
    else
      emit_check gh_auth FAIL "run gh auth login"
      failures=$((failures + 1))
    fi

    env_file="${RECON_JIRA_ENV:-$HOME/.config/jira/env}"
    if [ -r "$env_file" ]; then
      emit_check jira_env PASS "$env_file"
      set +u
      # shellcheck disable=SC1090
      set -a; source "$env_file"; set +a
      set -u
      if [ -n "${JIRA_HOST:-}" ] && [ -n "${JIRA_EMAIL:-}" ] && [ -n "${JIRA_API_TOKEN:-}" ]; then
        emit_check jira_config PASS "required values present"
        if network_disabled; then
          emit_check jira_reachability FAIL "CODEX_SANDBOX_NETWORK_DISABLED=1 — Jira is unreachable from this sandbox"
          failures=$((failures + 1))
        elif command -v curl >/dev/null 2>&1; then
          host="${JIRA_HOST#https://}"; host="${host%/}"
          tmp="${TMPDIR:-/tmp}/recon-preflight-jira.$$"
          code="$(curl -sS -o "$tmp" -w '%{http_code}' --max-time "${RECON_PREFLIGHT_TIMEOUT:-8}" \
            -u "$JIRA_EMAIL:$JIRA_API_TOKEN" "https://$host/rest/api/2/myself" 2>/dev/null)" || code="000"
          rm -f "$tmp"
          if [ "$code" = "200" ]; then
            emit_check jira_reachability PASS "authenticated GET /myself returned HTTP 200"
          else
            emit_check jira_reachability FAIL "authenticated GET /myself returned HTTP $code"
            failures=$((failures + 1))
          fi
        fi
      else
        emit_check jira_config FAIL "JIRA_HOST, JIRA_EMAIL, and JIRA_API_TOKEN are required"
        failures=$((failures + 1))
        emit_check jira_reachability SKIP "Jira configuration incomplete"
      fi
    else
      emit_check jira_env FAIL "$env_file is not readable"
      failures=$((failures + 1))
      emit_check jira_config SKIP "Jira environment unavailable"
      emit_check jira_reachability SKIP "Jira environment unavailable"
    fi
  fi

  if [ "$failures" -eq 0 ]; then
    printf 'preflight: PASS\n'
  else
    printf 'preflight: FAIL — %s required check(s) failed\n' "$failures"
    return 1
  fi
}

preflight() {
  local profile="${1:-base}" root host surface
  validate_preflight_profile "$profile"
  root="$(recon_root)"
  host="$(detect_host)"
  surface="$(detect_surface)"
  preflight_snapshot "$profile" "$root" "$host" "$surface" 1
}

start() {
  local profile="${1:-}" root host surface
  validate_preflight_profile "$profile"
  root="$(recon_root)"
  host="$(detect_host)"
  surface="$(detect_surface "$host")"

  printf 'root: %s\n' "$root"
  printf 'host: %s\n' "$host"
  printf 'surface: %s\n' "$surface"
  capability_values "$host" "capability."
  preflight_snapshot "$profile" "$root" "$host" "$surface" 0
}

case "$command_name" in
  root) recon_root ;;
  ticket-dir)
    ticket="${2:-}"
    validate_ticket "$ticket"
    printf '%s/%s\n' "$(recon_root)" "$ticket"
    ;;
  detect-host) detect_host ;;
  detect-surface) detect_surface ;;
  invocation) invocation "${2:-}" "${3:-}" ;;
  capabilities) capabilities "${2:-}" ;;
  preflight) preflight "${2:-base}" ;;
  start) start "${2:-}" ;;
  help|--help|-h)
    cat <<'EOF'
usage: reconctl.sh <command>

commands:
  root                              print the absolute Recon workspace root
  ticket-dir <TICKET>               print and validate one ticket workspace path
  detect-host                       print claude-code, codex, or unknown
  detect-surface                    print the normalized local execution surface
  invocation <ACTION> [TICKET]      render one host-native Recon invocation
  capabilities [HOST]               print the local host capability contract
  preflight [base|triage|repro]     verify required local execution preconditions
  start <base|triage|repro>         print one runtime/capability/preflight snapshot

environment:
  RECON_ROOT                         absolute workspace root override
  RECON_HOST                         explicit host override (highest precedence)
  RECON_SURFACE                      explicit surface override
  RECON_JIRA_ENV                     Jira env file override for preflight tests
  RECON_PREFLIGHT_TIMEOUT            Jira reachability timeout in seconds
  RECON_PROOFSHOT_VERSION            pinned repro recorder version (default 1.6.0)

The default root remains ~/.claude/recon for backward compatibility.
Supported executable hosts in v0.15.0 are Claude Code and local Codex.
EOF
    ;;
  *) echo "unknown command: $command_name" >&2; exit 2 ;;
esac
