# claude-tmux

A tmux session manager for [Claude Code](https://claude.ai/code). Every Claude session lives in a named, persistent tmux session — visible via `tmux ls`, resumable after disconnect or reboot, and remotely accessible over SSH.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/rajmishra/claude-tmux/main/install.sh | bash
```

Or clone and install locally:

```bash
git clone https://github.com/rajmishra/claude-tmux
cd claude-tmux
./install.sh
```

## Usage

```bash
# Start a new Claude session in a named tmux session
claude-tmux new -s uan-project

# Start with extra Claude flags
claude-tmux new -s uan-project -- --model opus

# List all sessions (live and stopped)
claude-tmux ls

# Attach to a running session
claude-tmux attach -s uan-project

# Kill a session
claude-tmux kill -s uan-project

# Restore all active sessions (also runs automatically on login)
claude-tmux restore
```

## How it works

| Feature | Mechanism |
|---|---|
| Named sessions | `tmux new-session -s <name>` + `claude --name <name>` |
| Persistence across reboots | `~/Library/LaunchAgents/com.user.claude-tmux-restore.plist` restores sessions at login |
| Conversation history | Claude's built-in `--resume <name>` picks up where you left off |
| Remote access | SSH into your machine → `tmux attach -t <name>` |
| Session registry | `~/.claude-tmux/sessions.json` tracks all sessions |

## Session registry

All sessions are recorded in `~/.claude-tmux/sessions.json`:

```json
{
  "sessions": [
    {
      "name": "uan-project",
      "cwd": "/Users/you/work/uan",
      "created_at": "2026-04-02T14:30:00Z",
      "status": "active"
    }
  ]
}
```

## Remote access from mobile

SSH into your machine and attach to any running Claude session:

```bash
ssh you@your-machine
tmux attach -t uan-project
```

## Uninstall

```bash
./uninstall.sh
```
