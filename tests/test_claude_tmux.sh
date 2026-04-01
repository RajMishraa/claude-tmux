#!/usr/bin/env bash
# claude-tmux test suite
# Plain bash — no external test framework required (KISS).
#
# Usage:
#   ./tests/test_claude_tmux.sh
#
# Tests run against the script directly; no real tmux or claude sessions
# are created. tmux and claude calls are stubbed via PATH manipulation.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CLAUDE_TMUX="${REPO_DIR}/bin/claude-tmux"

# ── test framework ────────────────────────────────────────────────────────────

PASS=0
FAIL=0
_FAILURES=()

pass() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL  $1"; FAIL=$((FAIL + 1)); _FAILURES+=("$1"); }

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    pass "$desc"
  else
    fail "$desc"
    echo "        expected: $(printf '%q' "$expected")"
    echo "        actual  : $(printf '%q' "$actual")"
  fi
}

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    pass "$desc"
  else
    fail "$desc"
    echo "        expected to contain: $needle"
    echo "        actual: $haystack"
  fi
}

assert_exit_ok() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then
    pass "$desc"
  else
    fail "$desc (exit $?)"
  fi
}

assert_exit_fail() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then
    fail "$desc (expected non-zero exit)"
  else
    pass "$desc"
  fi
}

assert_file_exists() {
  local desc="$1" path="$2"
  if [[ -f "$path" ]]; then
    pass "$desc"
  else
    fail "$desc (file not found: $path)"
  fi
}

assert_json_field() {
  local desc="$1" file="$2" name="$3" field="$4" expected="$5"
  local actual
  actual=$(python3 - "$file" "$name" "$field" <<'PYEOF'
import json, sys
path, name, field = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path) as f:
    data = json.load(f)
for s in data["sessions"]:
    if s["name"] == name:
        print(s.get(field, ""))
        break
PYEOF
)
  assert_eq "$desc" "$expected" "$actual"
}

# ── test isolation ─────────────────────────────────────────────────────────────

# Each test group uses a fresh temp dir as HOME so the real ~/.claude-tmux
# is never touched.

setup() {
  TEST_HOME=$(mktemp -d)
  export HOME="$TEST_HOME"
  export SESSIONS_FILE="${TEST_HOME}/.claude-tmux/sessions.json"
  # Stub tmux: always reports "no session" and accepts all commands silently
  mkdir -p "${TEST_HOME}/bin"
  cat > "${TEST_HOME}/bin/tmux" <<'EOF'
#!/usr/bin/env bash
# Stub: has-session always fails (no live sessions), everything else succeeds
case "${1:-}" in
  has-session) exit 1 ;;
  ls)          exit 1 ;;
  *)           exit 0 ;;
esac
EOF
  chmod +x "${TEST_HOME}/bin/tmux"
  # Stub uuidgen
  cat > "${TEST_HOME}/bin/uuidgen" <<'EOF'
#!/usr/bin/env bash
echo "00000000-0000-0000-0000-000000000001"
EOF
  chmod +x "${TEST_HOME}/bin/uuidgen"
  # Stub claude (so _claude_bin succeeds)
  cat > "${TEST_HOME}/bin/claude" <<'EOF'
#!/usr/bin/env bash
echo "stub claude $*"
EOF
  chmod +x "${TEST_HOME}/bin/claude"
  export PATH="${TEST_HOME}/bin:$PATH"
}

teardown() {
  rm -rf "$TEST_HOME"
}

# ── helpers under test (source the script's internals) ────────────────────────

# We source the script with a guard so the entrypoint doesn't run.
_source_script() {
  # Replace the entrypoint block with a no-op for sourcing
  local tmp
  tmp=$(mktemp)
  sed 's/^\[\[ \$# -eq 0 \]\].*//;s/^subcmd=.*/subcmd="__noop__"/;s/^case.*subcmd.*/case "$subcmd" in __noop__) ;;/' \
    "$CLAUDE_TMUX" > "$tmp"
  # shellcheck disable=SC1090
  source "$tmp"
  rm -f "$tmp"
}

# ── tests ─────────────────────────────────────────────────────────────────────

echo ""
echo "═══ claude-tmux test suite ═══"
echo ""

# ─── 1. Version ───────────────────────────────────────────────────────────────
echo "── version"
setup
out=$("$CLAUDE_TMUX" version)
assert_contains "version output contains 'claude-tmux v'" "claude-tmux v" "$out"
assert_contains "version output contains '0.'" "0." "$out"
teardown

# ─── 2. Help ──────────────────────────────────────────────────────────────────
echo "── help"
setup
out=$("$CLAUDE_TMUX" help)
assert_contains "help shows 'new'" "new" "$out"
assert_contains "help shows 'attach'" "attach" "$out"
assert_contains "help shows 'ls'" "ls" "$out"
assert_contains "help shows 'kill'" "kill" "$out"
assert_contains "help shows 'restore'" "restore" "$out"
teardown

# ─── 3. Unknown subcommand ────────────────────────────────────────────────────
echo "── unknown subcommand"
setup
assert_exit_fail "unknown subcommand exits non-zero" "$CLAUDE_TMUX" bogus
out=$("$CLAUDE_TMUX" bogus 2>&1 || true)
assert_contains "unknown subcommand prints error" "Error: unknown subcommand" "$out"
teardown

# ─── 4. Name validation ───────────────────────────────────────────────────────
echo "── name validation"
setup
out=$("$CLAUDE_TMUX" new -s "bad name" 2>&1 || true)
assert_contains "space in name rejected" "invalid session name" "$out"

out=$("$CLAUDE_TMUX" new -s "bad/name" 2>&1 || true)
assert_contains "slash in name rejected" "invalid session name" "$out"

out=$("$CLAUDE_TMUX" new -s "bad@name" 2>&1 || true)
assert_contains "@ in name rejected" "invalid session name" "$out"

out=$("$CLAUDE_TMUX" new 2>&1 || true)
assert_contains "missing -s flag gives error" "-s <name> is required" "$out"
teardown

# ─── 5. _ensure_registry creates dirs and file ────────────────────────────────
echo "── registry init"
setup
_source_script
_ensure_registry
assert_file_exists "sessions.json created" "${TEST_HOME}/.claude-tmux/sessions.json"
assert_exit_ok "scripts dir created" test -d "${TEST_HOME}/.claude-tmux/scripts"
# Running again is idempotent
_ensure_registry
assert_file_exists "sessions.json still exists after second call" \
  "${TEST_HOME}/.claude-tmux/sessions.json"
teardown

# ─── 6. _register_session writes correct JSON ─────────────────────────────────
echo "── register session"
setup
_source_script
_ensure_registry
_register_session "my-proj" "/work/my-proj" "aaaaaaaa-0000-0000-0000-000000000001"
assert_file_exists "sessions.json exists after register" \
  "${TEST_HOME}/.claude-tmux/sessions.json"
assert_json_field "name stored" \
  "${TEST_HOME}/.claude-tmux/sessions.json" "my-proj" "name" "my-proj"
assert_json_field "cwd stored" \
  "${TEST_HOME}/.claude-tmux/sessions.json" "my-proj" "cwd" "/work/my-proj"
assert_json_field "session_id stored" \
  "${TEST_HOME}/.claude-tmux/sessions.json" "my-proj" "session_id" \
  "aaaaaaaa-0000-0000-0000-000000000001"
assert_json_field "status is active" \
  "${TEST_HOME}/.claude-tmux/sessions.json" "my-proj" "status" "active"
teardown

# ─── 7. _register_session deduplicates by name ────────────────────────────────
echo "── register deduplication"
setup
_source_script
_ensure_registry
_register_session "proj" "/a" "uuid-1"
_register_session "proj" "/b" "uuid-2"
count=$(python3 -c "
import json
with open('${TEST_HOME}/.claude-tmux/sessions.json') as f:
    d = json.load(f)
print(len([s for s in d['sessions'] if s['name'] == 'proj']))
")
assert_eq "duplicate name replaced (count=1)" "1" "$count"
assert_json_field "latest cwd wins" \
  "${TEST_HOME}/.claude-tmux/sessions.json" "proj" "cwd" "/b"
teardown

# ─── 8. _update_session_status changes status ─────────────────────────────────
echo "── update status"
setup
_source_script
_ensure_registry
_register_session "proj" "/work" "uuid-abc"
_update_session_status "proj" "killed"
assert_json_field "status updated to killed" \
  "${TEST_HOME}/.claude-tmux/sessions.json" "proj" "status" "killed"
teardown

# ─── 9. Atomic write: no temp file left on success ────────────────────────────
echo "── atomic write"
setup
_source_script
_ensure_registry
_register_session "proj" "/work" "uuid-abc"
tmp_count=$(find "${TEST_HOME}/.claude-tmux" -name "*.tmp.*" | wc -l | tr -d ' ')
assert_eq "no temp files left after write" "0" "$tmp_count"
teardown

# ─── 10. _write_new_script creates executable script ─────────────────────────
echo "── write new script"
setup
_source_script
_ensure_registry
_write_new_script "proj" "uuid-123" "/work" "${TEST_HOME}/bin/claude" > /dev/null
script="${TEST_HOME}/.claude-tmux/scripts/proj.sh"
assert_file_exists "startup script created" "$script"
content=$(cat "$script")
assert_contains "script contains session-id flag" "--session-id" "$content"
assert_contains "script contains name flag" "--name" "$content"
assert_contains "script contains exec bash fallback" "exec bash" "$content"
assert_exit_ok "startup script is executable" test -x "$script"
teardown

# ─── 11. _write_restore_script uses --resume when uuid present ────────────────
echo "── write restore script (with uuid)"
setup
_source_script
_ensure_registry
_write_restore_script "proj" "uuid-456" "/work" "${TEST_HOME}/bin/claude" > /dev/null
script="${TEST_HOME}/.claude-tmux/scripts/proj.sh"
content=$(cat "$script")
assert_contains "restore script uses --resume" "--resume" "$content"
assert_contains "restore script contains uuid" "uuid-456" "$content"
teardown

# ─── 12. _write_restore_script falls back when uuid is empty ─────────────────
echo "── write restore script (no uuid fallback)"
setup
_source_script
_ensure_registry
_write_restore_script "proj" "" "/work" "${TEST_HOME}/bin/claude" > /dev/null
script="${TEST_HOME}/.claude-tmux/scripts/proj.sh"
content=$(cat "$script")
assert_contains "no-uuid restore uses --name" "--name" "$content"
out=$(grep -- "--resume" "$script" 2>/dev/null || echo "no-resume")
assert_eq "no-uuid restore does not use --resume" "no-resume" "$out"
teardown

# ─── 13. _generate_uuid returns lowercase UUID format ─────────────────────────
echo "── generate uuid"
setup
_source_script
uuid=$(_generate_uuid)
assert_contains "uuid contains hyphens" "-" "$uuid"
[[ "$uuid" =~ ^[0-9a-f-]+$ ]] && pass "uuid is lowercase hex+hyphens" \
  || fail "uuid is lowercase hex+hyphens (got: $uuid)"
teardown

# ─── 14. ls with empty registry ───────────────────────────────────────────────
echo "── ls (empty)"
setup
out=$("$CLAUDE_TMUX" ls)
assert_contains "ls empty registry message" "No sessions registered" "$out"
teardown

# ─── 15. ls with registered sessions ─────────────────────────────────────────
echo "── ls (with sessions)"
setup
_source_script
_ensure_registry
_register_session "alpha" "/work/alpha" "uuid-a"
_register_session "beta"  "/work/beta"  "uuid-b"
out=$("$CLAUDE_TMUX" ls)
assert_contains "ls shows alpha" "alpha" "$out"
assert_contains "ls shows beta" "beta" "$out"
assert_contains "ls shows session id" "uuid-a" "$out"
teardown

# ─── 16. kill updates registry ───────────────────────────────────────────────
echo "── kill"
setup
_source_script
_ensure_registry
_register_session "myproj" "/work" "uuid-k"
# Stub tmux has-session to succeed for kill test
cat > "${TEST_HOME}/bin/tmux" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "${TEST_HOME}/bin/tmux"
out=$("$CLAUDE_TMUX" kill -s "myproj" 2>&1)
assert_contains "kill reports killed session" "Killed" "$out"
assert_json_field "kill updates status to killed" \
  "${TEST_HOME}/.claude-tmux/sessions.json" "myproj" "status" "killed"
teardown

# ─── 17. kill non-running session still updates registry ─────────────────────
echo "── kill (not running)"
setup
_source_script
_ensure_registry
_register_session "ghost" "/work" "uuid-g"
# tmux has-session returns failure (session not running)
out=$("$CLAUDE_TMUX" kill -s "ghost" 2>&1)
assert_contains "kill not-running reports registry update" "killed in registry" "$out"
assert_json_field "status set to killed" \
  "${TEST_HOME}/.claude-tmux/sessions.json" "ghost" "status" "killed"
teardown

# ─── 18. restore with no active sessions ─────────────────────────────────────
echo "── restore (nothing to restore)"
setup
_source_script
_ensure_registry
_register_session "dead" "/work" "uuid-d"
_update_session_status "dead" "killed"
out=$("$CLAUDE_TMUX" restore 2>&1)
assert_contains "restore reports nothing to do" "No active sessions" "$out"
teardown

# ─── summary ──────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════"
TOTAL=$((PASS + FAIL))
echo "  Results: ${PASS}/${TOTAL} passed"
if [[ ${#_FAILURES[@]} -gt 0 ]]; then
  echo ""
  echo "  Failed tests:"
  for f in "${_FAILURES[@]}"; do
    echo "    - $f"
  done
  echo ""
  exit 1
fi
echo "  All tests passed."
echo ""
