#!/bin/bash
# Isolated Codex activation contract: a fake Codex CLI plus two clones prove
# separate-marketplace sync and installed-byte attestation without touching the
# user's Codex config or network.
set -euo pipefail

# Hermetic git: every git command below must act on this script's own throwaway
# fixtures. Inherited git environment variables override -C and cwd discovery,
# so a caller that exports them — git itself when running a pre-commit hook, a
# release tool, a debugging shell — silently redirects the fixture's commits and
# status checks at the REAL repository. That once wrote fixture files onto
# master and overwrote the committer identity. Discovery from cwd is the only
# repository identity this script may use.
unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE GIT_OBJECT_DIRECTORY \
  GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_NAMESPACE \
  GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL

ROOT="$(git rev-parse --show-toplevel)"
ACTIVATOR="$ROOT/recon/scripts/activate-codex-plugin.sh"
BASE_TMP="${TMPDIR:-/tmp}"
BASE_TMP="${BASE_TMP%/}"
FIXTURE="$(mktemp -d "$BASE_TMP/recon-codex-activation.XXXXXX")"
REMOTE="$FIXTURE/remote.git"
SOURCE="$FIXTURE/source"
CONFIGURED="$FIXTURE/configured"
FAKE_BIN="$FIXTURE/bin"
ADD_LOG="$FIXTURE/plugin-add.log"

cleanup() {
  case "$FIXTURE" in
    "$BASE_TMP"/recon-codex-activation.*) rm -rf "$FIXTURE" ;;
    *) echo "refusing to remove unexpected fixture path: $FIXTURE" >&2 ;;
  esac
}
trap cleanup EXIT

fail() { echo "codex activation contract: FAIL — $1" >&2; exit 1; }
assert_contains() { printf '%s\n' "$1" | grep -Fq "$2" || fail "$3 (missing '$2')"; }

write_manifests() {
  local root="$1" version="$2"
  mkdir -p "$root/.agents/plugins" "$root/recon/.codex-plugin" \
    "$root/recon/skills/sample" "$root/recon/bin"
  printf '%s\n' \
    '{' \
    '  "name": "recon-plugin",' \
    '  "plugins": [{' \
    '    "name": "recon",' \
    '    "source": {"source": "local", "path": "./recon"}' \
    '  }]' \
    '}' >"$root/.agents/plugins/marketplace.json"
  printf '{"name":"recon","version":"%s"}\n' "$version" \
    >"$root/recon/.codex-plugin/plugin.json"
  printf '/recon/skills/rogue/\n' >"$root/.gitignore"
  printf '%s\n' '---' 'name: sample' '---' '# Sample' \
    >"$root/recon/skills/sample/SKILL.md"
  printf '%s\n' '#!/bin/bash' 'exit 0' >"$root/recon/bin/tool.sh"
  chmod +x "$root/recon/bin/tool.sh"
  [ -L "$root/recon/current-skill" ] || \
    ln -s skills/sample/SKILL.md "$root/recon/current-skill"
}

git init --bare -q "$REMOTE"
git init -q "$SOURCE"
git -C "$SOURCE" config user.name fixture
git -C "$SOURCE" config user.email fixture@example.invalid
write_manifests "$SOURCE" 0.14.1
git -C "$SOURCE" add .
git -C "$SOURCE" commit -qm 'fixture: v0.14.1'
git -C "$SOURCE" branch -M master
git -C "$SOURCE" remote add origin "$REMOTE"
git -C "$SOURCE" push -qu origin master
git --git-dir="$REMOTE" symbolic-ref HEAD refs/heads/master
git clone -q "$REMOTE" "$CONFIGURED"
CONFIGURED_REAL="$(cd "$CONFIGURED" && pwd -P)"

write_manifests "$SOURCE" 0.15.0
git -C "$SOURCE" add .
git -C "$SOURCE" commit -qm 'fixture: v0.15.0'
git -C "$SOURCE" push -q

mkdir -p "$FAKE_BIN"
cat >"$FAKE_BIN/codex" <<'SH'
#!/bin/bash
set -euo pipefail

case "${1:-}:${2:-}:${3:-}" in
  plugin:marketplace:list)
    # Real codex fails the whole listing when ANY configured marketplace cannot
    # load (e.g. a source path that no longer exists): nothing on stdout, the
    # message on stderr, exit 1.
    if [ "${FAKE_LIST_LOAD_FAILURE:-0}" = "1" ]; then
      printf 'Error: failed to load marketplace(s):\n- `other-plugin` at /nonexistent: marketplace root does not contain a supported manifest\n' >&2
      exit 1
    fi
    python3 - "$FAKE_CONFIGURED_ROOT" "${FAKE_SOURCE_TYPE:-local}" <<'PY'
import json, sys
root, source_type = sys.argv[1:3]
print(json.dumps({"marketplaces": [{
    "name": "recon-plugin",
    "root": root,
    "marketplaceSource": {"sourceType": source_type, "source": root},
}]}))
PY
    ;;
  plugin:marketplace:upgrade)
    git -C "$FAKE_CONFIGURED_ROOT" pull --ff-only >/dev/null
    if [ "${FAKE_DIRTY_AFTER_UPGRADE:-0}" = "1" ]; then
      printf 'dirty after upgrade\n' >"$FAKE_CONFIGURED_ROOT/post-upgrade-dirty.txt"
    fi
    ;;
  plugin:add:*)
    printf 'add\n' >>"$FAKE_ADD_LOG"
    if [ "${FAKE_MUTATE_AFTER_ADD:-0}" = "1" ]; then
      mkdir -p "$FAKE_CONFIGURED_ROOT/recon/skills/rogue"
      printf '%s\n' '---' 'name: post-add-rogue' '---' \
        >"$FAKE_CONFIGURED_ROOT/recon/skills/rogue/SKILL.md"
    fi
    printf '{}\n'
    ;;
  plugin:list:--json)
    if [ "${FAKE_MUTATE_DURING_LIST:-0}" = "1" ]; then
      mkdir -p "$FAKE_CONFIGURED_ROOT/recon/skills/rogue"
      printf '%s\n' '---' 'name: list-time-rogue' '---' \
        >"$FAKE_CONFIGURED_ROOT/recon/skills/rogue/SKILL.md"
    fi
    python3 - "$FAKE_CONFIGURED_ROOT" "${FAKE_STALE_INSTALL:-0}" <<'PY'
import json, sys
from pathlib import Path
root, stale = Path(sys.argv[1]), sys.argv[2] == "1"
plugin_root = root / "recon"
version = json.loads((plugin_root / ".codex-plugin/plugin.json").read_text())["version"]
if stale:
    version = "0.14.1"
print(json.dumps({"installed": [{
    "pluginId": "recon@recon-plugin",
    "name": "recon",
    "marketplaceName": "recon-plugin",
    "version": version,
    "installed": True,
    "enabled": True,
    "source": {"source": "local", "path": str(plugin_root)},
}]}))
PY
    ;;
  *)
    echo "unexpected fake codex call: $*" >&2
    exit 98
    ;;
esac
SH
chmod +x "$FAKE_BIN/codex"

run_activation() {
  env PATH="$FAKE_BIN:$PATH" \
    FAKE_CONFIGURED_ROOT="$CONFIGURED" FAKE_ADD_LOG="$ADD_LOG" "$@" \
    bash -c 'cd "$1" && bash "$2"' _ "$SOURCE" "$ACTIVATOR"
}

OUTPUT="$(run_activation)" || fail "clean separate clone did not activate"
SOURCE_HEAD="$(git -C "$SOURCE" rev-parse HEAD)"
assert_contains "$OUTPUT" "codex: marketplace clone synced — $CONFIGURED_REAL" "clone sync"
assert_contains "$OUTPUT" "codex: activated recon@recon-plugin v0.15.0" "activation version"
assert_contains "$OUTPUT" "codex: verified v0.15.0 commit $SOURCE_HEAD tree sha256:" \
  "materialized tree attestation"
assert_contains "$OUTPUT" "from $CONFIGURED_REAL/recon" \
  "installed commit/path attestation"
grep -Fq '"version":"0.15.0"' "$CONFIGURED/recon/.codex-plugin/plugin.json" || \
  fail "configured clone did not fast-forward to v0.15.0"
[ "$(git -C "$CONFIGURED" rev-parse HEAD)" = "$SOURCE_HEAD" ] || \
  fail "configured clone HEAD did not match source release"

set +e
STALE_OUTPUT="$(run_activation FAKE_STALE_INSTALL=1 2>&1)"
STALE_RC=$?
set -e
[ "$STALE_RC" -ne 0 ] || fail "stale installed version was accepted"
assert_contains "$STALE_OUTPUT" "codex: REFUSED" "stale installed version refusal"
if printf '%s\n' "$STALE_OUTPUT" | grep -Fq 'codex: activated'; then
  fail "stale installed version was reported as activated"
fi

# A clean same-origin branch with the same version but different bytes must not
# pass merely because its manifest and Codex-reported version look current.
git -C "$CONFIGURED" switch -qc same-version-wrong-content
printf 'different released bytes\n' >"$CONFIGURED/recon/wrong-content.txt"
git -C "$CONFIGURED" add recon/wrong-content.txt
git -C "$CONFIGURED" commit -qm 'fixture: same version, different content'
git -C "$CONFIGURED" push -qu --set-upstream origin same-version-wrong-content
set +e
WRONG_HEAD_OUTPUT="$(run_activation 2>&1)"
WRONG_HEAD_RC=$?
set -e
[ "$WRONG_HEAD_RC" -ne 0 ] || fail "same-version different-content HEAD was accepted"
assert_contains "$WRONG_HEAD_OUTPUT" "does not match source released HEAD $SOURCE_HEAD" \
  "same-version different-content refusal"
if printf '%s\n' "$WRONG_HEAD_OUTPUT" | grep -Fq 'codex: activated'; then
  fail "same-version different-content HEAD was reported as activated"
fi
git -C "$CONFIGURED" switch -q master

# The release source itself must be immutable before any synchronization.
printf 'dirty source\n' >"$SOURCE/uncommitted-source.txt"
set +e
SOURCE_DIRTY_OUTPUT="$(run_activation 2>&1)"
SOURCE_DIRTY_RC=$?
set -e
[ "$SOURCE_DIRTY_RC" -ne 0 ] || fail "dirty source release checkout was accepted"
assert_contains "$SOURCE_DIRTY_OUTPUT" "source release checkout is dirty" "dirty source refusal"
rm "$SOURCE/uncommitted-source.txt"

printf 'dirty\n' >"$CONFIGURED/uncommitted.txt"
set +e
DIRTY_OUTPUT="$(run_activation 2>&1)"
DIRTY_RC=$?
set -e
[ "$DIRTY_RC" -ne 0 ] || fail "dirty configured clone was accepted"
assert_contains "$DIRTY_OUTPUT" "configured marketplace clone is dirty" "dirty clone refusal"
rm "$CONFIGURED/uncommitted.txt"

# Ignored plugin content is invisible to status but still changes the
# materialized package Codex sees.
mkdir -p "$CONFIGURED/recon/skills/rogue"
printf '%s\n' '---' 'name: rogue' '---' >"$CONFIGURED/recon/skills/rogue/SKILL.md"
set +e
IGNORED_OUTPUT="$(run_activation 2>&1)"
IGNORED_RC=$?
set -e
[ "$IGNORED_RC" -ne 0 ] || fail "ignored rogue plugin content was accepted"
assert_contains "$IGNORED_OUTPUT" "materialized plugin content is not tracked" \
  "ignored rogue plugin refusal"
if printf '%s\n' "$IGNORED_OUTPUT" | grep -Fq 'codex: activated'; then
  fail "ignored rogue plugin content was reported as activated"
fi
rm -rf "$CONFIGURED/recon/skills/rogue"

# A sparse/skip-worktree omission has a clean status and the expected HEAD but
# does not materialize the released plugin tree.
git -C "$CONFIGURED" update-index --skip-worktree recon/skills/sample/SKILL.md
rm "$CONFIGURED/recon/skills/sample/SKILL.md"
set +e
SPARSE_OUTPUT="$(run_activation 2>&1)"
SPARSE_RC=$?
set -e
[ "$SPARSE_RC" -ne 0 ] || fail "sparse plugin omission was accepted"
assert_contains "$SPARSE_OUTPUT" "sparse/assume-unchanged" "sparse omission refusal"
if printf '%s\n' "$SPARSE_OUTPUT" | grep -Fq 'codex: activated'; then
  fail "sparse plugin omission was reported as activated"
fi
git -C "$CONFIGURED" update-index --no-skip-worktree recon/skills/sample/SKILL.md
git -C "$CONFIGURED" restore recon/skills/sample/SKILL.md

# Assume-unchanged is another clean-status escape hatch and is rejected even
# when the materialized bytes happen to match the index.
git -C "$CONFIGURED" update-index --assume-unchanged recon/skills/sample/SKILL.md
set +e
ASSUME_OUTPUT="$(run_activation 2>&1)"
ASSUME_RC=$?
set -e
[ "$ASSUME_RC" -ne 0 ] || fail "assume-unchanged plugin entry was accepted"
assert_contains "$ASSUME_OUTPUT" "sparse/assume-unchanged" \
  "assume-unchanged entry refusal"
git -C "$CONFIGURED" update-index --no-assume-unchanged recon/skills/sample/SKILL.md

# Codex itself is inside the trust boundary: an ignored rogue skill created
# after plugin add keeps status clean, so only the second tree attestation sees it.
set +e
POST_ADD_OUTPUT="$(run_activation FAKE_MUTATE_AFTER_ADD=1 2>&1)"
POST_ADD_RC=$?
set -e
[ "$POST_ADD_RC" -ne 0 ] || fail "post-add plugin mutation was accepted"
assert_contains "$POST_ADD_OUTPUT" "materialized plugin content is not tracked" \
  "post-add ignored mutation refusal"
if printf '%s\n' "$POST_ADD_OUTPUT" | grep -Fq 'codex: activated'; then
  fail "post-add plugin mutation was reported as activated"
fi
rm -rf "$CONFIGURED/recon/skills/rogue"

# The JSON report is the last external command before success. An ignored rogue
# skill created while that report is produced must be caught by a final, complete
# checkout and tree attestation rather than inheriting the post-add snapshot.
set +e
LIST_MUTATION_OUTPUT="$(run_activation FAKE_MUTATE_DURING_LIST=1 2>&1)"
LIST_MUTATION_RC=$?
set -e
[ "$LIST_MUTATION_RC" -ne 0 ] || fail "list-time plugin mutation was accepted"
assert_contains "$LIST_MUTATION_OUTPUT" "materialized plugin content is not tracked" \
  "list-time ignored mutation refusal"
if printf '%s\n' "$LIST_MUTATION_OUTPUT" | grep -Fq 'codex: activated'; then
  fail "list-time plugin mutation was reported as activated"
fi
rm -rf "$CONFIGURED/recon/skills/rogue"

# A non-local marketplace refresh can itself leave a dirty checkout. Recheck
# cleanliness after the upgrade boundary, before commit or manifest attestation.
set +e
POST_SYNC_DIRTY_OUTPUT="$(run_activation FAKE_SOURCE_TYPE=git FAKE_DIRTY_AFTER_UPGRADE=1 2>&1)"
POST_SYNC_DIRTY_RC=$?
set -e
[ "$POST_SYNC_DIRTY_RC" -ne 0 ] || fail "post-upgrade dirty clone was accepted"
assert_contains "$POST_SYNC_DIRTY_OUTPUT" "dirty after synchronization" \
  "post-upgrade dirty clone refusal"
if printf '%s\n' "$POST_SYNC_DIRTY_OUTPUT" | grep -Fq 'codex: activated'; then
  fail "post-upgrade dirty clone was reported as activated"
fi

# An unrelated broken marketplace entry makes codex fail the whole listing with
# nothing on stdout. The rail must report codex's own words, not die inside a
# JSON parse of empty input.
set +e
LIST_FAILURE_OUTPUT="$(run_activation FAKE_LIST_LOAD_FAILURE=1 2>&1)"
LIST_FAILURE_RC=$?
set -e
[ "$LIST_FAILURE_RC" -ne 0 ] || fail "unreadable marketplace listing was accepted"
assert_contains "$LIST_FAILURE_OUTPUT" "codex could not list marketplaces" \
  "marketplace listing failure refusal"
assert_contains "$LIST_FAILURE_OUTPUT" "does not contain a supported manifest" \
  "marketplace listing failure quotes codex"
if printf '%s\n' "$LIST_FAILURE_OUTPUT" | grep -Fq 'JSONDecodeError'; then
  fail "marketplace listing failure surfaced a raw traceback"
fi

echo "codex activation contract: PASS"
