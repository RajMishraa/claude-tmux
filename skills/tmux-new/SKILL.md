---
name: tmux-new
description: Create a new Claude session inside a named tmux session. Use when starting work on a project and you want persistent, resumable sessions.
disable-model-invocation: true
argument-hint: "<session-name> [claude flags...]"
allowed-tools: Bash(claude-tmux *)
---

# Create a tmux session

Create a new Claude tmux session. The session persists across disconnects and reboots.

**Arguments:** `$ARGUMENTS`

Run:

```bash
claude-tmux new -s $ARGUMENTS
```

If the session already exists, this attaches to it.

After creating, confirm by listing all sessions:

```bash
claude-tmux ls
```
