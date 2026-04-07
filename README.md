# claude-tmux

Never lose a Claude session again.

`claude-tmux` wraps [Claude Code](https://claude.ai/code) in a named tmux session so your work persists across disconnects, terminal crashes, and reboots. Pick up exactly where you left off — on your laptop, from a remote machine, or from your phone.

---

## Quick start

```bash
# Install
curl -fsSL https://raw.githubusercontent.com/RajMishraa/claude-tmux/main/install.sh | bash

# Start a session
claude-tmux new -s my-project

# Detach any time with Ctrl+B D — the session keeps running
# Come back later:
claude-tmux attach -s my-project
```

---

## Requirements

| Dependency | Install |
|---|---|
| [Claude Code CLI](https://claude.ai/code) | See claude.ai/code |
| tmux ≥ 2.0 | `brew install tmux` / `sudo apt install tmux` |
| python3 | Included on macOS and most Linux distros |

---

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/RajMishraa/claude-tmux/main/install.sh | bash
```

Or clone and run locally:

```bash
git clone https://github.com/RajMishraa/claude-tmux
cd claude-tmux
./install.sh
```

> **PATH check:** If `claude-tmux` isn't found after install, add this to your `~/.zshrc` or `~/.bashrc` and restart your shell:
> ```bash
> export PATH="$HOME/.local/bin:$PATH"
> ```

> **macOS:** The installer registers a LaunchAgent that automatically restores your sessions on login.
>
> **Linux:** Add this to your `~/.bashrc` or `~/.zshrc` for the same behaviour:
> ```bash
> claude-tmux restore &
> ```

---

## Commands

### `new` — start a session

```bash
claude-tmux new -s <name> [claude flags...]
```

Creates a tmux session and starts Claude inside it. Any flags after the session name are forwarded directly to Claude.

```bash
# Plain session
claude-tmux new -s uan-project

# Skip permission prompts (you opt in — not enabled by default)
claude-tmux new -s uan-project --dangerously-skip-permissions

# Choose a model
claude-tmux new -s uan-project --model opus

# Combine flags
claude-tmux new -s uan-project --model opus --dangerously-skip-permissions
```

Group sessions by tag:

```bash
# Team of agents working on JIRA tasks
claude-tmux new -s ticket-triage --tag jira
claude-tmux new -s backlog-grooming --tag jira

# Development agents
claude-tmux new -s api-refactor --tag dev --dangerously-skip-permissions
claude-tmux new -s frontend-fix --tag dev
```

If a session with that name already exists, this attaches to it instead of creating a new one.

> Flags you pass are **saved** and replayed automatically if the session is restored after a reboot — no need to remember them.

---

### `attach` — return to a session

```bash
claude-tmux attach -s <name>
```

Reattaches your terminal to a running session. If the session isn't running, you'll be offered to restore it.

---

### `ls` — see all sessions

```bash
claude-tmux ls             # all sessions
claude-tmux ls --tag jira  # only jira sessions
```

```
NAME                   STATE      TAG            CREATED                CWD
──────────────────────────────────────────────────────────────────────
uan-project            [live]     2026-04-02 14:30:00    /work/uan
api-refactor           [active]   2026-04-01 09:15:00    /work/api
old-spike              [killed]   2026-03-28 10:00:00    /work/spike
```

- `[live]` — tmux session is currently running
- `[active]` — not running, will be restored on next login
- `[killed]` — manually stopped

---

### `url` — view the remote session URL

```bash
claude-tmux url -s <name>
```

When remote access is enabled in Claude Code (`/config` → Remote Access → Always), the session URL is auto-captured on creation. Use this command to retrieve it later — for example, to open the session on your phone or another machine.

If the URL wasn't captured at startup, running this command re-scans the tmux pane.

---

### `kill` — stop a session

```bash
claude-tmux kill -s <name>
```

Stops the tmux session and marks it as killed so it won't be restored on reboot.

---

### `restore` — bring back sessions after reboot

```bash
claude-tmux restore
```

Recreates all `active` sessions and resumes their Claude conversations from where they left off.

**This runs automatically on macOS login** — you only need to call it manually on Linux or if you want to restore immediately without rebooting.

---

## Remote access from another device

Claude Code has **built-in remote control**. Enable it once and you can connect to any session from your phone, tablet, or another machine without needing SSH.

**Enable remote access permanently:**

Inside any Claude session, run:
```
/config
```

Find the **Remote Access** setting and set it to **Always**. Claude will show you a connection URL you can open on any device.

Once enabled, every session you start with `claude-tmux new` will be remotely accessible by name.

---

## Troubleshooting

**`claude: command not found` after reboot**

The session was created before Claude Code moved. Re-create it:
```bash
claude-tmux kill -s <name>
claude-tmux new -s <name> [same flags as before]
```

**Session shows `[active]` but restore fails**

Run `claude-tmux restore` manually to see the error. Most common cause: the working directory was deleted or renamed. The restore falls back to `$HOME` automatically.

**`sessions.json` is corrupted**

```bash
echo '{"sessions":[]}' > ~/.claude-tmux/sessions.json
```

---

## Uninstall

```bash
./uninstall.sh          # removes binary + LaunchAgent, keeps session history
rm -rf ~/.claude-tmux   # also wipes session history
```

---

## Development

```bash
# Run tests (bash only, no dependencies)
./tests/test_claude_tmux.sh
```

See [CHANGELOG.md](CHANGELOG.md) for release history.
