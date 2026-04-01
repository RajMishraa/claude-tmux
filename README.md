# claude-tmux

A tmux session manager for [Claude Code](https://claude.ai/code).

Every Claude session lives inside a named, persistent tmux session — visible via `tmux ls`, resumable after you disconnect or reboot, and accessible remotely over SSH.

---

## Requirements

- [Claude Code CLI](https://claude.ai/code) (`claude`)
- [tmux](https://github.com/tmux/tmux) ≥ 2.0
- python3 (standard on macOS and most Linux distributions)

---

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/RajMishraa/claude-tmux/main/install.sh | bash
```

Or clone and install locally:

```bash
git clone https://github.com/RajMishraa/claude-tmux
cd claude-tmux
./install.sh
```

The installer:
1. Copies `claude-tmux` to `~/.local/bin/`
2. Creates the session registry at `~/.claude-tmux/sessions.json`
3. Registers a macOS LaunchAgent that restores your sessions on every login

> **Note:** Ensure `~/.local/bin` is on your `PATH`. If not, add this to `~/.zshrc` or `~/.bashrc`:
> ```bash
> export PATH="$HOME/.local/bin:$PATH"
> ```

---

## Usage

### Start a new session

```bash
claude-tmux new -s uan-project
```

- Creates a tmux session named `uan-project`
- Starts `claude` inside it and attaches your terminal immediately
- If a session with that name already exists, attaches to it

Pass Claude flags directly — no `--` separator needed:

```bash
claude-tmux new -s uan-project --dangerously-skip-permissions
claude-tmux new -s uan-project --model opus --dangerously-skip-permissions
```

Flags are stored in the session registry and replayed automatically when the session is restored after a reboot.

### List all sessions

```bash
claude-tmux ls
```

Output shows each session's name, live/stopped state, creation time, session UUID, and working directory:

```
NAME                   STATE      CREATED                SESSION ID                           CWD
──────────────────────────────────────────────────────────────────────────────────────────────────
uan-project            [live]     2026-04-02 14:30:00    3f2a1b4c-...                         /work/uan
api-refactor           [active]   2026-04-01 09:15:00    7e8d9f0a-...                         /work/api
```

`[live]` = tmux session is currently running. `[active]` = registered but not running (will be restored on next login).

### Attach to a session

```bash
claude-tmux attach -s uan-project
```

If the session is stopped, you'll be prompted to restore it.

### Restore sessions (after reboot)

```bash
claude-tmux restore
```

Recreates all `active` tmux sessions and resumes their Claude conversations by UUID. This runs automatically at login via the LaunchAgent — you do not need to call it manually.

### Kill a session

```bash
claude-tmux kill -s uan-project
```

Kills the tmux session and marks it as `killed` in the registry.

### Print version

```bash
claude-tmux version
```

---

## How it works

| Feature | Mechanism |
|---|---|
| Named sessions | `tmux new-session -s <name>` + `claude --name <name>` |
| Conversation resume | `claude --session-id <uuid>` on start; `claude --resume <uuid>` on restore |
| Reboot persistence | `~/Library/LaunchAgents/com.user.claude-tmux-restore.plist` runs `restore` at login |
| Startup reliability | Session startup written to `~/.claude-tmux/scripts/<name>.sh` and executed directly — no `send-keys` timing issues |
| Safe registry writes | `sessions.json` written atomically via temp file + rename |
| Remote access | SSH into your machine → `tmux attach -t <session-name>` |

### Session registry

All sessions are recorded in `~/.claude-tmux/sessions.json`:

```json
{
  "sessions": [
    {
      "name": "uan-project",
      "session_id": "3f2a1b4c-0000-0000-0000-000000000001",
      "cwd": "/Users/you/work/uan",
      "created_at": "2026-04-02T14:30:00Z",
      "status": "active",
      "args": ["--dangerously-skip-permissions"]
    }
  ]
}
```

### Startup scripts

Each session has a corresponding script at `~/.claude-tmux/scripts/<name>.sh`. On restore, the script uses `claude --resume <uuid>` to pick up the exact conversation, replaying any flags (`--dangerously-skip-permissions`, `--model`, etc.) that were passed at creation time. When no UUID is present (sessions created before v0.2.0), it falls back to starting a fresh Claude session with the same name.

---

## Remote access

SSH into your machine and attach to any running Claude session:

```bash
ssh you@your-machine
tmux ls                        # see all sessions
tmux attach -t uan-project     # attach to a specific one
```

---

## Troubleshooting

**`claude: command not found` when restoring after reboot**

The startup script uses the full path to the `claude` binary captured at session creation time. If you moved or reinstalled Claude Code, re-create the session with `claude-tmux new -s <name>` to refresh the path.

**Session shows `[active]` but won't restore**

Run `claude-tmux restore` manually to see the error output. Common cause: the working directory no longer exists. The restore falls back to `$HOME` in this case.

**`sessions.json` is corrupted**

Reset it:
```bash
echo '{"sessions":[]}' > ~/.claude-tmux/sessions.json
```

---

## Running tests

```bash
./tests/test_claude_tmux.sh
```

No dependencies beyond bash and python3.

---

## Uninstall

```bash
./uninstall.sh
```

This kills all registered sessions, unloads the LaunchAgent, and removes the binary. The session registry (`~/.claude-tmux/`) is kept so you can reference past sessions.

To fully remove everything:
```bash
./uninstall.sh
rm -rf ~/.claude-tmux
```

---

## Changelog

See [CHANGELOG.md](CHANGELOG.md).
