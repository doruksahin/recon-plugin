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

detect_host() {
  if [ -n "${RECON_HOST:-}" ]; then
    normalize_host "$RECON_HOST"
  elif [ -n "${CLAUDECODE:-}" ] || [ -n "${CLAUDE_CODE_ENTRYPOINT:-}" ]; then
    printf 'claude-code\n'
  elif [ -n "${CODEX_THREAD_ID:-}" ] || [ -n "${CODEX_CI:-}" ] || \
       [ -n "${CODEX_SHELL:-}" ] || [ -n "${CODEX_INTERNAL_ORIGINATOR_OVERRIDE:-}" ]; then
    printf 'codex\n'
  else
    printf 'unknown\n'
  fi
}

detect_surface() {
  local host origin
  if [ -n "${RECON_SURFACE:-}" ]; then
    normalize_label "$RECON_SURFACE"
    printf '\n'
    return
  fi
  host="$(detect_host)"
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
    codex) printf '$recon:%s' "$skill" ;;
    *)
      title="$(action_title "$action")"
      printf 'Run %s' "$title"
      [ -z "$ticket" ] || printf ' for'
      ;;
  esac
  [ -z "$ticket" ] || printf ' %s' "$ticket"
  printf '\n'
}

capabilities() {
  local host="${1:-}"
  [ -n "$host" ] || host="$(detect_host)"
  host="$(normalize_host "$host")"
  printf 'host: %s\n' "$host"
  printf 'surface: %s\n' "$(detect_surface)"
  case "$host" in
    claude-code)
      cat <<'EOF'
ask_user: AskUserQuestion
invoke_skill: Skill tool or /recon:<skill>
browser: preview_start + read_page + computer
network: local environment; verify with preflight
render_local: available
display_file: SendUserFile
publish_once: Artifact tool
publish_stable_url: Artifact tool with existing URL
local_shell: available
EOF
      ;;
    codex)
      cat <<'EOF'
ask_user: request_user_input when available; otherwise ask and stop
invoke_skill: native skill invocation or $recon:<skill>
browser: in-app browser/computer-use when available
network: local environment; verify with preflight
render_local: available
display_file: Markdown with an absolute local path
publish_once: unavailable; render-only
publish_stable_url: unavailable; never write state/artifact-url
local_shell: available
EOF
      ;;
    *)
      cat <<'EOF'
ask_user: ask in conversation and stop
invoke_skill: use a host-native skill picker
browser: unavailable until explicitly verified
network: unavailable until explicitly verified
render_local: unavailable until explicitly verified
display_file: unavailable until explicitly verified
publish_once: unavailable
publish_stable_url: unavailable; never write state/artifact-url
local_shell: unavailable until explicitly verified
EOF
      ;;
  esac
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

preflight() {
  local profile="${1:-base}" root parent failures=0 cmd env_file host code tmp
  case "$profile" in
    base|triage) ;;
    *) echo "unknown preflight profile: $profile (expected base|triage)" >&2; exit 2 ;;
  esac

  root="$(recon_root)"
  printf 'profile: %s\n' "$profile"
  printf 'host: %s\n' "$(detect_host)"
  printf 'surface: %s\n' "$(detect_surface)"
  printf 'root: %s\n' "$root"

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
        if command -v curl >/dev/null 2>&1; then
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
  preflight [base|triage]           verify required local execution preconditions

environment:
  RECON_ROOT                         absolute workspace root override
  RECON_HOST                         explicit host override (highest precedence)
  RECON_SURFACE                      explicit surface override
  RECON_JIRA_ENV                     Jira env file override for preflight tests
  RECON_PREFLIGHT_TIMEOUT            Jira reachability timeout in seconds

The default root remains ~/.claude/recon for backward compatibility.
Supported executable hosts in v0.14.0 are Claude Code and local Codex.
EOF
    ;;
  *) echo "unknown command: $command_name" >&2; exit 2 ;;
esac
