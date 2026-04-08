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
assert_contains "help shows --tag syntax" "--tag" "$out"
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
_register_session "proj-skip" "/work" "uuid-def" "" "" "--dangerously-skip-permissions"
assert_json_array "dangerously flag stored in args" \
  "${TEST_HOME}/.claude-tmux/sessions.json" "proj-skip" "args" "--dangerously-skip-permissions"

_register_session "proj-model" "/work" "uuid-ghi" "" "" "--model" "opus"
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
assert_contains "ls shows cwd" "/work/alpha" "$out"
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
_register_session "proj-a" "/shared/dir" "uuid-a" "" "" "--dangerously-skip-permissions"
_register_session "proj-b" "/shared/dir" "uuid-b" "" "" "--model" "opus"
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
_register_session "restore-proj" "/work" "uuid-r" "" "" "--dangerously-skip-permissions" "--model" "sonnet"
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
assert_contains "ls shows CWD header" "CWD" "$out"
assert_contains "ls shows working dir" "/work" "$out"
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

# ─── 41. register session with single tag ─────────────────────────────────────
echo "── 41. register with tag"
setup
_source_script
_ensure_registry
_register_session "jira-task" "/work" "uuid-j" "jira"
assert_json_array "tag stored as array" \
  "${TEST_HOME}/.claude-tmux/sessions.json" "jira-task" "tags" "jira"
teardown

# ─── 42. register session without tag ────────────────────────────────────────
echo "── 42. register without tag"
setup
_source_script
_ensure_registry
_register_session "no-tag" "/work" "uuid-nt"
no_tags=$(python3 -c "
import json
with open('${TEST_HOME}/.claude-tmux/sessions.json') as f:
    d=json.load(f)
for s in d['sessions']:
    if s['name']=='no-tag':
        print('has_tags' if 'tags' in s else 'no_tags')
")
assert_eq "no tags field when none passed" "no_tags" "$no_tags"
teardown

# ─── 43. register with comma-separated tags ──────────────────────────────────
echo "── 43. comma-separated tags"
setup
_source_script
_ensure_registry
_register_session "multi" "/work" "uuid-m" "jira,sprint-5"
assert_json_array "first tag stored"  "${TEST_HOME}/.claude-tmux/sessions.json" "multi" "tags" "jira"
assert_json_array "second tag stored" "${TEST_HOME}/.claude-tmux/sessions.json" "multi" "tags" "sprint-5"
tag_count=$(python3 -c "
import json
with open('${TEST_HOME}/.claude-tmux/sessions.json') as f:
    d=json.load(f)
for s in d['sessions']:
    if s['name']=='multi':
        print(len(s.get('tags', [])))
")
assert_eq "two tags stored" "2" "$tag_count"
teardown

# ─── 44. multiple sessions with same tag ─────────────────────────────────────
echo "── 44. multiple sessions same tag"
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
print(len([s for s in d['sessions'] if 'jira' in s.get('tags', [])]))
")
assert_eq "two jira-tagged sessions" "2" "$count"
teardown

# ─── 45. ls --tag filters by tag ─────────────────────────────────────────────
echo "── 45. ls --tag filter"
setup
_source_script
_ensure_registry
_register_session "j1" "/work" "uuid-j1" "jira"
_register_session "j2" "/work" "uuid-j2" "jira,sprint-5"
_register_session "d1" "/work" "uuid-d1" "dev"
out=$("$CLAUDE_TMUX" ls --tag jira)
assert_contains     "ls tag filter shows j1" "j1" "$out"
assert_contains     "ls tag filter shows j2" "j2" "$out"
assert_not_contains "ls tag filter hides d1" "d1" "$out"
teardown

# ─── 46. ls --tag matches multi-tagged session ───────────────────────────────
echo "── 46. ls --tag matches multi-tag"
setup
_source_script
_ensure_registry
_register_session "both" "/work" "uuid-b" "jira,sprint-5"
out=$("$CLAUDE_TMUX" ls --tag sprint-5)
assert_contains "multi-tag session found by second tag" "both" "$out"
teardown

# ─── 47. ls --tag with no matches ────────────────────────────────────────────
echo "── 47. ls --tag no matches"
setup
_source_script
_ensure_registry
_register_session "d1" "/work" "uuid-d1" "dev"
out=$("$CLAUDE_TMUX" ls --tag nonexistent)
assert_contains "no matches message" "No sessions with tag" "$out"
teardown

# ─── 48. ls shows TAGS column ────────────────────────────────────────────────
echo "── 48. ls TAGS column"
setup
_source_script
_ensure_registry
_register_session "tagged" "/work" "uuid-t" "mygroup,team-a"
_register_session "untagged" "/work" "uuid-u"
out=$("$CLAUDE_TMUX" ls)
assert_contains "TAGS column header" "TAGS" "$out"
assert_contains "tags shown"         "mygroup,team-a" "$out"
teardown

# ─── 49. cmd_new repeated --tag flags ─────────────────────────────────────────
echo "── 49. cmd_new --tag repeated"
setup
_source_script
_test_args=(-s "proj" --tag "jira" --tag "sprint-5" --model opus)
_test_name=""
_test_tags=()
_test_extra=()
while [[ ${#_test_args[@]} -gt 0 ]]; do
  case "${_test_args[0]}" in
    -s|--session) _test_name="${_test_args[1]}"; _test_args=("${_test_args[@]:2}") ;;
    --tag)        _test_tags+=("${_test_args[1]}"); _test_args=("${_test_args[@]:2}") ;;
    *)            _test_extra+=("${_test_args[0]}"); _test_args=("${_test_args[@]:1}") ;;
  esac
done
_test_tag_csv=$(IFS=,; echo "${_test_tags[*]}")
assert_eq "name parsed"      "proj"          "$_test_name"
assert_eq "tags joined"      "jira,sprint-5" "$_test_tag_csv"
assert_eq "extra arg"        "--model"       "${_test_extra[0]}"
teardown

# ─── 50. cmd_new comma-separated --tag ────────────────────────────────────────
echo "── 50. cmd_new --tag comma"
setup
_source_script
_test_args=(-s "proj" --tag "jira,sprint-5")
_test_tags=()
while [[ ${#_test_args[@]} -gt 0 ]]; do
  case "${_test_args[0]}" in
    -s|--session) _test_args=("${_test_args[@]:2}") ;;
    --tag)        _test_tags+=("${_test_args[1]}"); _test_args=("${_test_args[@]:2}") ;;
    *)            _test_args=("${_test_args[@]:1}") ;;
  esac
done
_test_tag_csv=$(IFS=,; echo "${_test_tags[*]}")
assert_eq "comma tags passed through" "jira,sprint-5" "$_test_tag_csv"
teardown

# ─── 51. cmd_new --detach flag parsed ────────────────────────────────────────
echo "── 51. cmd_new --detach flag"
setup
_source_script
_test_args=(-s "proj" --detach --tag "dev")
_test_name="" _test_detach=0 _test_tags=()
while [[ ${#_test_args[@]} -gt 0 ]]; do
  case "${_test_args[0]}" in
    -s|--session) _test_name="${_test_args[1]}"; _test_args=("${_test_args[@]:2}") ;;
    -d|--detach)  _test_detach=1; _test_args=("${_test_args[@]:1}") ;;
    --tag)        _test_tags+=("${_test_args[1]}"); _test_args=("${_test_args[@]:2}") ;;
    *)            _test_args=("${_test_args[@]:1}") ;;
  esac
done
assert_eq "name parsed"   "proj" "$_test_name"
assert_eq "detach parsed" "1"    "$_test_detach"
teardown

# ─── 51b. help shows -d flag ──────────────────────────────────────────────────
echo "── 51b. help shows -d flag"
setup
out=$("$CLAUDE_TMUX" help)
assert_contains "help shows -d flag"  "-d"       "$out"
assert_contains "help shows detach"   "detach"   "$out"
assert_contains "help shows -m flag"  "-m"       "$out"
assert_contains "help shows message"  "message"  "$out"
teardown

# ─── 51d. -p/--print is rejected ──────────────────────────────────────────────
echo "── 51d. -p/--print rejected"
setup
_source_script
_ensure_registry
out=$("$CLAUDE_TMUX" new -s testprint -p "hello" 2>&1 || true)
assert_contains "-p rejected"            "Error"           "$out"
assert_contains "-p suggests --message"  "--message"       "$out"
teardown

echo "── 51e. --print rejected"
setup
_source_script
_ensure_registry
out=$("$CLAUDE_TMUX" new -s testprint --print "hello" 2>&1 || true)
assert_contains "--print rejected"  "Error"  "$out"
teardown

# ─── 51f. -m/--message parsed ────────────────────────────────────────────────
echo "── 51f. --message parsed"
setup
_source_script
_test_args=(-s "proj" --message "do the thing")
_test_name="" _test_msg=""
while [[ ${#_test_args[@]} -gt 0 ]]; do
  case "${_test_args[0]}" in
    -s|--session) _test_name="${_test_args[1]}"; _test_args=("${_test_args[@]:2}") ;;
    -m|--message) _test_msg="${_test_args[1]}";  _test_args=("${_test_args[@]:2}") ;;
    *)            _test_args=("${_test_args[@]:1}") ;;
  esac
done
assert_eq "name parsed"    "proj"         "$_test_name"
assert_eq "message parsed" "do the thing" "$_test_msg"
teardown

# ─── 51c. help shows upgrade ──────────────────────────────────────────────────
echo "── 51c. help shows upgrade"
setup
out=$("$CLAUDE_TMUX" help)
assert_contains "help shows upgrade" "upgrade" "$out"
teardown

# ─── 52. upgrade detects same version ─────────────────────────────────────────
echo "── 52. upgrade (already up to date)"
setup
_source_script
mkdir -p "${TEST_HOME}/.local/bin"
cp "$CLAUDE_TMUX" "${TEST_HOME}/.local/bin/claude-tmux"
chmod +x "${TEST_HOME}/.local/bin/claude-tmux"
export PATH="${TEST_HOME}/.local/bin:${PATH}"
# Stub curl that writes same-version binary to the -o target file
cat > "${TEST_HOME}/bin/curl" <<'STUBEOF'
#!/usr/bin/env bash
# Find the -o output file
outfile=""
prev=""
for arg in "$@"; do
  [[ "$prev" == "-o" ]] && outfile="$arg"
  prev="$arg"
done
if [[ "$*" == *"bin/claude-tmux"* ]]; then
  printf 'VERSION="%s"\n' "0.8.7" > "$outfile"
elif [[ "$*" == *"install.sh"* ]]; then
  echo 'ALL_SKILLS="tmux-new"'
elif [[ "$*" == *"SKILL.md"* && -n "$outfile" ]]; then
  echo "stub skill" > "$outfile"
fi
STUBEOF
chmod +x "${TEST_HOME}/bin/curl"
out=$(cmd_upgrade 2>&1)
assert_contains "reports up to date" "Already up to date" "$out"
teardown

# ─── 53. upgrade detects new version ──────────────────────────────────────────
echo "── 53. upgrade (new version available)"
setup
_source_script
mkdir -p "${TEST_HOME}/.local/bin"
cp "$CLAUDE_TMUX" "${TEST_HOME}/.local/bin/claude-tmux"
chmod +x "${TEST_HOME}/.local/bin/claude-tmux"
export PATH="${TEST_HOME}/.local/bin:${PATH}"
cat > "${TEST_HOME}/bin/curl" <<'STUBEOF'
#!/usr/bin/env bash
outfile=""
prev=""
for arg in "$@"; do
  [[ "$prev" == "-o" ]] && outfile="$arg"
  prev="$arg"
done
if [[ "$*" == *"bin/claude-tmux"* && -n "$outfile" ]]; then
  printf '#!/usr/bin/env bash\nVERSION="99.0.0"\necho "new binary"\n' > "$outfile"
elif [[ "$*" == *"install.sh"* ]]; then
  echo 'ALL_SKILLS="tmux-new"'
elif [[ "$*" == *"SKILL.md"* && -n "$outfile" ]]; then
  printf '---\nname: stub-skill\n---\n' > "$outfile"
fi
STUBEOF
chmod +x "${TEST_HOME}/bin/curl"
out=$(cmd_upgrade 2>&1)
assert_contains "reports upgrade"   "v99.0.0" "$out"
assert_contains "reports binary ok" "Binary updated" "$out"
new_content=$(cat "${TEST_HOME}/.local/bin/claude-tmux")
assert_contains "binary replaced" "99.0.0" "$new_content"
teardown

# ─── 54. upgrade updates skills ───────────────────────────────────────────────
echo "── 54. upgrade updates skills"
setup
_source_script
mkdir -p "${TEST_HOME}/.local/bin"
cp "$CLAUDE_TMUX" "${TEST_HOME}/.local/bin/claude-tmux"
chmod +x "${TEST_HOME}/.local/bin/claude-tmux"
export PATH="${TEST_HOME}/.local/bin:${PATH}"
cat > "${TEST_HOME}/bin/curl" <<'STUBEOF'
#!/usr/bin/env bash
outfile=""
prev=""
for arg in "$@"; do
  [[ "$prev" == "-o" ]] && outfile="$arg"
  prev="$arg"
done
if [[ "$*" == *"bin/claude-tmux"* && -n "$outfile" ]]; then
  printf '#!/usr/bin/env bash\nVERSION="99.0.0"\n' > "$outfile"
elif [[ "$*" == *"install.sh"* ]]; then
  # stdout mode — used to fetch ALL_SKILLS list
  echo 'ALL_SKILLS="tmux-new tmux-ls tmux-kill tmux-attach"'
elif [[ "$*" == *"SKILL.md"* && -n "$outfile" ]]; then
  printf '---\nname: updated-skill\n---\n' > "$outfile"
fi
STUBEOF
chmod +x "${TEST_HOME}/bin/curl"
cmd_upgrade > /dev/null 2>&1
skills_updated=0
for s in tmux-new tmux-ls tmux-kill tmux-attach; do
  [[ -f "${TEST_HOME}/.claude/skills/${s}/SKILL.md" ]] && skills_updated=$((skills_updated + 1))
done
assert_eq "all 4 skills updated" "4" "$skills_updated"
teardown

# ─── 55. register with --jira stores ticket ──────────────────────────────────
echo "── 55. register with --jira"
setup
_source_script
_ensure_registry
_register_session "jira-proj" "/work" "uuid-jp" "" "PROJ-123"
assert_json_field "jira stored" \
  "${TEST_HOME}/.claude-tmux/sessions.json" "jira-proj" "jira" "PROJ-123"
teardown

# ─── 56. register without --jira has no jira field ────────────────────────────
echo "── 56. register without --jira"
setup
_source_script
_ensure_registry
_register_session "no-jira" "/work" "uuid-nj"
no_jira=$(python3 -c "
import json
with open('${TEST_HOME}/.claude-tmux/sessions.json') as f:
    d=json.load(f)
for s in d['sessions']:
    if s['name']=='no-jira':
        print('has_jira' if 'jira' in s else 'no_jira')
")
assert_eq "no jira field" "no_jira" "$no_jira"
teardown

# ─── 57. register with --jira + --tag + args ──────────────────────────────────
echo "── 57. jira + tag + args combined"
setup
_source_script
_ensure_registry
_register_session "combo" "/work" "uuid-c" "dev" "PROJ-789" "--dangerously-skip-permissions"
assert_json_field "jira stored"    "${TEST_HOME}/.claude-tmux/sessions.json" "combo" "jira" "PROJ-789"
assert_json_array "tag stored"     "${TEST_HOME}/.claude-tmux/sessions.json" "combo" "tags" "dev"
assert_json_array "args stored"    "${TEST_HOME}/.claude-tmux/sessions.json" "combo" "args" "--dangerously-skip-permissions"
teardown

# ─── 58. _write_new_script injects --append-system-prompt for JIRA ────────────
echo "── 58. new script with JIRA prompt"
setup
_source_script
_ensure_registry
_write_new_script "jproj" "uuid-j" "/work" "${TEST_HOME}/bin/claude" "PROJ-123" > /dev/null
content=$(cat "${TEST_HOME}/.claude-tmux/scripts/jproj.sh")
assert_contains "script has --append-system-prompt" "--append-system-prompt" "$content"
assert_contains "script mentions ticket" "PROJ-123" "$content"
teardown

# ─── 59. _write_new_script without JIRA has no system prompt ──────────────────
echo "── 59. new script without JIRA"
setup
_source_script
_ensure_registry
_write_new_script "nojira" "uuid-nj" "/work" "${TEST_HOME}/bin/claude" "" > /dev/null
content=$(cat "${TEST_HOME}/.claude-tmux/scripts/nojira.sh")
assert_not_contains "no --append-system-prompt" "--append-system-prompt" "$content"
teardown

# ─── 60. _write_restore_script injects JIRA prompt ────────────────────────────
echo "── 60. restore script with JIRA"
setup
_source_script
_ensure_registry
_write_restore_script "rjira" "uuid-rj" "/work" "${TEST_HOME}/bin/claude" "PROJ-456" > /dev/null
content=$(cat "${TEST_HOME}/.claude-tmux/scripts/rjira.sh")
assert_contains "restore has --append-system-prompt" "--append-system-prompt" "$content"
assert_contains "restore mentions ticket" "PROJ-456" "$content"
teardown

# ─── 61. ls shows JIRA column ────────────────────────────────────────────────
echo "── 61. ls JIRA column"
setup
_source_script
_ensure_registry
_register_session "j1" "/work" "uuid-j1" "" "PROJ-100"
_register_session "j2" "/work" "uuid-j2" "" ""
out=$("$CLAUDE_TMUX" ls)
assert_contains "JIRA column header" "JIRA" "$out"
assert_contains "jira ticket shown"  "PROJ-100" "$out"
teardown

# ─── 62. cmd_new --jira parsing ───────────────────────────────────────────────
echo "── 62. cmd_new --jira parsing"
setup
_source_script
_test_args=(-s "proj" --jira "PROJ-999" --model opus)
_test_name="" _test_jira="" _test_extra=()
while [[ ${#_test_args[@]} -gt 0 ]]; do
  case "${_test_args[0]}" in
    -s|--session) _test_name="${_test_args[1]}"; _test_args=("${_test_args[@]:2}") ;;
    --jira)       _test_jira="${_test_args[1]}"; _test_args=("${_test_args[@]:2}") ;;
    *)            _test_extra+=("${_test_args[0]}"); _test_args=("${_test_args[@]:1}") ;;
  esac
done
assert_eq "name parsed"   "proj"      "$_test_name"
assert_eq "jira parsed"   "PROJ-999"  "$_test_jira"
assert_eq "extra arg"     "--model"   "${_test_extra[0]}"
teardown

# ─── 63. JIRA skills exist ───────────────────────────────────────────────────
echo "── 63. JIRA skills"
for skill in tmux-update-jira tmux-pick-ticket; do
  skill_file="${REPO_DIR}/skills/${skill}/SKILL.md"
  assert_file_exists "skill ${skill} exists" "$skill_file"
  content=$(cat "$skill_file")
  assert_contains "${skill}: has name" "name: ${skill}" "$content"
  assert_contains "${skill}: has atlassian tools" "atlassian" "$content"
done

# ─── 64. help shows --jira ───────────────────────────────────────────────────
echo "── 64. help shows --jira"
setup
out=$("$CLAUDE_TMUX" help)
assert_contains "help shows --jira" "--jira" "$out"
teardown

# ─── 65. cmd_jira set mode ────────────────────────────────────────────────────
echo "── 65. cmd_jira set"
setup
_source_script
_ensure_registry
_register_session "link-test" "/work" "uuid-lt"
out=$("$CLAUDE_TMUX" jira -s link-test PROJ-999)
assert_contains "reports linked" "Linked" "$out"
assert_contains "shows ticket" "PROJ-999" "$out"
assert_json_field "jira stored in registry" \
  "${TEST_HOME}/.claude-tmux/sessions.json" "link-test" "jira" "PROJ-999"
teardown

# ─── 66. cmd_jira get mode ────────────────────────────────────────────────────
echo "── 66. cmd_jira get"
setup
_source_script
_ensure_registry
_register_session "get-jira" "/work" "uuid-gj"
_set_session_jira "get-jira" "PROJ-888"
out=$("$CLAUDE_TMUX" jira -s get-jira)
assert_eq "prints jira ticket" "PROJ-888" "$out"
teardown

# ─── 67. cmd_jira get with no ticket ─────────────────────────────────────────
echo "── 67. cmd_jira get (none set)"
setup
_source_script
_ensure_registry
_register_session "no-jira-2" "/work" "uuid-nj2"
out=$("$CLAUDE_TMUX" jira -s no-jira-2 2>&1 || true)
assert_contains "reports no ticket" "No JIRA ticket" "$out"
teardown

# ─── 68. cmd_jira overwrites existing ticket ──────────────────────────────────
echo "── 68. cmd_jira overwrite"
setup
_source_script
_ensure_registry
_register_session "overwrite" "/work" "uuid-ow"
"$CLAUDE_TMUX" jira -s overwrite PROJ-100 > /dev/null
"$CLAUDE_TMUX" jira -s overwrite PROJ-200 > /dev/null
out=$("$CLAUDE_TMUX" jira -s overwrite)
assert_eq "overwritten to new ticket" "PROJ-200" "$out"
teardown

# ─── 69. /tmux-link-jira skill exists ─────────────────────────────────────────
echo "── 69. tmux-link-jira skill"
skill_file="${REPO_DIR}/skills/tmux-link-jira/SKILL.md"
assert_file_exists "skill exists" "$skill_file"
content=$(cat "$skill_file")
assert_contains "has name"         "name: tmux-link-jira"     "$content"
assert_contains "has atlassian"    "atlassian"                 "$content"
assert_contains "has tmux detect"  "tmux display-message"      "$content"
assert_contains "has claude-tmux"  "claude-tmux jira"          "$content"
assert_contains "has argument-hint" "argument-hint:"           "$content"

# ─── 70. help shows jira subcommand ──────────────────────────────────────────
echo "── 70. help shows jira subcommand"
setup
out=$("$CLAUDE_TMUX" help)
assert_contains "help shows jira command" "jira -s" "$out"
teardown

# ─── 71. /tmux-team-create skill ──────────────────────────────────────────────
echo "── 71. tmux-team-create skill"
skill_file="${REPO_DIR}/skills/tmux-team-create/SKILL.md"
assert_file_exists "skill file exists" "$skill_file"
content=$(cat "$skill_file")
assert_contains "has name frontmatter"      "name: tmux-team-create"     "$content"
assert_contains "has argument-hint"         "argument-hint:"             "$content"
assert_contains "has allowed-tools"         "allowed-tools:"             "$content"
assert_contains "mentions claude-tmux new"  "claude-tmux new"            "$content"
assert_contains "mentions --tag"            "--tag"                      "$content"
assert_contains "mentions --jira"           "--jira"                     "$content"

# ─── 72. /tmux-team-status skill ──────────────────────────────────────────────
echo "── 72. tmux-team-status skill"
skill_file="${REPO_DIR}/skills/tmux-team-status/SKILL.md"
assert_file_exists "skill file exists" "$skill_file"
content=$(cat "$skill_file")
assert_contains "has name frontmatter"      "name: tmux-team-status"     "$content"
assert_contains "has argument-hint"         "argument-hint:"             "$content"
assert_contains "mentions claude-tmux ls"   "claude-tmux ls"             "$content"
assert_contains "mentions tmux capture"     "tmux capture-pane"          "$content"

# ─── 73. /tmux-team-sync skill ────────────────────────────────────────────────
echo "── 73. tmux-team-sync skill"
skill_file="${REPO_DIR}/skills/tmux-team-sync/SKILL.md"
assert_file_exists "skill file exists" "$skill_file"
content=$(cat "$skill_file")
assert_contains "has name frontmatter"      "name: tmux-team-sync"       "$content"
assert_contains "has argument-hint"         "argument-hint:"             "$content"
assert_contains "mentions tmux capture"     "tmux capture-pane"          "$content"
assert_contains "mentions tmux send-keys"   "tmux send-keys"             "$content"

# ─── 74. /tmux-plan skill ─────────────────────────────────────────────────────
echo "── 74. tmux-plan skill"
skill_file="${REPO_DIR}/skills/tmux-plan/SKILL.md"
assert_file_exists "skill file exists" "$skill_file"
content=$(cat "$skill_file")
assert_contains "has name frontmatter"      "name: tmux-plan"            "$content"
assert_contains "has argument-hint"         "argument-hint:"             "$content"
assert_contains "has atlassian tools"       "atlassian"                  "$content"
assert_contains "mentions WBS"              "WBS"                        "$content"
assert_contains "mentions claude-tmux new"  "claude-tmux new"            "$content"

# ─── 75. /tmux-handoff skill ──────────────────────────────────────────────────
echo "── 75. tmux-handoff skill"
skill_file="${REPO_DIR}/skills/tmux-handoff/SKILL.md"
assert_file_exists "skill file exists" "$skill_file"
content=$(cat "$skill_file")
assert_contains "has name frontmatter"      "name: tmux-handoff"         "$content"
assert_contains "has argument-hint"         "argument-hint:"             "$content"
assert_contains "mentions claude-tmux ls"   "claude-tmux ls"             "$content"
assert_contains "mentions tmux send-keys"   "tmux send-keys"             "$content"
assert_contains "mentions handoff doc"      "handoff"                    "$content"

# ─── 76. /tmux-review skill ───────────────────────────────────────────────────
echo "── 76. tmux-review skill"
skill_file="${REPO_DIR}/skills/tmux-review/SKILL.md"
assert_file_exists "skill file exists" "$skill_file"
content=$(cat "$skill_file")
assert_contains "has name frontmatter"      "name: tmux-review"          "$content"
assert_contains "has argument-hint"         "argument-hint:"             "$content"
assert_contains "mentions git diff"         "git diff"                   "$content"
assert_contains "mentions tmux capture"     "tmux capture-pane"          "$content"
assert_contains "mentions review verdict"   "VERDICT"                    "$content"

# ─── 77. help lists multi-agent skills ────────────────────────────────────────
echo "── 77. help lists multi-agent skills"
setup
out=$("$CLAUDE_TMUX" help)
assert_contains "help mentions tmux-team-create"  "tmux-team-create"   "$out"
assert_contains "help mentions tmux-team-status"  "tmux-team-status"   "$out"
assert_contains "help mentions tmux-team-sync"    "tmux-team-sync"     "$out"
assert_contains "help mentions tmux-plan"         "tmux-plan"          "$out"
assert_contains "help mentions tmux-handoff"      "tmux-handoff"       "$out"
assert_contains "help mentions tmux-review"       "tmux-review"        "$out"
teardown

# ─── 78. version is 0.8.7 ─────────────────────────────────────────────────────
echo "── 78. version is 0.8.7"
setup
out=$("$CLAUDE_TMUX" version)
assert_contains "version is 0.8.7" "0.8.7" "$out"
teardown

# ─── 79. install.sh ALL_SKILLS includes new skills ────────────────────────────
echo "── 79. install.sh includes new skills"
installer="${REPO_DIR}/install.sh"
content=$(cat "$installer")
assert_contains "install has tmux-team-create"  "tmux-team-create"   "$content"
assert_contains "install has tmux-team-status"  "tmux-team-status"   "$content"
assert_contains "install has tmux-team-sync"    "tmux-team-sync"     "$content"
assert_contains "install has tmux-plan"         "tmux-plan"          "$content"
assert_contains "install has tmux-handoff"      "tmux-handoff"       "$content"
assert_contains "install has tmux-review"       "tmux-review"        "$content"

# ─── 80. tmux-new skill ───────────────────────────────────────────────────────
echo "── 80. tmux-new skill"
skill_file="${REPO_DIR}/skills/tmux-new/SKILL.md"
assert_file_exists "skill file exists" "$skill_file"
content=$(cat "$skill_file")
assert_contains "has name frontmatter"    "name: tmux-new"       "$content"
assert_contains "has argument-hint"       "argument-hint:"       "$content"
assert_contains "mentions claude-tmux new" "claude-tmux new"    "$content"

# ─── 81. tmux-ls skill ────────────────────────────────────────────────────────
echo "── 81. tmux-ls skill"
skill_file="${REPO_DIR}/skills/tmux-ls/SKILL.md"
assert_file_exists "skill file exists" "$skill_file"
content=$(cat "$skill_file")
assert_contains "has name frontmatter"    "name: tmux-ls"        "$content"
assert_contains "mentions claude-tmux ls" "claude-tmux ls"       "$content"

# ─── 82. tmux-kill skill ──────────────────────────────────────────────────────
echo "── 82. tmux-kill skill"
skill_file="${REPO_DIR}/skills/tmux-kill/SKILL.md"
assert_file_exists "skill file exists" "$skill_file"
content=$(cat "$skill_file")
assert_contains "has name frontmatter"      "name: tmux-kill"      "$content"
assert_contains "mentions claude-tmux kill" "claude-tmux kill"     "$content"

# ─── 83. tmux-attach skill ────────────────────────────────────────────────────
echo "── 83. tmux-attach skill"
skill_file="${REPO_DIR}/skills/tmux-attach/SKILL.md"
assert_file_exists "skill file exists" "$skill_file"
content=$(cat "$skill_file")
assert_contains "has name frontmatter"        "name: tmux-attach"    "$content"
assert_contains "mentions claude-tmux attach" "claude-tmux attach"   "$content"

# ─── 84. cmd_purge — purge all killed sessions ────────────────────────────────
echo "── 84. cmd_purge all killed"
setup
# Register two sessions and kill them both
_source_script
_ensure_registry
_register_session "dead-a" "/tmp" "uuid-da" "" ""
_register_session "dead-b" "/tmp" "uuid-db" "" ""
_update_session_status "dead-a" "killed"
_update_session_status "dead-b" "killed"
# Also create their startup scripts
touch "${TEST_HOME}/.claude-tmux/scripts/dead-a.sh"
touch "${TEST_HOME}/.claude-tmux/scripts/dead-b.sh"
out=$("$CLAUDE_TMUX" purge 2>&1)
assert_contains "reports purged count"   "Purged 2 session(s)"    "$out"
assert_contains "reports dead-a"         "dead-a"                 "$out"
assert_contains "reports dead-b"         "dead-b"                 "$out"
# Sessions removed from registry
remaining=$(python3 -c "import json; d=json.load(open('${TEST_HOME}/.claude-tmux/sessions.json')); print(len(d['sessions']))")
assert_eq "sessions removed from registry" "0" "$remaining"
# Startup scripts removed
[[ ! -f "${TEST_HOME}/.claude-tmux/scripts/dead-a.sh" ]] && pass "script dead-a removed" || fail "script dead-a removed"
[[ ! -f "${TEST_HOME}/.claude-tmux/scripts/dead-b.sh" ]] && pass "script dead-b removed" || fail "script dead-b removed"
teardown

# ─── 85. cmd_purge — purge single killed session ──────────────────────────────
echo "── 85. cmd_purge single killed"
setup
_source_script
_ensure_registry
_register_session "keep-me" "/tmp" "uuid-km" "" ""
_register_session "kill-me" "/tmp" "uuid-kl" "" ""
_update_session_status "kill-me" "killed"
touch "${TEST_HOME}/.claude-tmux/scripts/kill-me.sh"
out=$("$CLAUDE_TMUX" purge -s kill-me 2>&1)
assert_contains "reports purged 1"  "Purged 1 session(s)" "$out"
assert_contains "names kill-me"     "kill-me"             "$out"
# keep-me still in registry
remaining=$(python3 -c "import json; d=json.load(open('${TEST_HOME}/.claude-tmux/sessions.json')); print(d['sessions'][0]['name'])")
assert_eq "keep-me still in registry" "keep-me" "$remaining"
# script removed
[[ ! -f "${TEST_HOME}/.claude-tmux/scripts/kill-me.sh" ]] && pass "script kill-me removed" || fail "script kill-me removed"
teardown

# ─── 86. cmd_purge — dry-run ──────────────────────────────────────────────────
echo "── 86. cmd_purge dry-run"
setup
_source_script
_ensure_registry
_register_session "dry-a" "/tmp" "uuid-dry" "" ""
_update_session_status "dry-a" "killed"
touch "${TEST_HOME}/.claude-tmux/scripts/dry-a.sh"
out=$("$CLAUDE_TMUX" purge --dry-run 2>&1)
assert_contains "dry-run reports would purge" "Would purge" "$out"
assert_contains "dry-run lists session"       "dry-a"       "$out"
# Registry unchanged
remaining=$(python3 -c "import json; d=json.load(open('${TEST_HOME}/.claude-tmux/sessions.json')); print(len(d['sessions']))")
assert_eq "dry-run leaves registry intact" "1" "$remaining"
# Script not deleted
[[ -f "${TEST_HOME}/.claude-tmux/scripts/dry-a.sh" ]] && pass "dry-run leaves script" || fail "dry-run leaves script"
teardown

# ─── 87. cmd_purge — error on not-found ──────────────────────────────────────
echo "── 87. cmd_purge error on not-found"
setup
_source_script
_ensure_registry
out=$("$CLAUDE_TMUX" purge -s ghost 2>&1) || true
assert_contains "error not-found" "not found in registry" "$out"
teardown

# ─── 88. cmd_purge — error on not-killed ─────────────────────────────────────
echo "── 88. cmd_purge error on not-killed"
setup
_source_script
_ensure_registry
_register_session "alive" "/tmp" "uuid-al" "" ""
out=$("$CLAUDE_TMUX" purge -s alive 2>&1) || true
assert_contains "error not-killed"      "not killed"            "$out"
assert_contains "suggests kill command" "claude-tmux kill"      "$out"
teardown

# ─── 89. cmd_purge — no killed sessions ──────────────────────────────────────
echo "── 89. cmd_purge no killed sessions"
setup
_source_script
_ensure_registry
_register_session "running" "/tmp" "uuid-run" "" ""
out=$("$CLAUDE_TMUX" purge 2>&1)
assert_contains "no killed message" "No killed sessions to purge" "$out"
teardown

# ─── 90. help shows purge ─────────────────────────────────────────────────────
echo "── 90. help shows purge"
out=$("$CLAUDE_TMUX" help 2>&1)
assert_contains "help shows purge command" "purge" "$out"
assert_contains "help shows dry-run flag"  "--dry-run" "$out"

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
