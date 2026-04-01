# Changelog

All notable changes to claude-tmux are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

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
