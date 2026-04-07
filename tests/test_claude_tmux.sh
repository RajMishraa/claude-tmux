#!/usr/bin/env bash
# claude-tmux test suite
# Plain bash — no external test framework required (KISS).
#
# Usage:
#   ./tests/test_claude_tmux.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CLAUDE_TMUX="${REPO_DIR}/bin/claude-tmux"

# ── test framework ────────────────────────────────────────────────────────────

PASS=0
FAIL=0
_FAILURES=()

pass()  { echo "  PASS  $1"; PASS=$((PASS + 1)); }
fail()  { echo "  FAIL  $1"; FAIL=$((FAIL + 1)); _FAILURES+=("$1"); }

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then pass "$desc"
  else
    fail "$desc"
    echo "        expected: $(printf '%q' "$expected")"
    echo "        actual  : $(printf '%q' "$actual")"
  fi
}

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if [[ "$haystack" == *"$needle"* ]]; then pass "$desc"
  else
    fail "$desc"
    echo "        expected to contain: $needle"
    echo "        actual: $haystack"
  fi
}

assert_not_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if [[ "$haystack" != *"$needle"* ]]; then pass "$desc"
  else
    fail "$desc"
    echo "        expected NOT to contain: $needle"
    echo "        actual: $haystack"
  fi
}

assert_exit_ok()   { local desc="$1"; shift; if "$@" >/dev/null 2>&1; then pass "$desc"; else fail "$desc (exit $?)"; fi; }
assert_exit_fail() { local desc="$1"; shift; if "$@" >/dev/null 2>&1; then fail "$desc (expected non-zero)"; else pass "$desc"; fi; }
assert_file_exists() { local desc="$1" path="$2"; if [[ -f "$path" ]]; then pass "$desc"; else fail "$desc (not found: $path)"; fi; }

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
        val = s.get(field, "")
        print(val if isinstance(val, str) else str(val))
        break
PYEOF
)
  assert_eq "$desc" "$expected" "$actual"
}

assert_json_array() {
  # Assert that a JSON array field contains a specific element
  local desc="$1" file="$2" name="$3" field="$4" expected_elem="$5"
  local found
  found=$(python3 - "$file" "$name" "$field" "$expected_elem" <<'PYEOF'
import json, sys
path, name, field, elem = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
with open(path) as f:
    data = json.load(f)
for s in data["sessions"]:
    if s["name"] == name:
        arr = s.get(field, [])
        print("yes" if elem in arr else "no")
        break
PYEOF
)
  if [[ "$found" == "yes" ]]; then pass "$desc"
  else fail "$desc (element '$expected_elem' not found in $field)"; fi
}

# ── test isolation ─────────────────────────────────────────────────────────────
# Each test group uses a fresh temp dir as HOME so the real ~/.claude-tmux
# is never touched.

setup() {
  TEST_HOME=$(mktemp -d)
  export HOME="$TEST_HOME"
  export SESSIONS_FILE="${TEST_HOME}/.claude-tmux/sessions.json"

  mkdir -p "${TEST_HOME}/bin"

  # Stub tmux: has-session always fails (no live sessions), all else succeeds
  cat > "${TEST_HOME}/bin/tmux" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  has-session) exit 1 ;;
  ls)          exit 1 ;;
  *)           exit 0 ;;
esac
EOF
  chmod +x "${TEST_HOME}/bin/tmux"

  # Stub uuidgen: deterministic output for testing
  cat > "${TEST_HOME}/bin/uuidgen" <<'EOF'
#!/usr/bin/env bash
echo "00000000-0000-0000-0000-000000000001"
EOF
  chmod +x "${TEST_HOME}/bin/uuidgen"

  # Stub claude
  cat > "${TEST_HOME}/bin/claude" <<'EOF'
#!/usr/bin/env bash
echo "stub claude $*"
EOF
  chmod +x "${TEST_HOME}/bin/claude"

  export PATH="${TEST_HOME}/bin:$PATH"
}

setup_live_tmux() {
  # Variant: tmux has-session always succeeds (session is "live")
  cat > "${TEST_HOME}/bin/tmux" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${TEST_HOME}/bin/tmux"
}

teardown() {
  rm -rf "$TEST_HOME"
}

# Source script internals for unit testing helpers directly.
# The entrypoint is neutralised so it doesn't run.
_source_script() {
  local tmp
  tmp=$(mktemp)
  # Disable the entrypoint block
  sed \
    's/^\[\[ \$# -eq 0 \]\].*$/: # entrypoint disabled/' \
    "$CLAUDE_TMUX" | \
  sed \
    's/^subcmd=.*$/subcmd="__noop__"/' | \
  sed \
    's/^case "\$subcmd" in$/case "$subcmd" in\n  __noop__) ;;/' \
    > "$tmp"
  # shellcheck disable=SC1090
  source "$tmp"
  rm -f "$tmp"
}

# ── tests ─────────────────────────────────────────────────────────────────────

echo ""
echo "═══ claude-tmux test suite ═══"
echo ""

# ─── 1. version ───────────────────────────────────────────────────────────────
echo "── 1. version"
setup
out=$("$CLAUDE_TMUX" version)
assert_contains "version contains 'claude-tmux v'" "claude-tmux v" "$out"
assert_contains "version contains '0.'" "0." "$out"
teardown

# ─── 2. help ──────────────────────────────────────────────────────────────────
echo "── 2. help"
setup
out=$("$CLAUDE_TMUX" help)
assert_contains "help shows 'new'"     "new"     "$out"
assert_contains "help shows 'attach'"  "attach"  "$out"
assert_contains "help shows 'ls'"      "ls"      "$out"
assert_contains "help shows 'kill'"    "kill"    "$out"
assert_contains "help shows 'restore'" "restore" "$out"
assert_contains "help shows no '--' syntax" "--dangerously-skip-permissions" "$out"
assert_not_contains "help no longer shows '-- <'" "-- <" "$out"
teardown

# ─── 3. unknown subcommand ────────────────────────────────────────────────────
echo "── 3. unknown subcommand"
setup
assert_exit_fail "unknown subcommand exits non-zero" "$CLAUDE_TMUX" bogus
out=$("$CLAUDE_TMUX" bogus 2>&1 || true)
assert_contains "error message shown" "Error: unknown subcommand" "$out"
teardown

# ─── 4. name validation ───────────────────────────────────────────────────────
echo "── 4. name validation"
setup
out=$("$CLAUDE_TMUX" new -s "bad name" 2>&1 || true)
assert_contains "space rejected"     "invalid session name" "$out"
out=$("$CLAUDE_TMUX" new -s "bad/name" 2>&1 || true)
assert_contains "slash rejected"     "invalid session name" "$out"
out=$("$CLAUDE_TMUX" new -s "bad@name" 2>&1 || true)
assert_contains "@ rejected"         "invalid session name" "$out"
out=$("$CLAUDE_TMUX" new 2>&1 || true)
assert_contains "missing -s gives error" "-s <name> is required" "$out"
teardown

# ─── 5. registry init ─────────────────────────────────────────────────────────
echo "── 5. registry init"
setup
_source_script
_ensure_registry
assert_file_exists "sessions.json created" "${TEST_HOME}/.claude-tmux/sessions.json"
assert_exit_ok "scripts dir created" test -d "${TEST_HOME}/.claude-tmux/scripts"
_ensure_registry  # idempotent
assert_file_exists "sessions.json still present after second call" \
  "${TEST_HOME}/.claude-tmux/sessions.json"
teardown

# ─── 6. register session without extra args ───────────────────────────────────
echo "── 6. register session (no extra args)"
setup
_source_script
_ensure_registry
_register_session "my-proj" "/work/my-proj" "uuid-abc"
assert_json_field "name stored"       "${TEST_HOME}/.claude-tmux/sessions.json" "my-proj" "name"       "my-proj"
assert_json_field "cwd stored"        "${TEST_HOME}/.claude-tmux/sessions.json" "my-proj" "cwd"        "/work/my-proj"
assert_json_field "session_id stored" "${TEST_HOME}/.claude-tmux/sessions.json" "my-proj" "session_id" "uuid-abc"
assert_json_field "status is active"  "${TEST_HOME}/.claude-tmux/sessions.json" "my-proj" "status"     "active"
# No args field when none passed
no_args=$(python3 -c "
import json
with open('${TEST_HOME}/.claude-tmux/sessions.json') as f:
    d=json.load(f)
for s in d['sessions']:
    if s['name']=='my-proj':
        print('has_args' if 'args' in s else 'no_args')
")
assert_eq "no args field when none passed" "no_args" "$no_args"
teardown

# ─── 7. register session WITH extra args ──────────────────────────────────────
echo "── 7. register session (with extra args)"
setup
_source_script
_ensure_registry
_register_session "proj-skip" "/work" "uuid-def" "" "--dangerously-skip-permissions"
assert_json_array "dangerously flag stored in args" \
  "${TEST_HOME}/.claude-tmux/sessions.json" "proj-skip" "args" "--dangerously-skip-permissions"

_register_session "proj-model" "/work" "uuid-ghi" "" "--model" "opus"
assert_json_array "model flag stored" \
  "${TEST_HOME}/.claude-tmux/sessions.json" "proj-model" "args" "--model"
assert_json_array "model value stored" \
  "${TEST_HOME}/.claude-tmux/sessions.json" "proj-model" "args" "opus"
teardown

# ─── 8. register deduplication ────────────────────────────────────────────────
echo "── 8. register deduplication"
setup
_source_script
_ensure_registry
_register_session "proj" "/a" "uuid-1"
_register_session "proj" "/b" "uuid-2"
count=$(python3 -c "
import json
with open('${TEST_HOME}/.claude-tmux/sessions.json') as f:
    d=json.load(f)
print(len([s for s in d['sessions'] if s['name']=='proj']))
")
assert_eq "duplicate name replaced (count=1)" "1" "$count"
assert_json_field "latest cwd wins" "${TEST_HOME}/.claude-tmux/sessions.json" "proj" "cwd" "/b"
teardown

# ─── 9. update status ─────────────────────────────────────────────────────────
echo "── 9. update status"
setup
_source_script
_ensure_registry
_register_session "proj" "/work" "uuid-abc"
_update_session_status "proj" "killed"
assert_json_field "status updated to killed" \
  "${TEST_HOME}/.claude-tmux/sessions.json" "proj" "status" "killed"
teardown

# ─── 10. atomic write leaves no temp files ────────────────────────────────────
echo "── 10. atomic write"
setup
_source_script
_ensure_registry
_register_session "proj" "/work" "uuid-abc"
tmp_count=$(find "${TEST_HOME}/.claude-tmux" -name "*.tmp.*" | wc -l | tr -d ' ')
assert_eq "no temp files left" "0" "$tmp_count"
teardown

# ─── 11. _write_new_script: no --dangerously-skip-permissions by default ──────
echo "── 11. new script — no implicit dangerous flag"
setup
_source_script
_ensure_registry
_write_new_script "proj" "uuid-123" "/work" "${TEST_HOME}/bin/claude" > /dev/null
script="${TEST_HOME}/.claude-tmux/scripts/proj.sh"
content=$(cat "$script")
assert_not_contains "no implicit --dangerously-skip-permissions" \
  "--dangerously-skip-permissions" "$content"
assert_contains "contains --session-id"   "--session-id" "$content"
assert_contains "contains --name"         "--name"       "$content"
assert_contains "contains exec bash fallback" "exec bash" "$content"
assert_exit_ok   "script is executable" test -x "$script"
teardown

# ─── 12. _write_new_script: explicit --dangerously-skip-permissions ───────────
echo "── 12. new script — explicit dangerous flag"
setup
_source_script
_ensure_registry
_write_new_script "proj" "uuid-123" "/work" "${TEST_HOME}/bin/claude" \
  "--dangerously-skip-permissions" > /dev/null
content=$(cat "${TEST_HOME}/.claude-tmux/scripts/proj.sh")
assert_contains "explicit flag present in script" \
  "--dangerously-skip-permissions" "$content"
teardown

# ─── 13. _write_new_script: multiple extra args ───────────────────────────────
echo "── 13. new script — multiple extra args"
setup
_source_script
_ensure_registry
_write_new_script "proj" "uuid-123" "/work" "${TEST_HOME}/bin/claude" \
  "--model" "opus" > /dev/null
content=$(cat "${TEST_HOME}/.claude-tmux/scripts/proj.sh")
assert_contains "model flag in script"  "--model" "$content"
assert_contains "model value in script" "opus"    "$content"
teardown

# ─── 14. _write_restore_script: uses --resume with uuid ──────────────────────
echo "── 14. restore script — with uuid"
setup
_source_script
_ensure_registry
_write_restore_script "proj" "uuid-456" "/work" "${TEST_HOME}/bin/claude" > /dev/null
content=$(cat "${TEST_HOME}/.claude-tmux/scripts/proj.sh")
assert_contains     "uses --resume"                "--resume"  "$content"
assert_contains     "contains uuid"                "uuid-456"  "$content"
assert_not_contains "no implicit dangerous flag"   "--dangerously-skip-permissions" "$content"
teardown

# ─── 15. _write_restore_script: replays stored args ─────────────────────────
echo "── 15. restore script — replays args"
setup
_source_script
_ensure_registry
_write_restore_script "proj" "uuid-456" "/work" "${TEST_HOME}/bin/claude" \
  "--dangerously-skip-permissions" "--model" "opus" > /dev/null
content=$(cat "${TEST_HOME}/.claude-tmux/scripts/proj.sh")
assert_contains "stored dangerously flag replayed" "--dangerously-skip-permissions" "$content"
assert_contains "stored model flag replayed"       "--model"                        "$content"
assert_contains "stored model value replayed"      "opus"                           "$content"
teardown

# ─── 16. _write_restore_script: fallback to --name when no uuid ──────────────
echo "── 16. restore script — no uuid fallback"
setup
_source_script
_ensure_registry
_write_restore_script "proj" "" "/work" "${TEST_HOME}/bin/claude" > /dev/null
content=$(cat "${TEST_HOME}/.claude-tmux/scripts/proj.sh")
assert_contains     "fallback uses --name"     "--name"   "$content"
assert_not_contains "fallback has no --resume" "--resume" "$content"
teardown

# ─── 17. _generate_uuid returns lowercase uuid ────────────────────────────────
echo "── 17. generate uuid"
setup
_source_script
uuid=$(_generate_uuid)
assert_contains "uuid has hyphens" "-" "$uuid"
[[ "$uuid" =~ ^[0-9a-f-]+$ ]] && pass "uuid is lowercase hex+hyphens" \
  || fail "uuid is lowercase hex+hyphens (got: $uuid)"
teardown

# ─── 18. ls — empty registry ─────────────────────────────────────────────────
echo "── 18. ls (empty)"
setup
out=$("$CLAUDE_TMUX" ls)
assert_contains "empty message shown" "No sessions registered" "$out"
teardown

# ─── 19. ls — with sessions ──────────────────────────────────────────────────
echo "── 19. ls (with sessions)"
setup
_source_script
_ensure_registry
_register_session "alpha" "/work/alpha" "uuid-a"
_register_session "beta"  "/work/beta"  "uuid-b"
out=$("$CLAUDE_TMUX" ls)
assert_contains "ls shows alpha"      "alpha"  "$out"
assert_contains "ls shows beta"       "beta"   "$out"
assert_contains "ls shows session id" "uuid-a" "$out"
teardown

# ─── 20. ls — live vs stopped state ──────────────────────────────────────────
echo "── 20. ls (live vs stopped)"
setup
_source_script
_ensure_registry
_register_session "myproj" "/work" "uuid-z"
# Make tmux report myproj as live
cat > "${TEST_HOME}/bin/tmux" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  has-session) exit 0 ;;
  ls) echo "myproj" ;;
  *) exit 0 ;;
esac
EOF
chmod +x "${TEST_HOME}/bin/tmux"
out=$("$CLAUDE_TMUX" ls)
assert_contains "live session shows [live]" "[live]" "$out"
teardown

# ─── 21. cmd_new — no -- separator needed ────────────────────────────────────
echo "── 21. cmd_new (no -- separator)"
setup
_source_script
_ensure_registry
# Test arg parsing: --model opus should go into extra_args without --
local_extra_args=()
# Simulate what cmd_new's arg loop does
_test_args=(-s "myproj" --model opus --dangerously-skip-permissions)
_test_name=""
_test_extra=()
while [[ ${#_test_args[@]} -gt 0 ]]; do
  case "${_test_args[0]}" in
    -s|--session) _test_name="${_test_args[1]}"; _test_args=("${_test_args[@]:2}") ;;
    *) _test_extra+=("${_test_args[0]}"); _test_args=("${_test_args[@]:1}") ;;
  esac
done
assert_eq   "name parsed correctly" "myproj" "$_test_name"
assert_eq   "extra args count"      "3"      "${#_test_extra[@]}"
assert_eq   "first extra arg"       "--model"                         "${_test_extra[0]}"
assert_eq   "second extra arg"      "opus"                            "${_test_extra[1]}"
assert_eq   "third extra arg"       "--dangerously-skip-permissions"  "${_test_extra[2]}"
teardown

# ─── 22. cmd_new — existing session attaches ─────────────────────────────────
echo "── 22. cmd_new (existing session attaches)"
setup
setup_live_tmux
_source_script
_ensure_registry
_register_session "existing" "/work" "uuid-ex"
out=$("$CLAUDE_TMUX" new -s existing 2>&1 || true)
assert_contains "reports already running" "already running" "$out"
teardown

# ─── 23. multiple sessions in same directory ─────────────────────────────────
echo "── 23. multiple sessions in same directory"
setup
_source_script
_ensure_registry
_register_session "proj-a" "/shared/dir" "uuid-a" "" "--dangerously-skip-permissions"
_register_session "proj-b" "/shared/dir" "uuid-b" "" "--model" "opus"
_register_session "proj-c" "/shared/dir" "uuid-c"
count=$(python3 -c "
import json
with open('${TEST_HOME}/.claude-tmux/sessions.json') as f:
    d=json.load(f)
print(len([s for s in d['sessions'] if s['cwd']=='/shared/dir']))
")
assert_eq "three sessions in same dir" "3" "$count"
assert_json_field "proj-a has correct id"  "${TEST_HOME}/.claude-tmux/sessions.json" "proj-a" "session_id" "uuid-a"
assert_json_field "proj-b has correct id"  "${TEST_HOME}/.claude-tmux/sessions.json" "proj-b" "session_id" "uuid-b"
assert_json_field "proj-c has correct id"  "${TEST_HOME}/.claude-tmux/sessions.json" "proj-c" "session_id" "uuid-c"
assert_json_array "proj-a args stored"     "${TEST_HOME}/.claude-tmux/sessions.json" "proj-a" "args" "--dangerously-skip-permissions"
assert_json_array "proj-b model stored"    "${TEST_HOME}/.claude-tmux/sessions.json" "proj-b" "args" "--model"
teardown

# ─── 24. _restore_single replays args from registry ──────────────────────────
echo "── 24. restore single — replays stored args"
setup
_source_script
_ensure_registry
_register_session "restore-proj" "/work" "uuid-r" "" "--dangerously-skip-permissions" "--model" "sonnet"
_restore_single "restore-proj"
script="${TEST_HOME}/.claude-tmux/scripts/restore-proj.sh"
assert_file_exists "restore script created" "$script"
content=$(cat "$script")
assert_contains "restore uses --resume"           "--resume"                       "$content"
assert_contains "restore replays dangerous flag"  "--dangerously-skip-permissions" "$content"
assert_contains "restore replays --model"         "--model"                        "$content"
assert_contains "restore replays model value"     "sonnet"                         "$content"
teardown

# ─── 25. _restore_single — no args stored (clean session) ────────────────────
echo "── 25. restore single — no stored args"
setup
_source_script
_ensure_registry
_register_session "clean-proj" "/work" "uuid-clean"
_restore_single "clean-proj"
content=$(cat "${TEST_HOME}/.claude-tmux/scripts/clean-proj.sh")
assert_contains     "restore uses --resume"          "--resume"                       "$content"
assert_not_contains "no unexpected dangerous flag"   "--dangerously-skip-permissions" "$content"
teardown

# ─── 26. cmd_restore — skips already-running sessions ────────────────────────
echo "── 26. cmd_restore (already running)"
setup
_source_script
_ensure_registry
_register_session "running-proj" "/work" "uuid-run"
setup_live_tmux
out=$("$CLAUDE_TMUX" restore)
assert_contains "reports skipping live session" "already running" "$out"
teardown

# ─── 27. cmd_restore — nothing to restore ────────────────────────────────────
echo "── 27. cmd_restore (nothing active)"
setup
_source_script
_ensure_registry
_register_session "dead" "/work" "uuid-d"
_update_session_status "dead" "killed"
out=$("$CLAUDE_TMUX" restore)
assert_contains "reports nothing to do" "No active sessions" "$out"
teardown

# ─── 28. cmd_kill — running session ──────────────────────────────────────────
echo "── 28. cmd_kill (running)"
setup
setup_live_tmux
_source_script
_ensure_registry
_register_session "kill-me" "/work" "uuid-k"
out=$("$CLAUDE_TMUX" kill -s "kill-me")
assert_contains "reports killed"   "Killed"           "$out"
assert_contains "reports registry" "killed in registry" "$out"
assert_json_field "status is killed" "${TEST_HOME}/.claude-tmux/sessions.json" "kill-me" "status" "killed"
teardown

# ─── 29. cmd_kill — not-running session ──────────────────────────────────────
echo "── 29. cmd_kill (not running)"
setup
_source_script
_ensure_registry
_register_session "ghost" "/work" "uuid-g"
out=$("$CLAUDE_TMUX" kill -s "ghost")
assert_contains "reports not running"  "not running"       "$out"
assert_contains "still marks registry" "killed in registry" "$out"
assert_json_field "status still killed" "${TEST_HOME}/.claude-tmux/sessions.json" "ghost" "status" "killed"
teardown

# ─── 30. cmd_attach — TTY prompt skipped in non-interactive mode ─────────────
echo "── 30. cmd_attach (non-interactive, session not running)"
setup
_source_script
_ensure_registry
_register_session "no-tty" "/work" "uuid-nt"
# stdin is not a TTY in this test — should not hang on read
out=$("$CLAUDE_TMUX" attach -s no-tty 2>&1 < /dev/null || true)
assert_contains "reports not running"  "not running"  "$out"
assert_contains "suggests restore cmd" "restore"      "$out"
teardown

# ─── 31. _set_session_url stores URL ──────────────────────────────────────────
echo "── 31. set session URL"
setup
_source_script
_ensure_registry
_register_session "url-proj" "/work" "uuid-u"
_set_session_url "url-proj" "https://claude.ai/code/abc123"
assert_json_field "url stored" \
  "${TEST_HOME}/.claude-tmux/sessions.json" "url-proj" "url" "https://claude.ai/code/abc123"
teardown

# ─── 32. _get_session_url reads URL ──────────────────────────────────────────
echo "── 32. get session URL"
setup
_source_script
_ensure_registry
_register_session "url-proj" "/work" "uuid-u"
_set_session_url "url-proj" "https://claude.ai/code/xyz789"
url=$(_get_session_url "url-proj")
assert_eq "url read back correctly" "https://claude.ai/code/xyz789" "$url"
teardown

# ─── 33. _get_session_url fails when no URL ──────────────────────────────────
echo "── 33. get URL when none set"
setup
_source_script
_ensure_registry
_register_session "no-url-proj" "/work" "uuid-nu"
url=$(_get_session_url "no-url-proj" 2>/dev/null)
assert_eq "no url returns empty string" "" "$url"
teardown

# ─── 34. cmd_url prints stored URL ──────────────────────────────────────────
echo "── 34. cmd_url shows URL"
setup
_source_script
_ensure_registry
_register_session "show-url" "/work" "uuid-su"
_set_session_url "show-url" "https://claude.ai/code/test456"
out=$("$CLAUDE_TMUX" url -s show-url 2>&1)
assert_contains "cmd_url prints URL" "https://claude.ai/code/test456" "$out"
teardown

# ─── 35. cmd_url fails when no URL stored ────────────────────────────────────
echo "── 35. cmd_url with no URL"
setup
_source_script
_ensure_registry
_register_session "empty-url" "/work" "uuid-eu"
out=$("$CLAUDE_TMUX" url -s empty-url 2>&1 || true)
assert_contains "reports no URL" "No URL stored" "$out"
teardown

# ─── 36. ls shows URL column when URLs exist ─────────────────────────────────
echo "── 36. ls with URLs"
setup
_source_script
_ensure_registry
_register_session "proj-a" "/work" "uuid-a"
_register_session "proj-b" "/work" "uuid-b"
_set_session_url "proj-a" "https://claude.ai/code/aaa"
out=$("$CLAUDE_TMUX" ls)
assert_contains "ls shows URL column header" "URL" "$out"
assert_contains "ls shows stored URL" "https://claude.ai/code/aaa" "$out"
assert_contains "ls shows proj-b" "proj-b" "$out"
teardown

# ─── 37. ls shows session ID when no URLs exist ──────────────────────────────
echo "── 37. ls without URLs (legacy view)"
setup
_source_script
_ensure_registry
_register_session "proj-c" "/work" "uuid-c"
out=$("$CLAUDE_TMUX" ls)
assert_contains "ls shows SESSION ID header" "SESSION ID" "$out"
assert_contains "ls shows uuid" "uuid-c" "$out"
teardown

# ─── 38. _capture_url extracts URL from tmux pane ────────────────────────────
echo "── 38. capture URL from pane"
setup
_source_script
# Stub tmux capture-pane to return fake pane content with a URL
cat > "${TEST_HOME}/bin/tmux" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  capture-pane)
    echo "Claude Code v1.0"
    echo "Remote session: https://claude.ai/code/session_abc123"
    echo "Type /help for commands"
    ;;
  has-session) exit 0 ;;
  *) exit 0 ;;
esac
EOF
chmod +x "${TEST_HOME}/bin/tmux"
url=$(_capture_url "test-session")
assert_eq "captured URL from pane" "https://claude.ai/code/session_abc123" "$url"
teardown

# ─── 39. _capture_url returns empty when no URL in pane ──────────────────────
echo "── 39. capture URL (none in pane)"
setup
_source_script
cat > "${TEST_HOME}/bin/tmux" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  capture-pane) echo "Claude Code v1.0"; echo "Type /help" ;;
  *) exit 0 ;;
esac
EOF
chmod +x "${TEST_HOME}/bin/tmux"
url=$(_capture_url "test-session")
assert_eq "empty when no URL in pane" "" "$url"
teardown

# ─── 40. help shows url subcommand ───────────────────────────────────────────
echo "── 40. help shows url"
setup
out=$("$CLAUDE_TMUX" help)
assert_contains "help shows url command" "url -s" "$out"
teardown

# ─── 41. register session with tag ────────────────────────────────────────────
echo "── 41. register with tag"
setup
_source_script
_ensure_registry
_register_session "jira-task" "/work" "uuid-j" "jira"
assert_json_field "tag stored" \
  "${TEST_HOME}/.claude-tmux/sessions.json" "jira-task" "tag" "jira"
teardown

# ─── 42. register session without tag ────────────────────────────────────────
echo "── 42. register without tag"
setup
_source_script
_ensure_registry
_register_session "no-tag" "/work" "uuid-nt"
no_tag=$(python3 -c "
import json
with open('${TEST_HOME}/.claude-tmux/sessions.json') as f:
    d=json.load(f)
for s in d['sessions']:
    if s['name']=='no-tag':
        print('has_tag' if 'tag' in s else 'no_tag')
")
assert_eq "no tag field when none passed" "no_tag" "$no_tag"
teardown

# ─── 43. multiple sessions with same tag ─────────────────────────────────────
echo "── 43. multiple sessions with same tag"
setup
_source_script
_ensure_registry
_register_session "j1" "/work" "uuid-j1" "jira"
_register_session "j2" "/work" "uuid-j2" "jira"
_register_session "d1" "/work" "uuid-d1" "dev"
count=$(python3 -c "
import json
with open('${TEST_HOME}/.claude-tmux/sessions.json') as f:
    d=json.load(f)
print(len([s for s in d['sessions'] if s.get('tag')=='jira']))
")
assert_eq "two jira-tagged sessions" "2" "$count"
teardown

# ─── 44. ls --tag filters by tag ─────────────────────────────────────────────
echo "── 44. ls --tag filter"
setup
_source_script
_ensure_registry
_register_session "j1" "/work" "uuid-j1" "jira"
_register_session "j2" "/work" "uuid-j2" "jira"
_register_session "d1" "/work" "uuid-d1" "dev"
out=$("$CLAUDE_TMUX" ls --tag jira)
assert_contains     "ls tag filter shows j1" "j1" "$out"
assert_contains     "ls tag filter shows j2" "j2" "$out"
assert_not_contains "ls tag filter hides d1" "d1" "$out"
teardown

# ─── 45. ls --tag with no matches ────────────────────────────────────────────
echo "── 45. ls --tag no matches"
setup
_source_script
_ensure_registry
_register_session "d1" "/work" "uuid-d1" "dev"
out=$("$CLAUDE_TMUX" ls --tag nonexistent)
assert_contains "no matches message" "No sessions with tag" "$out"
teardown

# ─── 46. ls shows TAG column when tags exist ──────────────────────────────────
echo "── 46. ls TAG column"
setup
_source_script
_ensure_registry
_register_session "tagged" "/work" "uuid-t" "mygroup"
_register_session "untagged" "/work" "uuid-u"
out=$("$CLAUDE_TMUX" ls)
assert_contains "TAG column header" "TAG" "$out"
assert_contains "tag value shown"   "mygroup" "$out"
teardown

# ─── 47. cmd_new parses --tag correctly ───────────────────────────────────────
echo "── 47. cmd_new --tag parsing"
setup
_source_script
# Simulate arg parsing
_test_args=(-s "proj" --tag "jira" --model opus)
_test_name="" _test_tag="" _test_extra=()
while [[ ${#_test_args[@]} -gt 0 ]]; do
  case "${_test_args[0]}" in
    -s|--session) _test_name="${_test_args[1]}"; _test_args=("${_test_args[@]:2}") ;;
    --tag)        _test_tag="${_test_args[1]}";  _test_args=("${_test_args[@]:2}") ;;
    *)            _test_extra+=("${_test_args[0]}"); _test_args=("${_test_args[@]:1}") ;;
  esac
done
assert_eq "name parsed"   "proj"    "$_test_name"
assert_eq "tag parsed"    "jira"    "$_test_tag"
assert_eq "extra arg"     "--model" "${_test_extra[0]}"
assert_eq "extra val"     "opus"    "${_test_extra[1]}"
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
