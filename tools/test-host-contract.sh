#!/bin/bash
# Isolated contract test for local Claude Code / Codex runtime behavior.
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
CTL="$ROOT/recon/scripts/reconctl.sh"
BASE_TMP="${TMPDIR:-/tmp}"
BASE_TMP="${BASE_TMP%/}"
FIXTURE="$(mktemp -d "$BASE_TMP/recon-host-contract.XXXXXX")"

cleanup() {
  case "$FIXTURE" in
    "$BASE_TMP"/recon-host-contract.*) rm -rf "$FIXTURE" ;;
    *) echo "refusing to remove unexpected fixture path: $FIXTURE" >&2 ;;
  esac
}
trap cleanup EXIT

fail() { echo "host contract: FAIL — $1" >&2; exit 1; }
assert_eq() { [ "$1" = "$2" ] || fail "$3 (expected '$2', got '$1')"; }
assert_contains() { printf '%s\n' "$1" | grep -Fq "$2" || fail "$3 (missing '$2')"; }

clean_env() {
  env -i HOME="$HOME" PATH="$PATH" "$@"
}

assert_eq "$(clean_env RECON_HOST=claude bash "$CTL" detect-host)" "claude-code" "explicit Claude normalization"
assert_eq "$(clean_env RECON_HOST=codex-app bash "$CTL" detect-host)" "codex" "explicit Codex normalization"
assert_eq "$(clean_env CLAUDECODE=1 bash "$CTL" detect-host)" "claude-code" "Claude environment detection"
assert_eq "$(clean_env CODEX_THREAD_ID=test bash "$CTL" detect-host)" "codex" "Codex environment detection"
assert_eq "$(clean_env bash "$CTL" detect-host)" "unknown" "unknown host fallback"
assert_eq "$(clean_env RECON_SURFACE=Team-Local bash "$CTL" detect-surface)" "team-local" "explicit surface normalization"
assert_eq "$(clean_env CODEX_THREAD_ID=test CODEX_INTERNAL_ORIGINATOR_OVERRIDE='Codex Desktop' bash "$CTL" detect-surface)" "codex-app" "Codex app surface detection"

assert_eq "$(clean_env RECON_HOST=claude bash "$CTL" invocation recon.triage ATT-1234)" "/recon:recon-triage ATT-1234" "Claude invocation"
assert_eq "$(clean_env RECON_HOST=codex bash "$CTL" invocation recon.triage ATT-1234)" '$recon:recon-triage ATT-1234' "Codex invocation"
assert_eq "$(clean_env bash "$CTL" invocation recon.triage ATT-1234)" "Run Recon Triage for ATT-1234" "neutral invocation"

CAPS="$(clean_env RECON_HOST=codex bash "$CTL" capabilities)"
assert_contains "$CAPS" "render_local: available" "Codex local render capability"
assert_contains "$CAPS" "publish_stable_url: unavailable" "Codex stable publishing boundary"

PREFLIGHT="$(clean_env RECON_ROOT="$FIXTURE/workspaces" RECON_HOST=codex bash "$CTL" preflight base)"
assert_contains "$PREFLIGHT" "check.workspace: PASS" "base workspace preflight"
assert_contains "$PREFLIGHT" "preflight: PASS" "base preflight verdict"
if clean_env RECON_ROOT=relative/path bash "$CTL" preflight base >"$FIXTURE/relative.out" 2>&1; then
  fail "relative RECON_ROOT unexpectedly passed"
fi
assert_contains "$(cat "$FIXTURE/relative.out")" "RECON_ROOT must be an absolute path" "relative root failure"

RUN_ROOT="$FIXTURE/runs"
clean_env RECON_ROOT="$RUN_ROOT" RECON_HOST=codex RECON_SURFACE=codex-cli \
  bash "$ROOT/recon/scripts/fresh-workspace.sh" TEST-1 >"$FIXTURE/fresh.out"
META="$RUN_ROOT/TEST-1/meta.yaml"
grep -Fq "started_host: codex" "$META" || fail "meta missing starting host"
grep -Fq "started_surface: codex-cli" "$META" || fail "meta missing starting surface"

clean_env RECON_ROOT="$RUN_ROOT" RECON_HOST=claude RECON_SURFACE=claude-code \
  bash "$ROOT/recon/scripts/log-event.sh" TEST-1 verdict disposition=READY blockers=0 >"$FIXTURE/event.out"
tail -1 "$RUN_ROOT/TEST-1/history.ndjson" | grep -Fq '"host":"claude-code"' || fail "event missing current host"
tail -1 "$RUN_ROOT/TEST-1/history.ndjson" | grep -Fq '"surface":"claude-code"' || fail "event missing current surface"

clean_env RECON_ROOT="$RUN_ROOT" RECON_HOST=codex \
  bash "$ROOT/recon/scripts/derive-state.sh" TEST-1 >"$FIXTURE/state.out"
STATE="$RUN_ROOT/TEST-1/state/state.yaml"
grep -Fq "next_action: recon.triage" "$STATE" || fail "state missing canonical next action"
if grep -Fq "/recon:" "$STATE"; then
  fail "durable state contains a Claude slash command"
fi

clean_env RECON_ROOT="$RUN_ROOT" RECON_HOST=codex \
  bash "$ROOT/recon/scripts/lint-workspace.sh" TEST-1 >"$FIXTURE/lint.out"
assert_contains "$(cat "$FIXTURE/lint.out")" "lint: clean" "fixture workspace lint"

echo "host contract: PASS"
