# Changelog

All notable changes to claude-tmux are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [0.5.1] - 2026-04-07

### Changed
- **Multiple tags per session.** Use comma-separated or repeated `--tag`:
  `claude-tmux new -s task --tag jira,sprint-5` or `--tag jira --tag sprint-5`.
  Tags stored as a JSON array (`"tags": ["jira", "sprint-5"]`).
- `ls --tag <name>` matches any session that contains that tag.
- Legacy single `"tag"` field auto-migrated to `"tags"` array on read.
- 112-test suite (+4 tests for multi-tag, comma-separated, repeated flags).

## [0.5.0] - 2026-04-07

### Added
- **Session grouping with `--tag`** — Group sessions by task, team, or purpose:
  `claude-tmux new -s ticket-triage --tag jira`. Tags are stored in the registry and
  shown in `ls` output.
- **`claude-tmux ls --tag <group>`** — Filter sessions by tag. Only shows matching sessions.
- `ls` output now includes a TAGS column when any session has tags.
- 108-test suite (+15 tests for tag storage, filtering, multi-tag, arg parsing).

## [0.4.1] - 2026-04-07

### Added
- **Auto-capture session URL** — When remote access is enabled in Claude Code, the session URL
  is automatically captured from the tmux pane output after session creation and stored in the
  registry. Access it any time with `claude-tmux url -s <name>`.
- `claude-tmux url -s <name>` — Prints the stored remote URL. Also re-scans the tmux pane if
  the session is still live (useful if the URL wasn't captured on first try).
- `claude-tmux ls` — Now shows a URL column instead of session ID when any session has a stored URL.
- 93-test suite (+11 tests for URL storage, capture, display, and edge cases).

## [0.4.0] - 2026-04-02

### Changed
- **`--dangerously-skip-permissions` is no longer added by default.** Pass it explicitly when
  you want it: `claude-tmux new -s proj --dangerously-skip-permissions`. This gives users full
  control over Claude's permission mode.
- **No `--` separator required.** Claude flags can be passed directly after the session name:
  `claude-tmux new -s proj --model opus --dangerously-skip-permissions`. Any argument that is
  not `-s`/`--session` is forwarded to claude as-is.

### Added
- **Args stored in registry.** Extra flags passed to `new` are saved in `sessions.json` under
  an `args` array and replayed automatically on `restore`, so your session comes back with the
  exact same claude invocation.
- Test suite expanded to 82 tests covering: no-`--` arg parsing, implicit flag absence,
  explicit flag forwarding, multiple sessions in the same directory, restore arg replay,
  non-interactive `attach` (TTY check), live-vs-stopped `ls` state.

## [0.3.0] - 2026-04-02

### Fixed
- **PATH in startup scripts** — The claude binary path is now resolved at session creation time
  (via `command -v claude`) and hardcoded into the startup script. Sessions created by launchd
  at login no longer fail with "command not found" due to a minimal PATH environment.
- **Empty UUID on restore** — Sessions created before v0.2.0 have no stored UUID. Restore now
  falls back to `claude --name <name>` (fresh session) instead of crashing with `claude --resume ""`.
- **Double startup-script write in `_restore_single`** — `_write_new_script` was called then
  immediately overwritten. Split into `_write_new_script` (for `new`) and `_write_restore_script`
  (for `restore`); each is called exactly once.
- **`rename-window` race with `set -e`** — Added `|| true` so a window that closes before the
  rename (e.g. claude not found) doesn't abort the whole script.
- **`install.sh` now checks for `claude`** — Fails early with an install link if the Claude CLI
  is not found.

### Added
- Test suite at `tests/test_claude_tmux.sh` — 45 tests, plain bash, no dependencies.
- `_claude_bin` helper — resolves and validates the claude binary path once per invocation.
- Separate `_write_new_script` / `_write_restore_script` helpers (KISS: one function, one job).

## [0.2.0] - 2026-04-02

### Fixed
- **Session resume now works correctly after reboot** — Claude sessions are started with
  `--session-id <uuid>` and restored with `--resume <uuid>`. Previously used display name
  which is not a valid resume target.
- **Race condition on session start eliminated** — replaced `tmux send-keys` with a startup
  script written to disk. The script is passed directly to `tmux new-session`.
- **tmux availability check** — clear error message with install instructions if tmux is not found.
- **Session name validation** — names are restricted to `[a-zA-Z0-9_-]`.
- **Atomic registry writes** — `sessions.json` written via temp file + `os.replace`.
- **Uninstall kills running sessions first** — `uninstall.sh` reads registry and kills all
  live tmux sessions before removing the binary and launchd plist.

### Added
- `claude-tmux version` subcommand.
- Startup scripts persisted to `~/.claude-tmux/scripts/`.
- `python3` availability check.
- `.gitignore`.

## [0.1.0] - 2026-04-02

### Added
- Initial release.
- `new`, `attach`, `ls`, `restore`, `kill` subcommands.
- Session registry at `~/.claude-tmux/sessions.json`.
- macOS LaunchAgent for auto-restore on login (`~/Library/LaunchAgents/com.user.claude-tmux-restore.plist`).
- `install.sh` / `uninstall.sh`.
