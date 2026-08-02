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
assert_eq "$(clean_env CODEX_SANDBOX=seatbelt bash "$CTL" detect-host)" "codex" "Codex sandbox marker detection"
assert_eq "$(clean_env bash "$CTL" detect-host)" "unknown" "unknown host fallback"
# A nested session carries both families; guessing there granted Claude's
# stable-URL publishing to Codex. Ambiguity must fail closed, and an explicit
# RECON_HOST must still win over it.
assert_eq "$(clean_env CLAUDECODE=1 CODEX_THREAD_ID=test bash "$CTL" detect-host)" "unknown" "ambiguous host fails closed"
assert_eq "$(clean_env CLAUDECODE=1 CODEX_SANDBOX=seatbelt RECON_HOST=codex bash "$CTL" detect-host)" "codex" "explicit host overrides ambiguity"
assert_contains "$(clean_env CLAUDECODE=1 CODEX_THREAD_ID=test RECON_ROOT="$FIXTURE/amb" bash "$CTL" preflight base)" \
  "check.host: WARN" "ambiguous host reported by preflight"
AMB_CAPS="$(clean_env CLAUDECODE=1 CODEX_THREAD_ID=test bash "$CTL" capabilities)"
assert_contains "$AMB_CAPS" "publish_stable_url: unavailable" "ambiguous host never gains stable publishing"
assert_eq "$(clean_env RECON_SURFACE=Team-Local bash "$CTL" detect-surface)" "team-local" "explicit surface normalization"
assert_eq "$(clean_env CODEX_THREAD_ID=test CODEX_INTERNAL_ORIGINATOR_OVERRIDE='Codex Desktop' bash "$CTL" detect-surface)" "codex-app" "Codex app surface detection"

assert_eq "$(clean_env RECON_HOST=claude bash "$CTL" invocation recon.triage ATT-1234)" "/recon:recon-triage ATT-1234" "Claude invocation"
assert_eq "$(clean_env RECON_HOST=codex bash "$CTL" invocation recon.triage ATT-1234)" '$recon-triage ATT-1234' "Codex invocation"
assert_eq "$(clean_env bash "$CTL" invocation recon.triage ATT-1234)" "Run Recon Triage for ATT-1234" "neutral invocation"

CAPS="$(clean_env RECON_HOST=codex bash "$CTL" capabilities)"
assert_contains "$CAPS" "render_local: available" "Codex local render capability"
assert_contains "$CAPS" "publish_stable_url: unavailable" "Codex stable publishing boundary"
# hosts.md rule 4 keys off this literal, so the rail must print it.
assert_contains "$(clean_env RECON_HOST=claude bash "$CTL" capabilities)" \
  "publish_stable_url: available" "Claude stable publishing capability"

# One start invocation owns the full pre-mutation snapshot. Runtime identity is
# emitted once, capability keys are namespaced, and the read-only base profile
# must not create the configured workspace root.
START_ROOT="$FIXTURE/start-pass"
START_PASS="$(clean_env RECON_ROOT="$START_ROOT" RECON_HOST=codex RECON_SURFACE=codex-cli \
  bash "$CTL" start base)"
START_PREFIX="$(printf '%s\n' "$START_PASS" | sed -n '1,4p')"
assert_eq "$START_PREFIX" "root: $START_ROOT
host: codex
surface: codex-cli
capability.ask_user: request_user_input when available; otherwise ask and stop" "atomic start output order"
assert_contains "$START_PASS" "capability.publish_stable_url: unavailable" "atomic start capability snapshot"
assert_contains "$START_PASS" "profile: base" "atomic start preflight profile"
assert_contains "$START_PASS" "preflight: PASS" "atomic start pass verdict"
assert_eq "$(printf '%s\n' "$START_PASS" | grep -c '^host: ')" "1" "atomic start emits host once"
[ ! -e "$START_ROOT" ] || fail "atomic start mutated the workspace root"

# Nested host markers fail closed inside the same snapshot: unknown identity,
# conservative capabilities, an explicit warning, and a passing base preflight.
AMB_START_ROOT="$FIXTURE/start-ambiguous"
AMB_START="$(clean_env CLAUDECODE=1 CODEX_THREAD_ID=test RECON_ROOT="$AMB_START_ROOT" \
  bash "$CTL" start base)"
assert_contains "$AMB_START" "host: unknown" "ambiguous atomic start host"
assert_contains "$AMB_START" "surface: unknown" "ambiguous atomic start surface"
assert_contains "$AMB_START" "capability.publish_stable_url: unavailable" "ambiguous atomic start capabilities"
assert_contains "$AMB_START" "check.host: WARN" "ambiguous atomic start warning"
assert_contains "$AMB_START" "preflight: PASS" "ambiguous atomic start preflight"
[ ! -e "$AMB_START_ROOT" ] || fail "ambiguous atomic start mutated the workspace root"

if clean_env RECON_ROOT="$FIXTURE/start-missing-profile" bash "$CTL" start \
  >"$FIXTURE/start-missing-profile.out" 2>&1; then
  fail "atomic start passed without a preflight profile"
fi
assert_contains "$(cat "$FIXTURE/start-missing-profile.out")" \
  "unknown preflight profile" "atomic start requires an explicit profile"
assert_contains "$(clean_env bash "$CTL" help)" "start <base|triage|repro>" "atomic start help"

# The repro profile pins the recorder: absent binaries or a version mismatch
# fail closed; a stubbed pinned install passes.
STUB_BIN="$FIXTURE/recorder-stub-bin"
mkdir -p "$STUB_BIN"
printf '#!/bin/bash\n[ "${1:-}" = "--version" ] && echo 1.6.0\nexit 0\n' >"$STUB_BIN/proofshot"
printf '#!/bin/bash\nexit 0\n' >"$STUB_BIN/agent-browser"
chmod +x "$STUB_BIN/proofshot" "$STUB_BIN/agent-browser"
if clean_env RECON_ROOT="$FIXTURE/repro-missing" PATH="/usr/bin:/bin" \
  bash "$CTL" preflight repro >"$FIXTURE/repro-missing.out" 2>&1; then
  fail "repro preflight passed without the recorder installed"
fi
assert_contains "$(cat "$FIXTURE/repro-missing.out")" \
  "check.command.proofshot: FAIL" "repro preflight fails closed without proofshot"
REPRO_PF="$(clean_env RECON_ROOT="$FIXTURE/workspaces" PATH="$STUB_BIN:/usr/bin:/bin" \
  bash "$CTL" preflight repro)"
assert_contains "$REPRO_PF" "check.proofshot_version: PASS" "pinned recorder version passes"
assert_contains "$REPRO_PF" "preflight: PASS" "repro preflight verdict"
if clean_env RECON_ROOT="$FIXTURE/workspaces" PATH="$STUB_BIN:/usr/bin:/bin" \
  RECON_PROOFSHOT_VERSION=9.9.9 bash "$CTL" preflight repro \
  >"$FIXTURE/repro-mismatch.out" 2>&1; then
  fail "repro preflight passed a version mismatch"
fi
assert_contains "$(cat "$FIXTURE/repro-mismatch.out")" \
  "check.proofshot_version: FAIL" "version mismatch fails closed"

# Codex declares its own network policy; preflight must not probe past it.
assert_contains "$(clean_env RECON_HOST=codex CODEX_SANDBOX_NETWORK_DISABLED=1 bash "$CTL" capabilities)" \
  "network: unavailable" "declared network policy honored"
printf 'JIRA_HOST=example.atlassian.net\nJIRA_EMAIL=t@example.com\nJIRA_API_TOKEN=t\n' >"$FIXTURE/jira.env"
if clean_env RECON_HOST=codex CODEX_SANDBOX_NETWORK_DISABLED=1 RECON_ROOT="$FIXTURE/net" \
  RECON_JIRA_ENV="$FIXTURE/jira.env" bash "$CTL" start triage >"$FIXTURE/net.out" 2>&1; then
  fail "atomic triage start passed with the network declared disabled"
fi
START_FAIL="$(cat "$FIXTURE/net.out")"
assert_contains "$START_FAIL" "root: $FIXTURE/net" "atomic start failure retains root snapshot"
assert_contains "$START_FAIL" "host: codex" "atomic start failure retains host snapshot"
assert_contains "$START_FAIL" "capability.network: unavailable" "atomic start failure retains capability snapshot"
assert_contains "$START_FAIL" "CODEX_SANDBOX_NETWORK_DISABLED=1" "network short-circuit reason"
assert_contains "$START_FAIL" "preflight: FAIL" "atomic start fail verdict"

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
grep -Fq "started_host: codex" "$META" || fail "later event changed the starting host snapshot"
if tail -1 "$RUN_ROOT/TEST-1/history.ndjson" | grep -Fq '"host":"codex"'; then
  fail "later event reused the starting host instead of current provenance"
fi

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
