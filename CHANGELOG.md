# Changelog

All notable changes to claude-tmux are documented here.

## [0.2.0] - 2026-04-02

### Fixed
- **Session resume now works correctly after reboot** — Claude sessions are started with
  `--session-id <uuid>` and restored with `--resume <uuid>`. Previously used display name
  which is not a valid resume target.
- **Race condition on session start eliminated** — replaced `tmux send-keys` with a startup
  script written to disk. The script is passed directly to `tmux new-session`, so the command
  runs as soon as the shell is ready.
- **tmux availability check** — clear error message with install instructions if tmux is not found.
- **Session name validation** — names are restricted to `[a-zA-Z0-9_-]`. Spaces and special
  characters that break tmux session names are rejected with a descriptive error.
- **Atomic registry writes** — `sessions.json` is now written to a temp file and renamed into
  place, preventing corruption if the process is interrupted mid-write.
- **Uninstall kills running sessions first** — `uninstall.sh` reads the registry and kills all
  live tmux sessions before removing the binary and launchd plist.

### Added
- `claude-tmux version` subcommand
- Startup scripts persisted to `~/.claude-tmux/scripts/` for each session
- `python3` availability check with actionable error message
- `.gitignore`

## [0.1.0] - 2026-04-02

### Added
- Initial release
- `new`, `attach`, `ls`, `restore`, `kill` subcommands
- Session registry at `~/.claude-tmux/sessions.json`
- macOS LaunchAgent for auto-restore on login
- `install.sh` / `uninstall.sh`
